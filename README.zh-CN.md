# MBExpandableCalendar

[English](README.md)

<p align="center">
  <img src="https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white" alt="Swift 6.0">
  <img src="https://img.shields.io/badge/iOS-18%2B-007AFF?logo=apple&logoColor=white" alt="iOS 18+">
  <img src="https://img.shields.io/badge/SPM-compatible-34C759" alt="SPM compatible">
  <img src="https://img.shields.io/badge/License-MIT-lightgrey" alt="MIT License">
</p>

纯 SwiftUI 日历组件，支持通过拖拽手势在**月视图**和**周视图**之间平滑折叠切换，带水平月份翻页和每日徽章角标。

## 截图

| 截图 | 说明 |
|:---:|---|
| <img src="Assets/Screenshots/01-expanded-light.png" width="160"> <img src="Assets/Screenshots/02-expanded-dark.png" width="160"> | **月视图（展开）** — 完整月份网格，每个日期支持角标计数。自适应 4–6 行月份，支持浅色和深色模式。 |
| <img src="Assets/Screenshots/03-collapsed-light.png" width="160"> <img src="Assets/Screenshots/04-collapsed-dark.png" width="160"> | **周视图（折叠）** — 通过拖拽手势折叠为单行周视图，弹簧动画 + 橡皮筋回弹效果。 |
| <img src="Assets/Screenshots/05-4-rows.png" width="160"> <img src="Assets/Screenshots/06-6-rows.png" width="160"> | **行数自适应** — 4 行月份与 6 行月份对比。切换月份时日历高度平滑动画过渡。 |
| <img src="Assets/Screenshots/07-no-radius-no-shadow.png" width="160"> <img src="Assets/Screenshots/08-radius-no-shadow.png" width="160"> | **内容区样式** — 日历下方内容区完全可组合。左：边到边平铺；右：带圆角的卡片样式。 |
| <img src="Assets/Screenshots/09-custom-list.png" width="160"> | **自定义内容** — 任意 SwiftUI 视图均可作为日历下方的可滚动内容区域。 |

## 特性

- **月 ↔ 周折叠** — 手势驱动、弹簧动画的月/周视图切换
- **水平月份翻页** — 左右滑动切换月份，带交叉淡入效果
- **徽章角标** — 每日右上角角标，由 `(Date) -> Int` 闭包驱动
- **橡皮筋回弹** — 拖拽超出边界时的弹性效果
- **滚动联动** — 仅在内容列表滚动到顶部时触发折叠手势
- **零依赖** — 纯 SwiftUI，无第三方依赖

## 系统要求

- iOS 18.0+
- Swift 6.0+
- Xcode 16.0+

> **为什么需要 iOS 18？** `CompactCalendarView` 的月份翻页条基于 iOS 18 新增的 SwiftUI 滚动 API：`scrollPosition(id:)`、`scrollTargetBehavior(.paging)`、`scrollTransition(.interactive, ...)`、`onScrollGeometryChange` 和 `containerRelativeFrame`，这些 API 在 iOS 17 上不可用。

## 安装

### Swift Package Manager

在 Xcode 中选择 **File → Add Package Dependencies**，或在 `Package.swift` 中添加：

```swift
dependencies: [
    .package(url: "https://github.com/mark-x64/MBExpandableCalendar", from: "1.0.0")
]
```

然后添加 target：

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "MBExpandableCalendar", package: "MBExpandableCalendar")
    ]
)
```

## 使用

### ExpandableCalendarContainer（推荐）

完整容器：上方日历标题 + 下方可滚动内容，内建折叠手势协调逻辑。

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
                Text("选中：\(selectedDate, format: .dateTime.month().day())")
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

> **注意：** content 闭包必须通过 `.onScrollGeometryChange`（或等效方式）更新 `listAtTop` 绑定，容器据此判断何时允许激活折叠手势。

### CompactCalendarView（独立使用）

单独使用日历网格，自行控制手势和布局：

```swift
import MBExpandableCalendar

CompactCalendarView(
    selectedDate: $date,
    badgeCount: { _ in 0 },
    collapse: collapseValue,           // 0 = 月视图，1 = 周视图
    isDraggingVertically: isDragging,
    suppressTap: suppress
)
```

## API

### ExpandableCalendarContainer

| 参数 | 类型 | 说明 |
|------|------|------|
| `selectedDate` | `Binding<Date>` | 当前选中日期 |
| `badgeCount` | `(Date) -> Int` | 每个日期的角标计数 |
| `content` | `(Date, Binding<Bool>) -> Content` | 日历下方可滚动内容；接收选中日期和 `listAtTop` 绑定 |

### CompactCalendarView

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `selectedDate` | `Binding<Date>` | — | 当前选中日期 |
| `badgeCount` | `(Date) -> Int` | — | 每个日期的角标计数 |
| `overscaleAnchor` | `UnitPoint` | `.center` | 橡皮筋缩放锚点 |
| `collapse` | `CGFloat` | `0` | 折叠进度：0 = 月视图，1 = 周视图 |
| `isDraggingVertically` | `Bool` | `false` | 垂直拖拽时禁用水平翻页 |
| `suppressTap` | `Bool` | `false` | 拖拽期间禁止日期点击 |

## 许可证

MIT
