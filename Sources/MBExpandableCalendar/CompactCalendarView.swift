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
        while days.count < 42 { days.append(nil) }
        let result = stride(from: 0, to: 42, by: 7).map { Array(days[$0..<$0 + 7]) }
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

    public init(
        selectedDate: Binding<Date>,
        badgeCount: @escaping @Sendable (Date) -> Int,
        overscaleAnchor: UnitPoint = .center,
        collapse: CGFloat = 0,
        isDraggingVertically: Bool = false,
        suppressTap: Bool = false
    ) {
        self._selectedDate = selectedDate
        self.badgeCount = badgeCount
        self.overscaleAnchor = overscaleAnchor
        self.collapse = collapse
        self.isDraggingVertically = isDraggingVertically
        self.suppressTap = suppressTap
    }

    // Horizontal paging: wide LazyHStack, no reset needed
    private static let pageRadius = 60
    private static let centerPage = pageRadius
    private static let pageRange = 0...(pageRadius * 2)

    @State private var baseMonth = Date()
    @State private var currentPage: Int? = centerPage
    @State private var rowsCache = MonthRowsCache()

    private let cal = Calendar.current
    private let cellH: CGFloat = 44

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
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.2), value: currentPage)
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
            ForEach(weekdaySymbols, id: \.self) { s in
                Text(s)
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
        .scrollDisabled(isDraggingVertically)
        .scrollClipDisabled()
        .frame(height: gridHeight)
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

    // MARK: - Navigation

    private func dateForPage(_ page: Int) -> Date {
        let offset = page - Self.centerPage
        return cal.date(byAdding: .month, value: offset, to: cal.dateInterval(of: .month, for: baseMonth)!.start)!
    }

    private func navigateAnimated(forward: Bool) {
        withAnimation(.spring(.bouncy)) {
            currentPage = (currentPage ?? Self.centerPage) + (forward ? 1 : -1)
        }
    }

    // MARK: - Layout

    /// The current grid height based on collapse progress.
    public var gridHeight: CGFloat {
        let monthH = cellH * 6
        let weekH = cellH
        let h = weekH + (monthH - weekH) * (1 - collapse)
        return max(weekH * 0.6, h)
    }

    private var overscaleY: CGFloat {
        if collapse < 0 {
            return 1 + (-collapse) * 0.15
        } else if collapse > 1 {
            return 1 - (collapse - 1) * 0.15
        }
        return 1
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
