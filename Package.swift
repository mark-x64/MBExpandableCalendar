// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MBExpandableCalendar",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(name: "MBExpandableCalendar", targets: ["MBExpandableCalendar"])
    ],
    targets: [
        .target(
            name: "MBExpandableCalendar",
            dependencies: [],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
