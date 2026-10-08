import SwiftUI
import TimeZoneCore

struct AddZoneView: View {
    @ObservedObject var model: ComparisonModel
    let onDone: () -> Void

    @State private var query = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        let results = ZoneCatalog.search(query)
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("City, region or abbreviation (e.g. Tokyo, PST)", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onSubmit { if let first = results.first { add(first) } }
                    .accessibilityIdentifier("search")
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
            .padding(10)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(results) { zone in
                        resultRow(zone)
                    }
                }
            }
            .id(query) // new results start scrolled to the top
            .frame(height: 300)
        }
        .onAppear { searchFocused = true }
        .onExitCommand(perform: onDone)
    }

    private func resultRow(_ zone: ZoneInfo) -> some View {
        let added = model.zoneIDs.contains(zone.id)
        return Button { add(zone) } label: {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(zone.city).fontWeight(.medium)
                    Text(zone.region.isEmpty ? zone.id : zone.region)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(zone.offsetAndAbbreviation(at: model.now))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Image(systemName: added ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(added ? Color.green : Color.accentColor)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(added)
        .accessibilityIdentifier("result-\(zone.id)")
    }

    private func add(_ zone: ZoneInfo) {
        model.add(zone.id)
        onDone()
    }
}
