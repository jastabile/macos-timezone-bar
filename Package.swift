// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TimeZoneBar",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure time-zone logic: no SwiftUI, fully unit-tested.
        .target(name: "TimeZoneCore"),
        // The menu bar app. Assembled into TimeZoneBar.app by scripts/build-app.sh.
        .executableTarget(name: "TimeZoneBar", dependencies: ["TimeZoneCore"]),
        .testTarget(name: "TimeZoneCoreTests", dependencies: ["TimeZoneCore"]),
    ]
)
