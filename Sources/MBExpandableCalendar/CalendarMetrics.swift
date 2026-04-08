//
//  CalendarMetrics.swift
//  MBExpandableCalendar
//
//  Shared constants and helpers used by both CompactCalendarView and
//  ExpandableCalendarContainer. Keep this file free of SwiftUI/UIKit imports.
//

import Foundation

// MARK: - Constants

enum CalendarMetrics {
    /// Height of a single day cell, shared across all layout calculations.
    static let cellHeight: CGFloat = 44
}

// MARK: - Row Count

/// Returns the number of week rows needed to display the month containing `date`.
///
/// This is the single source of truth for the month-row-count calculation that
/// was previously duplicated in `CompactCalendarView.computeRowCount` and
/// `ExpandableCalendarContainer.configureInsetIfNeeded`.
func computeMonthRowCount(for date: Date) -> Int {
    let cal = Calendar.current
    let comps = cal.dateComponents([.year, .month], from: date)
    guard let firstOfMonth = cal.date(from: comps),
          let range = cal.range(of: .day, in: .month, for: firstOfMonth) else {
        return 6  // safe fallback: maximum possible row count
    }
    let firstWD = cal.component(.weekday, from: firstOfMonth)
    let offset = (firstWD - cal.firstWeekday + 7) % 7
    return (offset + range.count + 6) / 7
}
