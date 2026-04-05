# MBExpandableCalendar

[English](README.md)

一个 SwiftUI 日历组件，支持通过拖拽手势在**月视图**和**周视图**之间平滑折叠切换，带水平翻页和徽章角标。

## 截图

| 截图 | 说明 |
|:---:|---|
| <img src="Assets/Screenshots/01-expanded-light.png" width="160"> <img src="Assets/Screenshots/02-expanded-dark.png" width="160"> | **月视图（展开）** — 完整月份网格，每个日期支持角标计数。自适应 4–6 行月份，支持浅色和深色模式。 |
| <img src="Assets/Screenshots/03-collapsed-light.png" width="160"> <img src="Assets/Screenshots/04-collapsed-dark.png" width="160"> | **周视图（折叠）** — 通过拖拽手势折叠为单行周视图，弹簧动画 + 橡皮筋回弹效果。 |
| <img src="Assets/Screenshots/05-4-rows.png" width="160"> <img src="Assets/Screenshots/06-6-rows.png" width="160"> | **行数自适应** — 4 行月份与 6 行月份对比。切换月份时日历高度平滑动画过渡。 |
| <img src="Assets/Screenshots/07-no-radius-no-shadow.png" width="160"> <img src="Assets/Screenshots/08-radius-no-shadow.png" width="160"> | **内容区样式** — 日历下方的内容区完全可组合。左：无圆角无阴影的边到边布局；右：有圆角、无阴影的卡片样式。 |
| <img src="Assets/Screenshots/09-custom-list.png" width="160"> | **自定义内容** — 任意 SwiftUI 视图均可作为日历下方的可滚动内容区域。 |

## 特性

- **月 ↔ 周折叠** — 手势驱动、弹簧动画的月/周视图切换
- **水平翻页** — 左右滑动切换月份，带交叉淡入效果
- **徽章角标** — 每日右上角角标，支持自定义计数
- **橡皮筋回弹** — 拖拽超出边界时的弹性效果
- **滚动联动** — 仅在内容滚动到顶部时触发折叠手势
- **零依赖** — 纯 SwiftUI，无第三方依赖

## 环境要求

- iOS 17.0+
- Swift 6.0+
- Xcode 16+

## 安装

在 Xcode 中添加为本地 Swift Package：

1. File → Add Package Dependencies → Add Local...
2. 选择 `MBExpandableCalendar` 目录

或在 `Package.swift` 中：

```swift
.package(path: "../MBExpandableCalendar")
```

## 使用

### ExpandableCalendarContainer（推荐）

完整容器：上方日历 + 下方可滚动内容 + 内建折叠手势。

```swift
import MBExpandableCalendar

struct CalendarScreen: View {
    @State private var selectedDate = Date()

    var body: some View {
        ExpandableCalendarContainer(
            selectedDate: $selectedDate,
            badgeCount: { date in
                // 返回每个日期的角标数
                Calendar.current.isDateInToday(date) ? 3 : 0
            }
        ) { selectedDate, listAtTop in
            List {
                // 你的内容
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

> **注意：** content 闭包必须通过 `.onScrollGeometryChange`（或等效方式）更新 `listAtTop` 绑定，以便容器知道何时启用折叠手势。

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

### CompactCalendarView

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `selectedDate` | `Binding<Date>` | — | 当前选中日期 |
| `badgeCount` | `(Date) -> Int` | — | 每个日期的角标计数 |
| `overscaleAnchor` | `UnitPoint` | `.center` | 橡皮筋缩放锚点 |
| `collapse` | `CGFloat` | `0` | 折叠进度：0 = 月视图，1 = 周视图 |
| `isDraggingVertically` | `Bool` | `false` | 垂直拖拽时禁用水平翻页 |
| `suppressTap` | `Bool` | `false` | 拖拽期间禁止日期点击 |

### ExpandableCalendarContainer

| 参数 | 类型 | 说明 |
|------|------|------|
| `selectedDate` | `Binding<Date>` | 当前选中日期 |
| `badgeCount` | `(Date) -> Int` | 每个日期的角标计数 |
| `content` | `(Date, Binding<Bool>) -> Content` | 日历下方的可滚动内容 |

## 许可证

MIT
