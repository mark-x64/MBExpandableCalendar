//
//  ExpandableCalendarContainer.swift
//  MBExpandableCalendar
//
//  UIKit-backed expandable calendar + drawer container.
//
//  Visual model (front → back):
//
//    ┌─ Scroll view (fills screen, masked) ── z = front ───┐
//    │  mask: transparent above calendarBottom              │
//    │        rounded-top opaque below calendarBottom       │
//    │                                                     │
//    │  content: pushed down by contentInset.top            │
//    │           scrolls normally after collapse            │
//    └─────────────────────────────────────────────────────┘
//    ┌─ Calendar + background ──────────── z = back ───────┐
//    │  calendarBg: white/black, screen top → cal bottom   │
//    │  calendarHC: CompactCalendarView at top              │
//    └─────────────────────────────────────────────────────┘
//
//  Scroll drives collapse:
//    scrollOffset = contentOffset.y + contentInset.top
//    collapse = scrollOffset / collapseRange
//    calendarBottom = monthCalH - collapseRange * collapse
//

import SwiftUI
import UIKit

// MARK: - RectangleCornerRadii convenience

extension RectangleCornerRadii {
    public static func top(leading: CGFloat, trailing: CGFloat) -> Self {
        .init(topLeading: leading, bottomLeading: 0, bottomTrailing: 0, topTrailing: trailing)
    }
    public static func top(_ radius: CGFloat) -> Self { .top(leading: radius, trailing: radius) }
    public static func bottom(leading: CGFloat, trailing: CGFloat) -> Self {
        .init(topLeading: 0, bottomLeading: leading, bottomTrailing: trailing, topTrailing: 0)
    }
    public static func bottom(_ radius: CGFloat) -> Self { .bottom(leading: radius, trailing: radius) }
}

// MARK: - DrawerShadow

public struct DrawerShadow: Sendable {
    public var color: Color
    public var radius: CGFloat
    public var x: CGFloat
    public var y: CGFloat

    public init(
        color: Color = Color.black.opacity(0.08),
        radius: CGFloat = 4,
        x: CGFloat = 0,
        y: CGFloat = -2
    ) {
        self.color = color
        self.radius = radius
        self.x = x
        self.y = y
    }

    public static let `default` = DrawerShadow()
}

// MARK: - Public API

public struct ExpandableCalendarContainer<Content: View>: UIViewControllerRepresentable {

    @Binding public var selectedDate: Date
    public let badgeCount: @Sendable (Date) -> Int
    public let cornerRadius: CGFloat
    public var drawerOffset: CGFloat
    public var drawerShadow: DrawerShadow?
    public var referenceDate: Date
    public var initialCollapse: CGFloat
    public var drawerBackgroundColor: UIColor
    @ViewBuilder public let content: (Date) -> Content

    public init(
        selectedDate: Binding<Date>,
        badgeCount: @escaping @Sendable (Date) -> Int,
        contentCornerRadius: CGFloat = 0,
        drawerOffset: CGFloat = 0,
        referenceDate: Date = Date(),
        initialCollapse: CGFloat = 0,
        drawerBackgroundColor: UIColor = .systemGroupedBackground,
        @ViewBuilder content: @escaping (Date) -> Content
    ) {
        self._selectedDate = selectedDate
        self.badgeCount = badgeCount
        self.cornerRadius = contentCornerRadius
        self.drawerOffset = drawerOffset
        self.referenceDate = referenceDate
        self.initialCollapse = initialCollapse
        self.drawerBackgroundColor = drawerBackgroundColor
        self.content = content
    }

    public init(
        selectedDate: Binding<Date>,
        badgeCount: @escaping @Sendable (Date) -> Int,
        contentCornerRadii: RectangleCornerRadii,
        drawerOffset: CGFloat = 0,
        referenceDate: Date = Date(),
        initialCollapse: CGFloat = 0,
        drawerBackgroundColor: UIColor = .systemGroupedBackground,
        @ViewBuilder content: @escaping (Date) -> Content
    ) {
        self._selectedDate = selectedDate
        self.badgeCount = badgeCount
        self.cornerRadius = max(contentCornerRadii.topLeading, contentCornerRadii.topTrailing)
        self.drawerOffset = drawerOffset
        self.referenceDate = referenceDate
        self.initialCollapse = initialCollapse
        self.drawerBackgroundColor = drawerBackgroundColor
        self.content = content
    }

