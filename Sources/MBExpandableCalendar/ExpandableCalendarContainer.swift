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
    public var drawerBackgroundColor: UIColor = .systemGroupedBackground
    @ViewBuilder public let content: (Date) -> Content

    public init(
        selectedDate: Binding<Date>,
        badgeCount: @escaping @Sendable (Date) -> Int,
        contentCornerRadius: CGFloat = 0,
        drawerOffset: CGFloat = 0,
        referenceDate: Date = Date(),
        initialCollapse: CGFloat = 0,
        @ViewBuilder content: @escaping (Date) -> Content
    ) {
        self._selectedDate = selectedDate
        self.badgeCount = badgeCount
        self.cornerRadius = contentCornerRadius
        self.drawerOffset = drawerOffset
        self.referenceDate = referenceDate
        self.initialCollapse = initialCollapse
        self.content = content
    }

    public init(
        selectedDate: Binding<Date>,
        badgeCount: @escaping @Sendable (Date) -> Int,
        contentCornerRadii: RectangleCornerRadii,
        drawerOffset: CGFloat = 0,
        referenceDate: Date = Date(),
        initialCollapse: CGFloat = 0,
        @ViewBuilder content: @escaping (Date) -> Content
    ) {
        self._selectedDate = selectedDate
        self.badgeCount = badgeCount
        self.cornerRadius = max(contentCornerRadii.topLeading, contentCornerRadii.topTrailing)
        self.drawerOffset = drawerOffset
        self.referenceDate = referenceDate
        self.initialCollapse = initialCollapse
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

        vc.setCalendar(AnyView(CompactCalendarView(
            selectedDate: $selectedDate, badgeCount: badgeCount,
            overscaleAnchor: .top, collapse: c.collapse,
            isDraggingVertically: vc.isDraggingCalendar,
            suppressTap: vc.isDraggingCalendar,
            referenceDate: referenceDate,
            onContinuousRowCountChange: { [weak vc] count in
                vc?.handleContinuousRowCountChange(count)
            }
        )))
        vc.setContent(AnyView(content(selectedDate)))
    }

    // MARK: Coordinator

    public final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: ExpandableCalendarContainer
        weak var vc: CalendarContainerVC?
        private(set) var collapse: CGFloat = 0

        init(parent: ExpandableCalendarContainer) { self.parent = parent }

        public func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let vc else { return }
            let offset = scrollView.contentOffset.y + scrollView.contentInset.top
            collapse = vc.collapseRange > 0 ? min(offset / vc.collapseRange, 1) : 0

            if !vc.isUpdatingFromHorizontalSwipe {
                vc.setCalendar(AnyView(CompactCalendarView(
                    selectedDate: parent.$selectedDate, badgeCount: parent.badgeCount,
                    overscaleAnchor: .top, collapse: collapse,
                    isDraggingVertically: vc.isDraggingCalendar,
                    suppressTap: vc.isDraggingCalendar,
                    onContinuousRowCountChange: { [weak vc] count in
                        vc?.handleContinuousRowCountChange(count)
                    }
                )))
                vc.calendarHC?.view.invalidateIntrinsicContentSize()
                vc.calendarHC?.view.layoutIfNeeded()
            }
            vc.updateMask()
        }

        public func scrollViewWillEndDragging(
            _ scrollView: UIScrollView, withVelocity v: CGPoint,
            targetContentOffset t: UnsafeMutablePointer<CGPoint>
        ) {
            let cr = vc?.collapseRange ?? 220
            let inset = scrollView.contentInset.top
            let target = t.pointee.y + inset
            guard target >= 0, target < cr else { return }
            t.pointee.y = (target < cr / 2 ? 0 : cr) - inset
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
    var cornerRadius: CGFloat = 0
    var drawerOffset: CGFloat = 0 {
        didSet {
            guard oldValue != drawerOffset, baseCalH > 0, insetConfigured else { return }
            let scrollOffset = scrollView.contentOffset.y + scrollView.contentInset.top
            let visibleCalH = baseCalH + currentInterpolatedRowCount * 44 + drawerOffset
            scrollView.contentInset.top = visibleCalH
            scrollView.contentOffset.y = scrollOffset - visibleCalH
            contentMinHeightConstraint?.constant = -(baseCalH + 44 + drawerOffset)
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
    private let maskLayer = CAShapeLayer()
    private var monthCalH: CGFloat = 0
    private var baseCalH: CGFloat = 0
    private var insetConfigured = false
    private(set) var collapseRange: CGFloat = 44 * 5
    private var contentMinHeightConstraint: NSLayoutConstraint?
    private var currentInterpolatedRowCount: CGFloat = 6
    var isUpdatingFromHorizontalSwipe = false

    // Calendar pan gesture → scroll driving
    private var calendarPanGR: UIPanGestureRecognizer?
    private var panStartOffset: CGFloat = 0
    private var calendarPanIsVertical = false
    var isDraggingCalendar = false

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
            addChild(hc); scrollView.addSubview(hc.view); hc.didMove(toParent: self)
            contentHC = hc

            let minH = hc.view.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.heightAnchor)
            contentMinHeightConstraint = minH

            NSLayoutConstraint.activate([
                hc.view.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
                hc.view.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor),
                hc.view.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor),
                hc.view.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
                minH,
            ])
        }
    }

    // MARK: Layout

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        measureCalendarIfNeeded()
        configureInsetIfNeeded()
        updateMask()
    }

    public override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        configureInsetIfNeeded()
        updateMask()
    }

    public override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        configureInsetIfNeeded()
        updateMask()
    }

    private func measureCalendarIfNeeded() {
        guard monthCalH == 0, let hc = calendarHC else { return }
        let w = view.bounds.width > 0 ? view.bounds.width : UIScreen.main.bounds.width
        var h = hc.sizeThatFits(in: CGSize(width: w, height: .greatestFiniteMagnitude)).height
        if h <= 10 {
            hc.view.setNeedsLayout(); hc.view.layoutIfNeeded()
            h = hc.view.frame.height
        }
        guard h > 10 else { return }
        monthCalH = h
    }

    private func configureInsetIfNeeded() {
        guard monthCalH > 0, !insetConfigured else { return }
        guard view.window != nil else { return }

        let cellH: CGFloat = 44
        // Compute actual row count for the reference month.
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: referenceDate)
        let firstOfMonth = cal.date(from: comps)!
        let range = cal.range(of: .day, in: .month, for: firstOfMonth)!
        let firstWD = cal.component(.weekday, from: firstOfMonth)
        let offset = (firstWD - cal.firstWeekday + 7) % 7
        let rowCount = (offset + range.count + 6) / 7
        // gridHeight uses actual row count; baseCalH = non-grid portion.
        baseCalH = monthCalH - CGFloat(rowCount) * cellH
        currentInterpolatedRowCount = CGFloat(rowCount)
        collapseRange = CGFloat(rowCount - 1) * cellH

        // contentInset is based on the *visible* calendar height, not the full view height.
        let visibleCalH = baseCalH + CGFloat(rowCount) * cellH + drawerOffset
        scrollView.contentInset.top = visibleCalH
        scrollView.verticalScrollIndicatorInsets.top = visibleCalH
        // Content min height: ensure drawer fills screen when collapsed (baseCalH + one row).
        contentMinHeightConstraint?.constant = -(baseCalH + cellH + drawerOffset)
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

        let visibleCalH = baseCalH + currentInterpolatedRowCount * 44 + drawerOffset
        let scrollOffset = scrollView.contentOffset.y + scrollView.contentInset.top
        let ec = collapseRange > 0 ? min(max(scrollOffset / collapseRange, 0), 1) : CGFloat(0)
        // When overscrolling past top (scrollOffset < 0), push drawer down with it
        let overscroll = max(-scrollOffset, 0)
        let calBottom = visibleCalH - collapseRange * ec + overscroll
        let r = cornerRadius

        // Mask is on scrollView.layer whose coordinate system shifts by contentOffset.
        // Add contentOffset.y to keep the mask fixed on screen at calBottom.
        let maskY = calBottom + scrollView.contentOffset.y
        let rect = CGRect(x: 0, y: maskY, width: w, height: h - calBottom + 2000)
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: [.topLeft, .topRight],
            cornerRadii: CGSize(width: r, height: r)
        )
        // Shadow path in container coordinates (same as view coordinates)
        let shadowRect = CGRect(x: 0, y: calBottom, width: w, height: h - calBottom + 2000)
        let shadowPath = UIBezierPath(
            roundedRect: shadowRect,
            byRoundingCorners: [.topLeft, .topRight],
            cornerRadii: CGSize(width: r, height: r)
        )

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        maskLayer.path = path.cgPath
        scrollContainer.layer.shadowPath = shadowPath.cgPath
        CATransaction.commit()

        // Keep scroll indicator below calendar
        scrollView.verticalScrollIndicatorInsets.top = calBottom
    }

    // MARK: Calendar Pan → Scroll

    @objc private func handleCalendarPan(_ pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .began:
            let v = pan.velocity(in: view)
            calendarPanIsVertical = abs(v.y) > abs(v.x)
            if calendarPanIsVertical {
                panStartOffset = scrollView.contentOffset.y
                isDraggingCalendar = true
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
                isDraggingCalendar = false
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
        guard offset < collapseRange else { return }

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
        let cellH: CGFloat = 44
        let newVisibleCalH = baseCalH + newCount * cellH + drawerOffset
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
