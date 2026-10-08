import SwiftUI
import TimeZoneCore

@main
struct TimeZoneBarApp: App {
    @StateObject private var model = ComparisonModel()

    var body: some Scene {
        MenuBarExtra("Time Zones", systemImage: "clock") {
            PanelView(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}
