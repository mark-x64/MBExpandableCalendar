//
//  CompactCalendarView.swift
//  MBExpandableCalendar
//
//  LazyVGrid calendar with month/week collapse, horizontal paging, and badge support.
//  Driven externally via `collapse` (0 = month, 1 = week).
//

import SwiftUI

// MARK: - Month Rows Cache

/// Reference-type cache stored in @State: mutations don't trigger SwiftUI redraws.
/// During drag-collapse every frame reads from the cache, skipping Calendar date math.
private final class MonthRowsCache: @unchecked Sendable {
    private var store: [Int: [[Date?]]] = [:]
    private let cal = Calendar.current

    func rows(for date: Date) -> [[Date?]] {
        let comps = cal.dateComponents([.year, .month], from: date)
        let key = comps.year! * 13 + comps.month!
        if let cached = store[key] { return cached }

        let firstOfMonth = cal.date(from: comps)!
        let range = cal.range(of: .day, in: .month, for: firstOfMonth)!
        let firstWD = cal.component(.weekday, from: firstOfMonth)
        let offset = (firstWD - cal.firstWeekday + 7) % 7

        var days: [Date?] = Array(repeating: nil, count: offset)
        for day in range {
            days.append(cal.date(from: DateComponents(year: comps.year, month: comps.month, day: day)))
        }
        // Pad to complete last row only (actual row count: 4–6)
        let remainder = days.count % 7
        if remainder != 0 {
            days.append(contentsOf: Array(repeating: nil as Date?, count: 7 - remainder))
        }
        let total = days.count
        let result = stride(from: 0, to: total, by: 7).map { Array(days[$0..<$0 + 7]) }
        store[key] = result
        return result
    }
}

// MARK: - CompactCalendarView

/// A compact calendar that supports smooth month-to-week collapse animation.
///
/// - `selectedDate`: the currently selected date (two-way binding)
/// - `badgeCount`: closure returning a badge count for any given date
/// - `collapse`: 0 = full month view, 1 = single-week view (driven externally)
/// - `overscaleAnchor`: anchor point for the rubber-band overscale effect
/// - `isDraggingVertically`: when true, horizontal paging is disabled
/// - `suppressTap`: when true, date taps are ignored (prevents accidental taps during drag)
public struct CompactCalendarView: View {

    @Binding public var selectedDate: Date
    public let badgeCount: @Sendable (Date) -> Int
    public var overscaleAnchor: UnitPoint
    public var collapse: CGFloat
    public var isDraggingVertically: Bool
    public var suppressTap: Bool
    public var referenceDate: Date
    /// When set, overrides the grid height computation so the container can
    /// drive a smooth height animation independently of `currentPage`.
    public var rowCountOverride: CGFloat?
    public var onContinuousRowCountChange: (@MainActor @Sendable (CGFloat) -> Void)?
    /// Called when the user taps a prev/next button, with the target month's row count.
    /// The container should animate its height to match (vs. the continuous-scroll path).
    public var onButtonNavigate: (@MainActor @Sendable (CGFloat) -> Void)?

    public init(
        selectedDate: Binding<Date>,
        badgeCount: @escaping @Sendable (Date) -> Int,
        overscaleAnchor: UnitPoint = .center,
        collapse: CGFloat = 0,
        isDraggingVertically: Bool = false,
        suppressTap: Bool = false,
        referenceDate: Date = Date(),
        rowCountOverride: CGFloat? = nil,
        onContinuousRowCountChange: (@MainActor @Sendable (CGFloat) -> Void)? = nil,
        onButtonNavigate: (@MainActor @Sendable (CGFloat) -> Void)? = nil
    ) {
        self._selectedDate = selectedDate
        self.badgeCount = badgeCount
        self.overscaleAnchor = overscaleAnchor
        self.collapse = collapse
        self.isDraggingVertically = isDraggingVertically
        self.suppressTap = suppressTap
        self.referenceDate = referenceDate
        self.rowCountOverride = rowCountOverride
        self.onContinuousRowCountChange = onContinuousRowCountChange
        self.onButtonNavigate = onButtonNavigate
        _baseMonth = State(initialValue: referenceDate)
    }

    // Horizontal paging: wide LazyHStack, no reset needed
    private static let pageRadius = 60
    private static let centerPage = pageRadius
    private static let pageRange = 0...(pageRadius * 2)

    @State private var baseMonth: Date
    @State private var currentPage: Int? = centerPage
    @State private var rowsCache = MonthRowsCache()

    private let cal = Calendar.current
    private let cellH = CalendarMetrics.cellHeight

