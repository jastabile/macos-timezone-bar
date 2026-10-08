import AppKit
import Combine
import SwiftUI
import TimeZoneCore

struct PanelView: View {
    @ObservedObject var model: ComparisonModel
    @State private var isAdding = false

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if isAdding {
                AddZoneView(model: model) { isAdding = false }
            } else if model.zoneIDs.isEmpty {
                emptyState
            } else {
                zoneList
            }
            Divider()
            footer
        }
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { PanelWindowSizer(contentHeight: $0.size.height) })
        .onReceive(ticker) { _ in model.tick() }
        .onAppear { model.tick() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Time Zones").font(.headline)
                HStack(spacing: 5) {
                    Circle()
                        .fill(model.isLive ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                    Text(model.offsetDescription ?? "Live")
                        .font(.caption.weight(model.isLive ? .regular : .semibold))
                        .foregroundStyle(model.isLive ? Color.secondary : Color.orange)
                        .accessibilityIdentifier("status")
                }
            }
            Spacer()
            Button("Now") { model.resetToNow() }
                .buttonStyle(.borderedProminent)
                .tint(model.isLive ? .gray : .accentColor)
                .controlSize(.small)
                .help("Return all zones to the current time")
                .accessibilityIdentifier("now")
            Picker("Clock", selection: $model.use24Hour) {
                Text("24h").tag(true)
                Text("12h").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 84)
            .accessibilityIdentifier("clockFormat")
            Button { isAdding.toggle() } label: {
                Image(systemName: isAdding ? "xmark" : "plus")
                    .frame(width: 14, height: 14)
            }
            .controlSize(.small)
            .help(isAdding ? "Close search" : "Add a time zone")
            .accessibilityLabel(isAdding ? "Close search" : "Add time zone")
            .accessibilityIdentifier("add")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var zoneList: some View {
        List {
            ForEach(model.zoneIDs, id: \.self) { id in
                if let info = ZoneCatalog.info(for: id) {
                    ZoneRowView(model: model, zone: info)
                        .contextMenu { rowMenu(id) }
                }
            }
            .onMove { model.move(fromOffsets: $0, toOffset: $1) }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .frame(height: min(CGFloat(model.zoneIDs.count) * ZoneRowView.height + 8, 520))
    }

    @ViewBuilder private func rowMenu(_ id: String) -> some View {
        let index = model.zoneIDs.firstIndex(of: id) ?? 0
        Button("Move Up") { model.move(fromOffsets: [index], toOffset: index - 1) }
            .disabled(index == 0)
        Button("Move Down") { model.move(fromOffsets: [index], toOffset: index + 2) }
            .disabled(index == model.zoneIDs.count - 1)
        Divider()
        Button("Remove") { model.remove(id) }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "globe").font(.largeTitle).foregroundStyle(.secondary)
            Text("No time zones yet").foregroundStyle(.secondary)
            Button("Add Time Zone") { isAdding = true }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 160)
    }

    private var footer: some View {
        HStack {
            Text("Drag a row to reorder · drag any slider to compare")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .controlSize(.small)
                .keyboardShortcut("q")
                .accessibilityIdentifier("quit")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