    public func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    public func makeUIViewController(context: Context) -> CalendarContainerVC {
        let vc = CalendarContainerVC()
        vc.scrollView.delegate = context.coordinator
        context.coordinator.vc = vc
        return vc
    }

    public func updateUIViewController(_ vc: CalendarContainerVC, context: Context) {
        let c = context.coordinator
        c.parent = self
        vc.cornerRadius = cornerRadius
        vc.drawerOffset = drawerOffset
        vc.drawerShadow = drawerShadow
        vc.referenceDate = referenceDate
        vc.initialCollapse = initialCollapse
        vc.drawerBackgroundColor = drawerBackgroundColor

        // Rebuild the factory closure with current bindings/params. The factory
        // is invoked only when struct-identity inputs (selectedDate binding,
        // badgeCount closure, referenceDate) change — not per scroll frame.
        // Per-frame collapse / rowCountOverride updates go through
        // `vc.calendarState`, which the SwiftUI view observes directly, so
        // we no longer need to pay for a full tree rebuild every tick.
        let binding = $selectedDate
        let badgeFn = badgeCount
        let refDate = referenceDate
        vc.makeCalendarView = { [weak vc] in
            guard let vc = vc else { return AnyView(EmptyView()) }
            return AnyView(CompactCalendarView(
                selectedDate: binding,
                badgeCount: badgeFn,
                overscaleAnchor: .top,
                referenceDate: refDate,
                onContinuousRowCountChange: { [weak vc] count in
                    vc?.handleContinuousRowCountChange(count)
                },
                onButtonNavigate: { [weak vc] count in
                    vc?.animateRowCountChange(to: count)
                },
                sharedState: vc.calendarState
            ))
        }

        if let makeView = vc.makeCalendarView {
            vc.setCalendar(makeView())
        }
        vc.setContent(AnyView(content(selectedDate)))
    }

    // MARK: Coordinator

    public final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: ExpandableCalendarContainer
        weak var vc: CalendarContainerVC?
        private(set) var collapse: CGFloat = 0
        private var lastPushedCollapse: CGFloat = -2  // sentinel; first call always pushes
        private var dragStartedInCollapseZone: Bool = false

        init(parent: ExpandableCalendarContainer) { self.parent = parent }

        public func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let vc else { return }
            let offset = scrollView.contentOffset.y + scrollView.contentInset.top
            let cr = vc.collapseRange
            // Match historical semantics: cap at 1, allow negatives (overscroll
            // past top) so CompactCalendarView.overscaleY's rubber-band fires.
            let newCollapse: CGFloat = cr > 0 ? min(offset / cr, 1) : 0
            collapse = newCollapse

            // Only push into the observable when the value actually changed so
            // SwiftUI's registrar doesn't dirty views for no-op writes. The
            // host no longer reassigns `hc.rootView` per frame — state
            // mutations flow through @Observable, invalidating only the
            // subviews that read each property.
            if !vc.isUpdatingFromHorizontalSwipe,
               abs(newCollapse - lastPushedCollapse) > 0.001 {
                vc.calendarState.collapse = newCollapse
                lastPushedCollapse = newCollapse
                // Poke the UIHostingController so its intrinsicContentSize
                // refreshes this frame — otherwise calendarBg (bound to
                // hc.view.bottomAnchor) can lag one frame behind the
                // SwiftUI-computed gridHeight.
                vc.calendarHC?.view.invalidateIntrinsicContentSize()
            }
            vc.updateMask()
        }

        public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            guard let vc else { return }
            // Permanently stop re-pinning the initial inset/offset once the
            // user has actually touched the scroll view.
            vc.userHasInteracted = true
            // Only allow snap when the user actually started inside the collapse
            // zone. Otherwise list-area scrolling whose decel target happens to
            // land in [0, cr) gets yanked back to the boundary — perceived as a
            // sudden "reset to bottom" jump.
            let inset = scrollView.contentInset.top
            let pos = scrollView.contentOffset.y + inset
            dragStartedInCollapseZone = pos >= 0 && pos <= vc.collapseRange
        }

        public func scrollViewWillEndDragging(
            _ scrollView: UIScrollView, withVelocity v: CGPoint,
            targetContentOffset t: UnsafeMutablePointer<CGPoint>
        ) {
            guard dragStartedInCollapseZone else { return }
            let cr = vc?.collapseRange ?? 220
            let inset = scrollView.contentInset.top
            let target = t.pointee.y + inset
            guard target >= 0, target < cr else { return }
            t.pointee.y = (target < cr / 2 ? 0 : cr) - inset
        }

        public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            dragStartedInCollapseZone = false
        }
    }

    // MARK: Modifiers

    /// Configure the drawer shadow using SwiftUI-native parameters (mirrors `.shadow()`).
    public func drawerShadow(
        color: Color = Color.black.opacity(0.08),
        radius: CGFloat = 4,
        x: CGFloat = 0,
        y: CGFloat = -2
    ) -> Self {
        var copy = self
        copy.drawerShadow = DrawerShadow(color: color, radius: radius, x: x, y: y)
        return copy
    }
}

