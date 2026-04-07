//
//  MBExpandableCalendarDemo.swift
//  MBExpandableCalendar
//
//  A self-contained demo view used by the Xcode preview below.
//  Anyone who fetches this package can open this file and hit
//  "Resume" in the canvas to play with the calendar live.
//

import SwiftUI

/// Demo content style: stock SwiftUI `List` (introduces a nested
/// scroll view) vs. plain `LazyVStack` (single scroll, recommended).
public enum MBDemoContentStyle: String, CaseIterable, Sendable {
    case list = "List (nested scroll)"
    case lazyVStack = "LazyVStack (single scroll)"
}

public struct MBExpandableCalendarDemoView: View {

    @State private var selectedDate = Date()
    @State private var roundedCorners = true
    @State private var shadowEnabled = true
    @State private var collapsed = false

    private let contentStyle: MBDemoContentStyle

    public init(contentStyle: MBDemoContentStyle = .list) {
        self.contentStyle = contentStyle
    }

    public var body: some View {
        let cornerRadius: CGFloat = roundedCorners ? 24 : 0

        return ZStack(alignment: .bottom) {
            ExpandableCalendarContainer(
                selectedDate: $selectedDate,
                badgeCount: { date in
                    // Sprinkle a few demo badges deterministically.
                    let day = Calendar.current.component(.day, from: date)
                    return [3, 7, 12, 18, 25].contains(day) ? (day % 3 + 1) : 0
                },
                contentCornerRadius: cornerRadius,
                initialCollapse: collapsed ? 1 : 0
            ) { date in
                switch contentStyle {
                case .list:
                    listContent(for: date)
                case .lazyVStack:
                    lazyVStackContent(for: date)
                }
            }
            .drawerShadow(
                color: shadowEnabled ? Color.black.opacity(0.18) : .clear,
                radius: shadowEnabled ? 12 : 0,
                x: 0,
                y: -4
            )
            .id(collapsed) // rebuild so initialCollapse takes effect when toggled
            .ignoresSafeArea(.container, edges: .bottom)

            controls
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding()
        }
    }

    // MARK: - Content variants

    @ViewBuilder
    private func listContent(for date: Date) -> some View {
        List {
            Section("Selected") {
                Text(date, format: .dateTime.year().month(.wide).day().weekday(.wide))
                    .font(.headline)
            }
            Section("Demo items") {
                ForEach(0..<30) { i in
                    Label("Task \(i + 1)", systemImage: "checkmark.circle")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func lazyVStackContent(for date: Date) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            Text(date, format: .dateTime.year().month(.wide).day().weekday(.wide))
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

            Text("Demo items")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                ForEach(0..<30) { i in
                    Label("Task \(i + 1)", systemImage: "checkmark.circle")
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    if i < 29 {
                        Divider().padding(.leading, 44)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 10))
            .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Rounded corners", isOn: $roundedCorners)
            Toggle("Drawer shadow", isOn: $shadowEnabled)
            Toggle("Collapsed (week view)", isOn: $collapsed.animation(.spring))
        }
        .font(.subheadline)
    }
}

#Preview("Demo · List (nested scroll)") {
    MBExpandableCalendarDemoView(contentStyle: .list)
}

#Preview("Demo · LazyVStack (single scroll)") {
    MBExpandableCalendarDemoView(contentStyle: .lazyVStack)
}
