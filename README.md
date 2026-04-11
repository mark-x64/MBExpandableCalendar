# MBExpandableCalendar

[简体中文](README.zh-CN.md)

<p align="center">
  <img src="https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white" alt="Swift 6.0">
  <img src="https://img.shields.io/badge/iOS-18%2B-007AFF?logo=apple&logoColor=white" alt="iOS 18+">
  <img src="https://img.shields.io/badge/SPM-compatible-34C759" alt="SPM compatible">
  <img src="https://img.shields.io/badge/License-MIT-lightgrey" alt="MIT License">
</p>

A pure-SwiftUI calendar component that collapses smoothly between **month view** and **week view** via drag gesture, with horizontal month paging and per-date badge support.

## Screenshots

| Screenshots | Description |
|:---:|---|
| <img src="Assets/Screenshots/01-expanded-light.png" width="160"> <img src="Assets/Screenshots/02-expanded-dark.png" width="160"> | **Month View** — Full month grid with per-date badge counts. Adapts to 4–6 row months. Light and dark mode. |
| <img src="Assets/Screenshots/03-collapsed-light.png" width="160"> <img src="Assets/Screenshots/04-collapsed-dark.png" width="160"> | **Week View (Collapsed)** — Collapses to a single-week strip via drag gesture. Spring-animated with rubber-band overscroll feel. |
| <img src="Assets/Screenshots/05-4-rows.png" width="160"> <img src="Assets/Screenshots/06-6-rows.png" width="160"> | **Variable Row Count** — 4-row vs 6-row months. Calendar height animates smoothly as months change. |
| <img src="Assets/Screenshots/07-no-radius-no-shadow.png" width="160"> <img src="Assets/Screenshots/08-radius-no-shadow.png" width="160"> | **Content Styling** — The content area below the calendar is fully composable. Left: flat edge-to-edge. Right: rounded card. |
| <img src="Assets/Screenshots/09-custom-list.png" width="160"> | **Custom Content** — Any SwiftUI view works as the scrollable content area beneath the calendar. |

## Features

- **Month ↔ Week collapse** — drag-driven, spring-animated transition between full month grid and single-week strip
- **Horizontal month paging** — swipe left/right to navigate months with crossfade transition
- **Badge counts** — per-date badge overlay (top-right corner), driven by a `(Date) -> Int` closure
- **Rubber-band overscroll** — elastic feel when dragging past collapse bounds
- **Scroll-linked gesture** — collapse only activates when the content scroll view is at the top
- **Zero dependencies** — pure SwiftUI, no external packages

## Requirements

- iOS 18.0+
- Swift 6.0+
- Xcode 16.0+

> **Why iOS 18?** The month paging strip in `CompactCalendarView` is built on the SwiftUI scroll enhancements introduced in iOS 18: `scrollPosition(id:)`, `scrollTargetBehavior(.paging)`, `scrollTransition(.interactive, ...)`, `onScrollGeometryChange`, and `containerRelativeFrame`. These APIs are not available on iOS 17.

## Installation

### Swift Package Manager

Add the package in Xcode via **File → Add Package Dependencies**, or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/mark-x64/MBExpandableCalendar", from: "1.0.0")
]
```

Then add the target:

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "MBExpandableCalendar", package: "MBExpandableCalendar")
    ]
)
```

## Usage

### ExpandableCalendarContainer (recommended)

The full-featured container: calendar header on top, your scrollable content below, with built-in collapse gesture coordination.

```swift
import MBExpandableCalendar

struct CalendarScreen: View {
    @State private var selectedDate = Date()

    var body: some View {
        ExpandableCalendarContainer(
            selectedDate: $selectedDate,
            badgeCount: { date in
                Calendar.current.isDateInToday(date) ? 3 : 0
            }
        ) { selectedDate, listAtTop in
            List {
                Text("Selected: \(selectedDate, format: .dateTime.month().day())")
            }
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentOffset.y <= geo.contentInsets.top + 1
            } action: { _, atTop in
                listAtTop.wrappedValue = atTop
            }
        }
    }
}
```

> **Important:** The content closure must update the `listAtTop` binding via `.onScrollGeometryChange` (or equivalent) so the container knows when to allow the collapse gesture to activate.

### CompactCalendarView (standalone)

Use the calendar grid on its own when you need custom gesture handling or a non-standard layout:

```swift
import MBExpandableCalendar

CompactCalendarView(
    selectedDate: $date,
    badgeCount: { _ in 0 },
    collapse: collapseValue,           // 0 = month, 1 = week
    isDraggingVertically: isDragging,
    suppressTap: suppress
)
```

## API

### ExpandableCalendarContainer

| Parameter | Type | Description |
|-----------|------|-------------|
| `selectedDate` | `Binding<Date>` | Currently selected date |
| `badgeCount` | `(Date) -> Int` | Badge count for each date |
| `content` | `(Date, Binding<Bool>) -> Content` | Scrollable content below the calendar; receives the selected date and a `listAtTop` binding |

### CompactCalendarView

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `selectedDate` | `Binding<Date>` | — | Currently selected date |
| `badgeCount` | `(Date) -> Int` | — | Badge count for each date |
| `overscaleAnchor` | `UnitPoint` | `.center` | Anchor for rubber-band scale effect |
| `collapse` | `CGFloat` | `0` | Collapse progress: 0 = month, 1 = week |
| `isDraggingVertically` | `Bool` | `false` | Disables horizontal paging during vertical drag |
| `suppressTap` | `Bool` | `false` | Prevents date taps during a drag gesture |

## License

MIT