// MARK: - View Controller

public final class CalendarContainerVC: UIViewController {

    // ── Public ──
    let scrollView = _CalendarScrollView()
    /// Observable driver for the SwiftUI calendar. Host mutates `collapse`,
    /// `rowCountOverride`, `isDraggingVertically`, `suppressTap` directly and
    /// SwiftUI invalidates only the subviews that read each property, so the
    /// calendar no longer has to be re-instantiated on every scroll tick.
    let calendarState = CompactCalendarState()
    var cornerRadius: CGFloat = 0 {
        didSet {
            guard oldValue != cornerRadius else { return }
            maskLayer.cornerRadius = cornerRadius
        }
    }
    var drawerOffset: CGFloat = 0 {
        didSet {
            guard oldValue != drawerOffset, baseCalH > 0, insetConfigured else { return }
            let scrollOffset = scrollView.contentOffset.y + scrollView.contentInset.top
            let visibleCalH = computeVisibleCalH()
            scrollView.contentInset.top = visibleCalH
            scrollView.contentOffset.y = scrollOffset - visibleCalH
            contentMinHeightConstraint?.constant = -(safeTopInset + baseCalH + 44 + drawerOffset)
            updateMask()
        }
    }
    var referenceDate: Date = Date()
    var initialCollapse: CGFloat = 0
    var drawerShadow: DrawerShadow? {
        didSet { applyShadowConfig() }
    }
    var drawerBackgroundColor: UIColor = .systemGroupedBackground {
        didSet { scrollView.backgroundColor = drawerBackgroundColor }
    }
    var calendarHC: UIHostingController<AnyView>?

    // ── Private ──
    private var contentHC: UIHostingController<AnyView>?
    private let calendarBg = UIView()
    private let scrollContainer = UIView()  // shadow host: .mask() then .shadow()
    /// Simple CALayer used as the scroll view's mask. Using `cornerRadius` +
    /// `maskedCorners` avoids rebuilding a `UIBezierPath` / `CGPath` on every
    /// scroll tick; moving the mask is just a frame update.
    private let maskLayer = CALayer()
    private var monthCalH: CGFloat = 0
    private var baseCalH: CGFloat = 0
    private var insetConfigured = false
    private(set) var collapseRange: CGFloat = 44 * 5
    private var contentMinHeightConstraint: NSLayoutConstraint?
    private var currentInterpolatedRowCount: CGFloat = 6
    var isUpdatingFromHorizontalSwipe = false
    /// Latches the first time the user touches the scroll view.
    var userHasInteracted = false
    /// Safe-area top inset at the time the scroll view's inset was configured.
    /// Calendar hc.view is pinned to `safeAreaLayoutGuide.topAnchor`, but the
    /// scroll view is pinned to `view.topAnchor` (ignoring safe area). For the
    /// content top to line up with the calendar bottom, contentInset.top must
    /// be = safeAreaTop + monthCalH + drawerOffset.
    private var safeTopInset: CGFloat = 0

    /// Single source of truth for the "visible calendar height" = y coordinate
    /// in the view where the drawer (and content) should start.
    private func computeVisibleCalH() -> CGFloat {
        let cellH = CalendarMetrics.cellHeight
        return safeTopInset + baseCalH + currentInterpolatedRowCount * cellH + drawerOffset
    }

    // Calendar pan gesture → scroll driving
    private var calendarPanGR: UIPanGestureRecognizer?
    private var panStartOffset: CGFloat = 0
    private var calendarPanIsVertical = false

