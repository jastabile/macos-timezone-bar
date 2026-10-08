import SwiftUI
import TimeZoneCore

struct ZoneRowView: View {
    static let height: CGFloat = 96

    @ObservedObject var model: ComparisonModel
    let zone: ZoneInfo

    /// The shared instant captured when a drag in this row began. The slider is positioned
    /// relative to that day so dragging to the end (24:00) does not wrap the thumb mid-drag.
    @State private var dragAnchor: Date?

    private var tz: TimeZone { zone.timeZone }

    var body: some View {
        let instant = model.instant
        let dayDiff = model.dayDifference(for: tz)
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(zone.city)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                        if model.isLocal(zone.id) {
                            Text("Local")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                                .foregroundStyle(Color.accentColor)
                                .accessibilityIdentifier("local-\(zone.id)")
                        }
                        Button { model.remove(zone.id) } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("Remove \(zone.city)")
                        .accessibilityLabel("Remove \(zone.city)")
                        .accessibilityIdentifier("remove-\(zone.id)")
                    }
                    Text(zone.offsetAndAbbreviation(at: instant))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("offset-\(zone.id)")
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(timeString(instant))
                        .font(.system(size: 26, weight: .medium, design: .rounded).monospacedDigit())
                        .lineLimit(1)
                        .accessibilityIdentifier("time-\(zone.id)")
                    HStack(spacing: 4) {
                        Text(dateString(instant))
                        if let label = ZoneMath.dayDifferenceLabel(dayDiff) {
                            Text(label)
                                .fontWeight(.semibold)
                                .foregroundStyle(dayDiff > 0 ? Color.blue : Color.purple)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("date-\(zone.id)")
                }
            }
            DaySlider(
                minutes: model.sliderMinutes(in: tz, anchor: dragAnchor),
                accessibilityLabel: "\(zone.city) time",
                accessibilityValue: timeString(instant),
                accessibilityIdentifier: "slider-\(zone.id)",
                onEditingChanged: { editing in dragAnchor = editing ? model.instant : nil },
                onChange: { model.setSlider(minutes: $0, in: tz, anchor: dragAnchor ?? model.instant) }
            )
        }
        .padding(.vertical, 6)
        .frame(height: Self.height - 8)
    }

    private func formatter(_ format: String, template: Bool) -> DateFormatter {
        let f = DateFormatter()
        f.timeZone = tz
        if template {
            f.setLocalizedDateFormatFromTemplate(format)
        } else {
            // POSIX locale so the 12h/24h toggle wins over the system "24-hour time" setting,
            // which otherwise rewrites fixed "h:mm a" patterns.
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = format
        }
        return f
    }

    private func timeString(_ date: Date) -> String {
        formatter(model.use24Hour ? "HH:mm" : "h:mm a", template: false).string(from: date)
    }

    private func dateString(_ date: Date) -> String {
        formatter("EEEMMMd", template: true).string(from: date)
    }
}

/// A 24-hour slider for one zone's wall clock, shaded by time of day:
/// night (22:00–07:00), shoulder hours, and working hours (09:00–18:00).
struct DaySlider: View {
    let minutes: Int
    let accessibilityLabel: String
    let accessibilityValue: String
    let accessibilityIdentifier: String
    let onEditingChanged: (Bool) -> Void
    let onChange: (Double) -> Void

    @State private var isDragging = false
    private let day = Double(ZoneMath.minutesPerDay)
    private let thumb: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let usable = geo.size.width - thumb
            let fraction = min(max(Double(minutes) / day, 0), 1)
            ZStack(alignment: .topLeading) {
                track
                    .frame(width: usable, height: 8)
                    .offset(x: thumb / 2, y: (thumb - 8) / 2)
                ForEach([0, 6, 12, 18, 24], id: \.self) { hour in
                    Text("\(hour)")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                        .fixedSize()
                        .frame(width: 20)
                        .offset(x: thumb / 2 + usable * CGFloat(hour) / 24 - 10, y: thumb + 1)
                }
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2.5))
                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
                    .frame(width: thumb, height: thumb)
                    .offset(x: usable * fraction)
            }
            // Fill the whole slider so the hit area (and accessibility frame) covers the thumb at both ends.
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            onEditingChanged(true)
                        }
                        let x = min(max(value.location.x - thumb / 2, 0), usable)
                        onChange(Double(x / max(usable, 1)) * day)
                    }
                    .onEnded { _ in
                        isDragging = false
                        onEditingChanged(false)
                    }
            )
        }
        .frame(height: thumb + 12)
        // Expose a standard, settable slider to Accessibility (VoiceOver and UI automation).
        .accessibilityRepresentation {
            Slider(value: Binding(get: { Double(minutes) }, set: { onChange($0) }), in: 0...day, step: 15) {
                Text(accessibilityLabel)
            }
            .accessibilityValue(accessibilityValue)
        }
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var track: some View {
        // Segments in wall-clock hours: [start, end, color].
        let segments: [(Double, Double, Color)] = [
            (0, 7, Color.indigo.opacity(0.45)),
            (7, 9, Color.gray.opacity(0.3)),
            (9, 18, Color.green.opacity(0.65)),
            (18, 22, Color.gray.opacity(0.3)),
            (22, 24, Color.indigo.opacity(0.45)),
        ]
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                ForEach(segments.indices, id: \.self) { i in
                    let s = segments[i]
                    Rectangle()
                        .fill(s.2)
                        .frame(width: geo.size.width * (s.1 - s.0) / 24)
                        .offset(x: geo.size.width * s.0 / 24)
                }
            }
        }
        .clipShape(Capsule())
    }
}
