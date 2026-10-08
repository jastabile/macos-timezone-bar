import Combine
import Foundation

/// Persists the user's zone list and preferences.
public struct ZoneStore {
    public static let zonesKey = "selectedZoneIdentifiers"
    public static let use24HourKey = "use24Hour"

    private let defaults: UserDefaults
    private let localZone: () -> TimeZone

    public init(defaults: UserDefaults = .standard, localZone: @escaping () -> TimeZone = { .current }) {
        self.defaults = defaults
        self.localZone = localZone
    }

    /// Saved identifiers; on first launch just the local zone. Unknown identifiers are dropped.
    public func loadZones() -> [String] {
        guard let saved = defaults.stringArray(forKey: Self.zonesKey) else { return [localZone().identifier] }
        return saved.filter { TimeZone(identifier: $0) != nil }
    }

    public func saveZones(_ ids: [String]) { defaults.set(ids, forKey: Self.zonesKey) }

    public var use24Hour: Bool {
        get { defaults.object(forKey: Self.use24HourKey) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Self.use24HourKey) }
    }
}

/// The app state: a list of zones that all display one shared reference instant.
/// `referenceDate == nil` means "live": the instant follows the clock.
public final class ComparisonModel: ObservableObject {
    @Published public private(set) var zoneIDs: [String]
    @Published public private(set) var referenceDate: Date?
    @Published public private(set) var now: Date
    @Published public var use24Hour: Bool { didSet { store.use24Hour = use24Hour } }

    public let snapMinutes = 15
    private let store: ZoneStore
    private let clock: () -> Date
    private let localZone: () -> TimeZone

    public init(store: ZoneStore = ZoneStore(), clock: @escaping () -> Date = Date.init,
                localZone: @escaping () -> TimeZone = { .current }) {
        self.store = store
        self.clock = clock
        self.localZone = localZone
        zoneIDs = store.loadZones()
        use24Hour = store.use24Hour
        now = clock()
    }

    public var instant: Date { referenceDate ?? now }
    public var isLive: Bool { referenceDate == nil }
    public var localTimeZone: TimeZone { localZone() }
    public var zones: [ZoneInfo] { zoneIDs.compactMap(ZoneCatalog.info(for:)) }

    public func isLocal(_ id: String) -> Bool { TimeZone(identifier: id) == localZone() }

    /// "+3h 15m from now", or nil while live.
    public var offsetDescription: String? {
        referenceDate.map { "\(ZoneMath.offsetLabel(from: now, to: $0)) from now" }
    }

    /// Advances the live clock; call periodically (e.g. every second). Only publishes when the
    /// minute changes: everything shown is minute-granular, and re-rendering every row each
    /// second would interrupt in-progress interactions such as dragging a row to reorder it.
    public func tick() {
        let t = clock()
        if Int(t.timeIntervalSince1970 / 60) != Int(now.timeIntervalSince1970 / 60) { now = t }
    }

    // MARK: Slider

    /// Slider position for `zone` (wall-clock minutes from midnight of the day containing `anchor`).
    public func sliderMinutes(in zone: TimeZone, anchor: Date? = nil) -> Int {
        ZoneMath.minuteOfDay(instant, relativeToDayOf: anchor ?? instant, in: zone)
    }

    /// Sets the shared instant so that `zone`'s wall clock reads `minutes` (snapped to 15 min)
    /// on the day containing `anchor` (the instant captured when the drag began).
    public func setSlider(minutes: Double, in zone: TimeZone, anchor: Date) {
        let snapped = min(max(ZoneMath.snap(minutes, step: snapMinutes), 0), ZoneMath.minutesPerDay)
        referenceDate = ZoneMath.instant(minuteOfDay: snapped, onDayOf: anchor, in: zone)
    }

    public func resetToNow() {
        referenceDate = nil
        now = clock()
    }

    /// Day offset of `zone` relative to the local zone at the shared instant.
    public func dayDifference(for zone: TimeZone) -> Int {
        ZoneMath.dayDifference(at: instant, in: zone, relativeTo: localZone())
    }

    // MARK: List editing (persisted immediately)

    public func add(_ id: String) {
        guard TimeZone(identifier: id) != nil, !zoneIDs.contains(id) else { return }
        zoneIDs.append(id)
        store.saveZones(zoneIDs)
    }

    public func remove(_ id: String) {
        zoneIDs.removeAll { $0 == id }
        store.saveZones(zoneIDs)
    }

    public func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        // Same semantics as SwiftUI's Array.move(fromOffsets:toOffset:), without importing SwiftUI.
        let moving = source.map { zoneIDs[$0] }
        var rest = zoneIDs.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertAt = destination - source.filter { $0 < destination }.count
        rest.insert(contentsOf: moving, at: insertAt)
        zoneIDs = rest
        store.saveZones(zoneIDs)
    }
}