    // Button-navigation height animation (CADisplayLink driven)
    private var navAnimLink: CADisplayLink?
    private var navAnimStart: CFTimeInterval = 0
    private var navAnimFrom: CGFloat = 0
    private var navAnimTo: CGFloat = 0
    private var navAnimCollapseFrac: CGFloat = 0
    private let navAnimDuration: CFTimeInterval = 0.42

    // Factory closure set by updateUIViewController. Only invoked when
    // struct-identity inputs (selectedDate binding, badgeCount, referenceDate)
    // change — per-frame collapse / rowCountOverride updates go through
    // `calendarState` instead, avoiding hc.rootView reassignment.
    var makeCalendarView: (() -> AnyView)?

    // MARK: viewDidLoad

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        // ── Back layer: calendar background ──
        calendarBg.backgroundColor = .systemBackground
        calendarBg.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(calendarBg)

        // ── Front layer: container (shadow) → scroll view (mask) ──
        // Like SwiftUI's .mask().shadow(): mask first, then shadow on container.
        scrollContainer.backgroundColor = .clear
        scrollContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollContainer)

        scrollView.backgroundColor = drawerBackgroundColor
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.contentInsetAdjustmentBehavior = .never
        // Mask: opaque black backing + rounded top corners. Rebuilding a
        // CAShapeLayer path every frame was one of the main jank sources;
        // a frame update on this layer is essentially free.
        maskLayer.backgroundColor = UIColor.black.cgColor
        maskLayer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        maskLayer.masksToBounds = true
        maskLayer.cornerRadius = cornerRadius
        scrollView.layer.mask = maskLayer
        scrollContainer.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollContainer.topAnchor.constraint(equalTo: view.topAnchor),
            scrollContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            scrollView.topAnchor.constraint(equalTo: scrollContainer.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: scrollContainer.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: scrollContainer.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: scrollContainer.bottomAnchor),

            calendarBg.topAnchor.constraint(equalTo: view.topAnchor),
            calendarBg.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            calendarBg.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    // MARK: Calendar

    func setCalendar(_ rootView: AnyView) {
        if let hc = calendarHC {
            hc.rootView = rootView
        } else {
            let hc = UIHostingController(rootView: rootView)
            hc.view.backgroundColor = .clear
            hc.view.translatesAutoresizingMaskIntoConstraints = false
            hc.sizingOptions = .intrinsicContentSize
            addChild(hc)
            view.insertSubview(hc.view, belowSubview: scrollContainer)
            hc.didMove(toParent: self)
            calendarHC = hc
            scrollView.calendarView = hc.view

            NSLayoutConstraint.activate([
                hc.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                hc.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                hc.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ])
            calendarBg.bottomAnchor.constraint(equalTo: hc.view.bottomAnchor).isActive = true

            // Pan gesture on calendar drives scroll for vertical drag → collapse
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handleCalendarPan(_:)))
            pan.delegate = self
            hc.view.addGestureRecognizer(pan)
            calendarPanGR = pan
        }
    }

    // MARK: Shadow

    private func applyShadowConfig() {
        if let s = drawerShadow {
            scrollContainer.layer.shadowColor = UIColor(s.color).cgColor
            scrollContainer.layer.shadowOpacity = 1          // opacity baked into Color
            scrollContainer.layer.shadowRadius = s.radius
            scrollContainer.layer.shadowOffset = CGSize(width: s.x, height: s.y)
        } else {
            scrollContainer.layer.shadowOpacity = 0
        }
    }

    // MARK: Content

    func setContent(_ rootView: AnyView) {
        if let hc = contentHC {
            hc.rootView = rootView
        } else {
            let hc = UIHostingController(rootView: rootView)
            hc.view.backgroundColor = .clear
            hc.view.translatesAutoresizingMaskIntoConstraints = false
            // Disable hc's automatic safe-area handling so the SwiftUI content
            // fills hc.view edge-to-edge. We manage inset/offset ourselves.
            hc.safeAreaRegions = []
            // Use intrinsic content sizing so hc.view.height follows SwiftUI's
            // natural measurement instead of the circular self-sizing
            // negotiation between autolayout and SwiftUI.
            hc.sizingOptions = .intrinsicContentSize
            addChild(hc); scrollView.addSubview(hc.view); hc.didMove(toParent: self)
            contentHC = hc

            let minH = hc.view.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.heightAnchor)
            contentMinHeightConstraint = minH

            NSLayoutConstraint.activate([
                // Apple-standard UIScrollView content layout: pin ALL four
                // edges to contentLayoutGuide (forming the scrollable content
                // bounds), plus an explicit widthAnchor == frameLayoutGuide.width
                // to disable horizontal scroll. The previous setup pinned
                // leading/trailing to frameLayoutGuide which left
                // contentLayoutGuide with no horizontal anchors → contentSize.width
                // ended up as 0, which can confuse UIScrollView's internal
                // scrollable-range calculation.
                hc.view.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
                hc.view.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
                hc.view.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
                hc.view.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
                hc.view.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
                minH,
            ])
        }
    }

    // MARK: Layout

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        measureCalendarIfNeeded()
        configureInsetIfNeeded()
        if !userHasInteracted {
            pinInitialOffsetIfIdle()
        }
        updateMask()
    }

    public override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        measureCalendarIfNeeded()
        configureInsetIfNeeded()
        if !userHasInteracted {
            pinInitialOffsetIfIdle()
        }
        updateMask()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !userHasInteracted {
            pinInitialOffsetIfIdle()
        }
        updateMask()
    }

    /// Re-set contentInset AND contentOffset to the intended initial state if
    /// the user is not currently interacting with the scroll view. Idempotent
    /// and safe to call repeatedly. Critically, this does NOT gate on
    /// `insetConfigured` — the goal is to recover from cases where UIKit's
    /// layout cycle silently clobbered our contentInset.top back to 0, which
    /// clamps the scrollable min offset to 0 and makes the top of the content
    /// unreachable via downward drag.
    private func pinInitialOffsetIfIdle() {
        guard !userHasInteracted else { return }
        guard baseCalH > 0 else { return }
        guard !scrollView.isTracking && !scrollView.isDecelerating else { return }

        let visibleCalH = computeVisibleCalH()
        if abs(scrollView.contentInset.top - visibleCalH) > 0.5 {
            scrollView.contentInset.top = visibleCalH
            scrollView.verticalScrollIndicatorInsets.top = visibleCalH
        }
        let clamped = min(max(initialCollapse, 0), 1)
        let target = clamped * collapseRange - visibleCalH
        if abs(scrollView.contentOffset.y - target) > 0.5 {
            scrollView.contentOffset.y = target
        }
    }

    public override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        // Safe-area top may become known after configureInsetIfNeeded already
        // ran with an estimate of 0. Reconcile contentInset and contentOffset
        // against the new value here.
        let newSafeTop = view.safeAreaInsets.top
        if insetConfigured {
            scrollView.contentInset.bottom = view.safeAreaInsets.bottom
        }
        if insetConfigured && abs(newSafeTop - safeTopInset) > 0.5 {
            let oldVisible = computeVisibleCalH()
            let scrollOffset = scrollView.contentOffset.y + scrollView.contentInset.top
            safeTopInset = newSafeTop
            let newVisible = computeVisibleCalH()
            scrollView.contentInset.top = newVisible
            scrollView.verticalScrollIndicatorInsets.top = newVisible
            contentMinHeightConstraint?.constant = -(safeTopInset + baseCalH + 44 + drawerOffset)
            // Preserve scroll progress across the safe-area change.
            scrollView.contentOffset.y = scrollOffset - newVisible
            _ = oldVisible // silence warning
        }
        configureInsetIfNeeded()
        if !userHasInteracted {
            pinInitialOffsetIfIdle()
        }
        updateMask()
    }

    private func measureCalendarIfNeeded() {
        guard monthCalH == 0, let hc = calendarHC else { return }
        let w = view.bounds.width > 0 ? view.bounds.width : UIScreen.main.bounds.width
        var h = hc.sizeThatFits(in: CGSize(width: w, height: .greatestFiniteMagnitude)).height
        if h <= 10 {
            hc.view.setNeedsLayout()
            hc.view.layoutIfNeeded()
            h = hc.view.frame.height
        }
        guard h > 10 else { return }
        monthCalH = h
    }

    private func configureInsetIfNeeded() {
        guard monthCalH > 0, !insetConfigured else { return }

        let cellH = CalendarMetrics.cellHeight
        let rowCount = computeMonthRowCount(for: referenceDate)
        // gridHeight uses actual row count; baseCalH = non-grid portion.
        baseCalH = monthCalH - CGFloat(rowCount) * cellH
        currentInterpolatedRowCount = CGFloat(rowCount)
        collapseRange = CGFloat(rowCount - 1) * cellH

        // Capture the current safe-area top. calendarHC is pinned to the safe
        // area, so contentInset must include it or content gets hidden behind
        // calendar (and cannot be revealed, because offset is already at min).
        safeTopInset = view.safeAreaInsets.top

        let visibleCalH = computeVisibleCalH()
        scrollView.contentInset.top = visibleCalH
        scrollView.verticalScrollIndicatorInsets.top = visibleCalH
        // Bottom inset: contentHC's hc.safeAreaRegions = [] tells SwiftUI not
        // to reserve home-indicator space at the VStack bottom, so we must do
        // it on the scroll view side. Without this, scrolling to max hides the
        // last contentInset.bottom's worth of content under the home indicator.
        scrollView.contentInset.bottom = view.safeAreaInsets.bottom
        // Content min height: ensure drawer fills screen when collapsed.
        contentMinHeightConstraint?.constant = -(safeTopInset + baseCalH + cellH + drawerOffset)
        insetConfigured = true

        // Apply initial collapse (0 = expanded, 1 = collapsed)
        let clamped = min(max(initialCollapse, 0), 1)
        scrollView.contentOffset.y = clamped * collapseRange - visibleCalH
    }

    // MARK: Mask

    func updateMask() {
        guard baseCalH > 0, insetConfigured else { return }
        let w = view.bounds.width
        let h = view.bounds.height
        guard w > 0 else { return }

        let visibleCalH = computeVisibleCalH()
        let scrollOffset = scrollView.contentOffset.y + scrollView.contentInset.top
        let ec = collapseRange > 0 ? min(max(scrollOffset / collapseRange, 0), 1) : CGFloat(0)
        // When overscrolling past top (scrollOffset < 0), push drawer down with it
        let overscroll = max(-scrollOffset, 0)
        let calBottom = visibleCalH - collapseRange * ec + overscroll
        let r = cornerRadius

        // Mask lives on scrollView.layer whose coordinate system shifts by
        // contentOffset. Add contentOffset.y to keep the mask fixed on screen
        // at calBottom. A CALayer frame update is ~free compared to the old
        // per-frame UIBezierPath → cgPath rebuild.
        let maskY = calBottom + scrollView.contentOffset.y
        let maskFrame = CGRect(x: 0, y: maskY, width: w, height: h - calBottom + 2000)

        // Shadow path still needs a CGPath. Build it via CG's direct API
        // (avoids UIBezierPath bridging) and round all four corners — bottom
        // corners are far below screen at `+2000` so the difference is invisible.
        let shadowRect = CGRect(x: 0, y: calBottom, width: w, height: h - calBottom + 2000)
        let shadowPath = CGPath(
            roundedRect: shadowRect,
            cornerWidth: r,
            cornerHeight: r,
            transform: nil
        )

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        maskLayer.frame = maskFrame
        if maskLayer.cornerRadius != r {
            maskLayer.cornerRadius = r
        }
        scrollContainer.layer.shadowPath = shadowPath
        CATransaction.commit()

        // Keep scroll indicator below calendar
        scrollView.verticalScrollIndicatorInsets.top = calBottom
    }

    // MARK: Calendar Pan → Scroll

    @objc private func handleCalendarPan(_ pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .began:
            let v = pan.velocity(in: view)
            // Treat as horizontal only when we have a clear, strong horizontal
            // signal. Otherwise default to vertical — slow/ambiguous gestures
            // where velocity ≈ (0, 0) would otherwise be misclassified and
            // can strand the drawer mid-drag.
            let horizontalLock: CGFloat = 10  // pt/s; below this, signal is noise
            calendarPanIsVertical = !(abs(v.x) > abs(v.y) && abs(v.x) > horizontalLock)
            if calendarPanIsVertical {
                // Kill any in-flight snap animation or deceleration from a
                // previous release. Without this, a running
                // setContentOffset(animated:) (e.g. from snapAfterCalendarPan)
                // keeps writing toward its old target while `.changed` below
                // writes the user's finger position, and the two fight each
                // frame — the user perceives it as juddering / snapping back
                // to the old target while they're still dragging.
                //
                // Unconditional: if nothing's animating this is a no-op;
                // if something is, the assignment cancels it.
                scrollView.setContentOffset(scrollView.contentOffset, animated: false)
                panStartOffset = scrollView.contentOffset.y
                calendarState.isDraggingVertically = true
                calendarState.suppressTap = true
                scrollView.delegate?.scrollViewDidScroll?(scrollView)
            }
        case .changed:
            guard calendarPanIsVertical else { return }
            let rawOffset = panStartOffset - pan.translation(in: view).y
            let inset = scrollView.contentInset.top
            let minOffset = -inset                        // fully expanded
            let maxOffset = collapseRange - inset          // fully collapsed
            let dim = scrollView.bounds.height

            if rawOffset < minOffset {
                let over = minOffset - rawOffset
                let rb = (1.0 - (1.0 / ((over * 0.55 / dim) + 1.0))) * dim
                scrollView.contentOffset.y = minOffset - rb
            } else if rawOffset > maxOffset {
                let over = rawOffset - maxOffset
                let rb = (1.0 - (1.0 / ((over * 0.55 / dim) + 1.0))) * dim
                scrollView.contentOffset.y = maxOffset + rb
            } else {
                scrollView.contentOffset.y = rawOffset
            }
        case .ended, .cancelled:
            if calendarPanIsVertical {
                calendarState.isDraggingVertically = false
                calendarState.suppressTap = false
                snapAfterCalendarPan(velocity: pan.velocity(in: view).y)
            }
            calendarPanIsVertical = false
        default: break
        }
    }

    private func snapAfterCalendarPan(velocity vy: CGFloat) {
        let inset = scrollView.contentInset.top
        let offset = scrollView.contentOffset.y + inset

        if offset < 0 {
            // Bounce back from overscroll — setContentOffset calls delegate each frame
            scrollView.setContentOffset(CGPoint(x: 0, y: -inset), animated: true)
            return
        }
        // offset > collapseRange: user released the calendar in the rubber-band
        // zone past collapsed. Because the calendar pan writes contentOffset
        // directly (bypassing UIKit's native deceleration), UIKit will not
        // bounce back on its own — we have to snap back to collapseRange.
        if offset > collapseRange {
            scrollView.setContentOffset(CGPoint(x: 0, y: collapseRange - inset), animated: true)
            return
        }

        let target: CGFloat
        if vy < -500 {
            target = 0
        } else if vy > 500 {
            target = collapseRange
        } else {
            target = offset < collapseRange / 2 ? 0 : collapseRange
        }
        // setContentOffset(animated:) properly fires scrollViewDidScroll every frame,
        // keeping mask and calendar in sync (unlike UIView.animate on contentOffset).
        scrollView.setContentOffset(CGPoint(x: 0, y: target - inset), animated: true)
    }

    // MARK: Programmatic Collapse

    /// Set the collapse fraction (0 = expanded, 1 = collapsed). For snapshotting / testing.
    public func setCollapseFraction(_ fraction: CGFloat) {
        guard insetConfigured else { return }
        let clamped = min(max(fraction, 0), 1)
        let target = clamped * collapseRange
        scrollView.contentOffset.y = target - scrollView.contentInset.top
    }

    // MARK: Dynamic Height

    func handleContinuousRowCountChange(_ newCount: CGFloat) {
        guard baseCalH > 0, insetConfigured else { return }
        guard abs(newCount - currentInterpolatedRowCount) > 0.01 else { return }
        // While a button-nav animation is running, onScrollGeometryChange fires with
        // intermediate values as the pager spring-scrolls toward the new page — those
        // values converge toward navAnimTo (and may briefly overshoot by ≤0.5 rows).
        // Keep the animation running unless the value is far from the target AND
        // diverging, which indicates a genuine user swipe toward a different month.
        if navAnimLink != nil {
            let distNow = abs(newCount - navAnimTo)
            let distWas = abs(currentInterpolatedRowCount - navAnimTo)
            if distNow <= 0.5 || distNow <= distWas + 0.01 { return }  // converging or within overshoot tolerance
            // User swiped away — cancel button-nav animation and clear the override.
            navAnimLink?.invalidate()
            navAnimLink = nil
            calendarState.rowCountOverride = nil
        }
        let cellH = CalendarMetrics.cellHeight
        let newVisibleCalH = safeTopInset + baseCalH + newCount * cellH + drawerOffset
        let newCollapseRange = (newCount - 1) * cellH

        // Preserve collapse fraction across row-count changes.
        let scrollOffset = scrollView.contentOffset.y + scrollView.contentInset.top
        let oldCR = collapseRange
        let collapseFrac = oldCR > 0 ? min(max(scrollOffset / oldCR, 0), 1) : CGFloat(0)

        currentInterpolatedRowCount = newCount
        collapseRange = newCollapseRange

        let newScrollOffset = collapseFrac * newCollapseRange

        isUpdatingFromHorizontalSwipe = true
        scrollView.contentInset.top = newVisibleCalH
        scrollView.contentOffset.y = newScrollOffset - newVisibleCalH
        isUpdatingFromHorizontalSwipe = false

        updateMask()
    }
    // MARK: Button-Navigation Height Animation

    func animateRowCountChange(to newCount: CGFloat) {
        guard baseCalH > 0, insetConfigured else { return }
        guard abs(newCount - currentInterpolatedRowCount) > 0.01 else { return }

        let scrollOffset = scrollView.contentOffset.y + scrollView.contentInset.top
        let oldCR = collapseRange
        navAnimCollapseFrac = oldCR > 0 ? min(max(scrollOffset / oldCR, 0), 1) : 0
        navAnimFrom = currentInterpolatedRowCount
        navAnimTo = newCount
        navAnimStart = CACurrentMediaTime()

        // Seed the override so the SwiftUI view's gridHeight doesn't jump on
        // the first render pass after currentPage changes (before the first
        // tick fires). State mutation is observed by CompactCalendarView.
        calendarState.rowCountOverride = navAnimFrom

        navAnimLink?.invalidate()
        let link = CADisplayLink(target: self, selector: #selector(navAnimTick))
        link.add(to: .main, forMode: .common)
        navAnimLink = link
    }

    @objc private func navAnimTick() {
        let elapsed = CACurrentMediaTime() - navAnimStart
        let raw = min(elapsed / navAnimDuration, 1.0)
        let t = 1 - pow(1 - raw, 3)   // ease-out cubic
        let cellH = CalendarMetrics.cellHeight
        let count = navAnimFrom + (navAnimTo - navAnimFrom) * t

        // Drive gridHeight (SwiftUI, via state), calendarBg (UIKit constraint
        // on hc.view), and mask/inset from the same `count` so they stay in
        // lockstep. No hc.rootView reassignment — state observation handles it.
        calendarState.rowCountOverride = count
        currentInterpolatedRowCount = count
        collapseRange = max((count - 1) * cellH, 0)

        let newVisibleCalH = safeTopInset + baseCalH + count * cellH + drawerOffset
        isUpdatingFromHorizontalSwipe = true
        scrollView.contentInset.top = newVisibleCalH
        scrollView.contentOffset.y = navAnimCollapseFrac * collapseRange - newVisibleCalH
        isUpdatingFromHorizontalSwipe = false

        // Kick UIHostingController so calendarBg (bound to hc.view.bottom)
        // tracks the new intrinsic size synchronously this frame.
        calendarHC?.view.invalidateIntrinsicContentSize()
        view.layoutIfNeeded()

        updateMask()

        if raw >= 1.0 {
            navAnimLink?.invalidate()
            navAnimLink = nil
            // Clear the override so normal scroll-driven updates resume.
            calendarState.rowCountOverride = nil
        }
    }
}

// MARK: - UIGestureRecognizerDelegate

extension CalendarContainerVC: UIGestureRecognizerDelegate {
    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer === calendarPanGR
    }
}

// MARK: - Custom scroll view with hit-test forwarding

final class _CalendarScrollView: UIScrollView {
    weak var calendarView: UIView?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // Forward touches in the calendar area to the calendar view.
        // A separate UIPanGestureRecognizer on the calendar drives
        // the scrollView for vertical drag (collapse).
        if let cal = calendarView {
            let calPoint = convert(point, to: cal)
            if cal.bounds.contains(calPoint),
               let hit = cal.hitTest(calPoint, with: event) {
                return hit
            }
        }
        return super.hitTest(point, with: event)
    }
}
