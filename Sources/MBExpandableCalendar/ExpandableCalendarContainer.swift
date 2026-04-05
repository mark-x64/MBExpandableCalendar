//
//  ExpandableCalendarContainer.swift
//  MBExpandableCalendar
//
//  A layout container: CompactCalendarView on top, user-provided scrollable
//  content below, with a vertical drag gesture that collapses the calendar
//  from month view to week view.
//

import SwiftUI

/// A container that places a ``CompactCalendarView`` above arbitrary content,
/// linking vertical drag gestures to the calendar's month-to-week collapse.
///
/// The content closure receives:
/// - `selectedDate`: the date the user tapped on the calendar
/// - `listAtTop`: a binding the content **must** drive so the container knows
///   when the scroll view is at its top edge (enabling the collapse gesture).
///
/// Usage:
/// ```swift
/// ExpandableCalendarContainer(
///     selectedDate: $date,
///     badgeCount: { _ in 0 }
/// ) { selectedDate, listAtTop in
///     List { ... }
///         .onScrollGeometryChange(for: Bool.self) { geo in
///             geo.contentOffset.y <= geo.contentInsets.top + 1
///         } action: { _, atTop in
///             listAtTop.wrappedValue = atTop
///         }
/// }
/// ```
public struct ExpandableCalendarContainer<Content: View>: View {

    @Binding public var selectedDate: Date
    public let badgeCount: @Sendable (Date) -> Int
    @ViewBuilder public let content: (Date, Binding<Bool>) -> Content

    public init(
        selectedDate: Binding<Date>,
        badgeCount: @escaping @Sendable (Date) -> Int,
        @ViewBuilder content: @escaping (Date, Binding<Bool>) -> Content
    ) {
        self._selectedDate = selectedDate
        self.badgeCount = badgeCount
        self.content = content
    }

    // MARK: Collapse state
    @State private var collapse: CGFloat = 0
    @State private var collapseStart: CGFloat = 0
    @State private var isDraggingVertically = false
    @State private var suppressTap = false
    private let collapseDragRange: CGFloat = 350

    // MARK: List scroll boundary
    @State private var listAtTop = true

    public var body: some View {
        VStack(spacing: 0) {
            CompactCalendarView(
                selectedDate: $selectedDate,
                badgeCount: badgeCount,
                overscaleAnchor: .top,
                collapse: collapse,
                isDraggingVertically: isDraggingVertically,
                suppressTap: suppressTap
            )

            Divider()

            content(selectedDate, $listAtTop)
                .frame(maxHeight: .infinity)
                .scrollDisabled(isDraggingVertically)
        }
        .simultaneousGesture(collapseGesture)
    }

    // MARK: - Collapse Gesture

    private static func rubberBand(_ value: CGFloat) -> CGFloat {
        if value >= 0 && value <= 1 { return value }
        let overflow = value < 0 ? -value : value - 1
        let dampened = log2(1 + overflow * 3) / 6
        return value < 0 ? -dampened : 1 + dampened
    }

    private var effectiveCollapse: CGFloat { min(max(collapse, 0), 1) }

    private var collapseGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if !isDraggingVertically {
                    guard abs(value.translation.height) > abs(value.translation.width) else { return }
                    guard listAtTop else { return }

                    let swipingUp   = value.translation.height < 0
                    let swipingDown = value.translation.height > 0

                    // 已折叠 + 上滑 → 放行给 list 滚动
                    if swipingUp && effectiveCollapse >= 1 { return }
                    // 已展开 + 下拉 → 无需再展开
                    if swipingDown && effectiveCollapse <= 0 { return }

                    isDraggingVertically = true
                    suppressTap = true
                    collapseStart = collapse
                }
                let raw = collapseStart + (-value.translation.height / collapseDragRange)
                collapse = Self.rubberBand(raw)
            }
            .onEnded { value in
                defer {
                    isDraggingVertically = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { suppressTap = false }
                }
                guard isDraggingVertically else { return }

                let target: CGFloat = collapse > 0.5 ? 1 : (collapse < 0.5 ? 0 : (-value.velocity.height / collapseDragRange > 0 ? 1 : 0))

                withAnimation(.spring(response: 0.4, dampingFraction: 0.75, blendDuration: 0)) {
                    collapse = target
                }
            }
    }
}
