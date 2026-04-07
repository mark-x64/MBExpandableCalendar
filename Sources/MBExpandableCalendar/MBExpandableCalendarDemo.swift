//
//  MBExpandableCalendarDemo.swift
//  MBExpandableCalendar
//
//  A self-contained demo view used by the Xcode preview below.
//  Anyone who fetches this package can open this file and hit
//  "Resume" in the canvas to play with the calendar live.
//

import SwiftUI

public struct MBExpandableCalendarDemoView: View {

    @State private var selectedDate = Date()
    @State private var roundedCorners = true
    @State private var shadowEnabled = true
    @State private var collapsed = false

    public init() {}

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
                List {
                    Section("Selected") {
                        Text(date, format: .dateTime.year().month(.wide).day().weekday(.wide))
                            .font(.headline)
                    }
                    Section("Demo items") {
                        ForEach(0..<12) { i in
                            Label("Task \(i + 1)", systemImage: "checkmark.circle")
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
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

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Rounded corners", isOn: $roundedCorners)
            Toggle("Drawer shadow", isOn: $shadowEnabled)
            Toggle("Collapsed (week view)", isOn: $collapsed.animation(.spring))
        }
        .font(.subheadline)
    }
}

#Preview("MBExpandableCalendar Demo") {
    MBExpandableCalendarDemoView()
}