    private let weekdaySymbols: [String] = {
        let s = Calendar.current.veryShortStandaloneWeekdaySymbols
        let f = Calendar.current.firstWeekday - 1
        return Array(s[f...]) + Array(s[..<f])
    }()

    // MARK: Body

    public var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.bottom, 12)
            weekdayBar
                .padding(.bottom, 4)
            pager
        }
        .padding(.horizontal)
        .scaleEffect(y: overscaleY, anchor: overscaleAnchor)
        .onAppear {
            let count = CGFloat(rowsCache.rows(for: displayDate).count)
            onContinuousRowCountChange?(count)
        }
    }

    // MARK: Header

    private var displayDate: Date {
        dateForPage(currentPage ?? Self.centerPage)
    }

    private var header: some View {
        HStack {
            Button { navigateAnimated(forward: false) } label: {
                Image(systemName: "chevron.left")
            }
            Spacer()
            Text(displayDate, format: .dateTime.year().month(.wide))
                .font(.headline)
                .transaction { $0.animation = nil }
            Spacer()
            Button { navigateAnimated(forward: true) } label: {
                Image(systemName: "chevron.right")
            }
        }
        .padding(.top, 4)
    }

    // MARK: Weekday Bar

    private var weekdayBar: some View {
        HStack(spacing: 0) {
            // Use index as id: veryShortStandaloneWeekdaySymbols contains
            // duplicates in some locales (e.g. "S" for Sat/Sun in English),
            // and ForEach with `id: \.self` on duplicates is undefined behavior.
            ForEach(weekdaySymbols.indices, id: \.self) { i in
                Text(weekdaySymbols[i])
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Pager

    private var pager: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(Self.pageRange, id: \.self) { page in
                    self.page(for: dateForPage(page))
                        .containerRelativeFrame(.horizontal)
                        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                            content.opacity(1 - abs(phase.value))
                        }
                        .id(page)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $currentPage)
        .scrollDisabled(isDraggingVertically || effectiveCollapse > 0.99)
        .scrollClipDisabled()
        .frame(height: gridHeight)
        .simultaneousGesture(weekSwipeGesture)
        .onScrollGeometryChange(for: PagerMetrics.self) { geo in
            PagerMetrics(offsetX: geo.contentOffset.x, pageWidth: geo.containerSize.width)
        } action: { _, newValue in
            let interpolated = interpolateRowCount(offsetX: newValue.offsetX, pageWidth: newValue.pageWidth)
            onContinuousRowCountChange?(interpolated)
        }
    }

    // MARK: Single Page

    private var effectiveCollapse: CGFloat { min(max(collapse, 0), 1) }

    private func page(for date: Date) -> some View {
        let rows = rowsCache.rows(for: date)
        let anchor = anchorRow(in: rows, monthDate: date)
        let ec = effectiveCollapse
        let yOffset = -CGFloat(anchor) * cellH * ec
        let maxDist = max(anchor, rows.count - 1 - anchor)

        return VStack(spacing: 0) {
            ForEach(0..<rows.count, id: \.self) { i in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { j in
                        if let d = rows[i][j] {
                            dayCell(d, monthDate: date)
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity)
                                .frame(height: cellH)
                        }
                    }
                }
                .frame(height: cellH)
                .drawingGroup()
                .opacity(rowOpacity(row: i, anchor: anchor, maxDist: maxDist))
            }
        }
        .offset(y: yOffset)
        .frame(height: gridHeight, alignment: .top)
    }

    // MARK: Day Cell

    private func dayCell(_ date: Date, monthDate: Date) -> some View {
        let isSelected = cal.isDate(date, inSameDayAs: selectedDate)
        let isToday = cal.isDateInToday(date)
        let inMonth = cal.component(.month, from: date) == cal.component(.month, from: monthDate)
        let badge = badgeCount(date)

        return Text("\(cal.component(.day, from: date))")
            .font(.system(.callout, design: .rounded, weight: isToday ? .bold : .regular))
            .foregroundStyle(
                isSelected ? AnyShapeStyle(.white) :
                isToday     ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary)
            )
            .opacity(inMonth ? 1 : 0)
            .frame(maxWidth: .infinity)
            .frame(height: cellH)
            .contentShape(.rect)
            .background {
                if isSelected { Circle().fill(.tint) }
            }
            .overlay(alignment: .topTrailing) {
                if badge > 0 {
                    Text("\(badge)")
                        .font(.footnote)
                        .fontDesign(.rounded)
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(.red, in: .circle)
                }
            }
            .onTapGesture {
                guard !suppressTap else { return }
                selectedDate = date
            }
    }

    // MARK: - Week Swipe (collapsed state)

    private var weekSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 15)
            .onEnded { value in
                guard effectiveCollapse > 0.99 else { return }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                guard abs(value.translation.width) > 30 else { return }
                advanceWeek(forward: value.translation.width < 0)
            }
    }

    private func advanceWeek(forward: Bool) {
        let delta = forward ? 7 : -7
        guard let newDate = cal.date(byAdding: .day, value: delta, to: selectedDate) else { return }
        let oldPage = currentPage ?? Self.centerPage
        let oldMonth = dateForPage(oldPage)
        let crossedMonth = !cal.isDate(newDate, equalTo: oldMonth, toGranularity: .month)
        withAnimation(.spring(.bouncy)) {
            selectedDate = newDate
            if crossedMonth {
                currentPage = oldPage + (forward ? 1 : -1)
            }
        }
    }

    // MARK: - Navigation

    private func dateForPage(_ page: Int) -> Date {
        let offset = page - Self.centerPage
        return cal.date(byAdding: .month, value: offset, to: cal.dateInterval(of: .month, for: baseMonth)!.start)!
    }

    private func navigateAnimated(forward: Bool) {
        let newPage = (currentPage ?? Self.centerPage) + (forward ? 1 : -1)
        let newDate = dateForPage(newPage)
        let newCount = CGFloat(Self.computeRowCount(for: newDate))
        onButtonNavigate?(newCount)
        withAnimation(.spring(.bouncy)) {
            currentPage = newPage
        }
    }

    // MARK: - Layout

    /// The current grid height based on collapse progress (clamped to 0…1).
    /// Uses `rowCountOverride` when set (container-driven animation), otherwise
    /// computes from the displayed month's actual row count.
    public var gridHeight: CGFloat {
        let ec = effectiveCollapse
        let rows = rowCountOverride ?? CGFloat(Self.computeRowCount(for: displayDate))
        let monthH = cellH * rows
        let weekH = cellH
        return weekH + (monthH - weekH) * (1 - ec)
    }

    /// Row count for the month containing `date`, without allocating the full row array.
    private static func computeRowCount(for date: Date) -> Int {
        computeMonthRowCount(for: date)
    }

    private var overscaleY: CGFloat {
        if collapse < 0 {
            return 1 + (-collapse) * 0.15
        } else if collapse > 1 {
            return 1 - (collapse - 1) * 0.15
        }
        return 1
    }

    // MARK: - Row Count Interpolation

    private struct PagerMetrics: Equatable {
        var offsetX: CGFloat
        var pageWidth: CGFloat
    }

    private func interpolateRowCount(offsetX: CGFloat, pageWidth: CGFloat) -> CGFloat {
        guard pageWidth > 0 else { return CGFloat(Self.computeRowCount(for: displayDate)) }
        let fractionalPage = offsetX / pageWidth
        guard fractionalPage > 0 else { return CGFloat(Self.computeRowCount(for: displayDate)) }
        let leftIdx = max(Self.pageRange.lowerBound, min(Int(floor(fractionalPage)), Self.pageRange.upperBound))
        let rightIdx = min(leftIdx + 1, Self.pageRange.upperBound)
        let fraction = max(0, min(fractionalPage - CGFloat(leftIdx), 1))

        let leftCount = CGFloat(Self.computeRowCount(for: dateForPage(leftIdx)))
        let rightCount = CGFloat(Self.computeRowCount(for: dateForPage(rightIdx)))
        return leftCount + (rightCount - leftCount) * fraction
    }

    // MARK: - Row Helpers

    private func rowOpacity(row: Int, anchor: Int, maxDist: Int) -> CGFloat {
        guard row != anchor else { return 1 }
        let ec = effectiveCollapse
        guard ec > 0 else { return 1 }
        let distance = abs(row - anchor)
        let normDist = CGFloat(distance) / CGFloat(max(maxDist, 1))
        let speed: CGFloat = 1 + normDist
        return max(0, 1 - ec * speed)
    }

    private func anchorRow(in rows: [[Date?]], monthDate: Date) -> Int {
        if cal.isDate(monthDate, equalTo: selectedDate, toGranularity: .month) {
            for (i, row) in rows.enumerated() {
                if row.contains(where: { $0 != nil && cal.isDate($0!, inSameDayAs: selectedDate) }) {
                    return i
                }
            }
        }
        if cal.isDate(monthDate, equalTo: Date(), toGranularity: .month) {
            for (i, row) in rows.enumerated() {
                if row.contains(where: { $0 != nil && cal.isDateInToday($0!) }) {
                    return i
                }
            }
        }
        return 0
    }
}
