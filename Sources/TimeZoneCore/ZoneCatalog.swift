import Foundation

/// A selectable time zone with the strings used for display and search.
public struct ZoneInfo: Identifiable, Hashable, Sendable {
    public let id: String          // IANA identifier, e.g. "America/New_York"
    public let city: String        // "New York"
    public let legacyCity: String? // pre-rename city still in the identifier ("Calcutta")
    public let region: String      // "America"
    public let genericName: String // "Eastern Time" (localized), may be empty
    public let abbreviations: [String] // tz database names, e.g. ["EST", "EDT"]

    public var timeZone: TimeZone { TimeZone(identifier: id)! }

    public init(id: String) {
        self.id = id
        let parts = id.split(separator: "/").map { $0.replacingOccurrences(of: "_", with: " ") }
        let rawCity = parts.last ?? id
        city = ZoneCatalog.renamedCities[id] ?? rawCity
        legacyCity = city == rawCity ? nil : rawCity
        region = parts.count > 1 ? parts.dropLast().joined(separator: " / ") : ""
        let zone = TimeZone(identifier: id)
        genericName = zone?.localizedName(for: .generic, locale: .current) ?? ""
        abbreviations = TZDatabase.abbreviations(for: id)
    }

    /// Display abbreviation in effect at `date`: the tz database name (JST, CEST, IST...),
    /// falling back to Foundation's localized short name. Nil when the only name is a bare
    /// offset like "GMT-3", which would just repeat the UTC offset label.
    public func abbreviation(at date: Date) -> String? {
        if let name = TZDatabase.abbreviation(for: timeZone, at: date) { return name }
        guard let name = timeZone.abbreviation(for: date), !name.hasPrefix("GMT") || name == "GMT" else { return nil }
        return name
    }

    /// "UTC+9 · JST", or just "UTC−3" when the zone has no real abbreviation.
    public func offsetAndAbbreviation(at date: Date) -> String {
        let offset = ZoneMath.utcOffsetLabel(timeZone, at: date)
        return abbreviation(at: date).map { "\(offset) · \($0)" } ?? offset
    }
}

public enum ZoneCatalog {
    public static let all: [ZoneInfo] = TimeZone.knownTimeZoneIdentifiers.map(ZoneInfo.init(id:))

    /// Zones Apple still lists only under a pre-rename identifier.
    static let renamedCities = ["Asia/Calcutta": "Kolkata"]
    private static let currentToListedID = ["Asia/Kolkata": "Asia/Calcutta"]

    private static let byID: [String: ZoneInfo] = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

    public static func info(for id: String) -> ZoneInfo? {
        byID[id] ?? (TimeZone(identifier: id) != nil ? ZoneInfo(id: id) : nil)
    }

    /// Ranked search over city, identifier, localized name and abbreviations.
    /// - An abbreviation with a canonical owner in `TimeZone.abbreviationDictionary`
    ///   ("PST" -> Los Angeles, "CET" -> Paris) ranks that zone first.
    /// - Zones whose tz database abbreviation equals the query follow (e.g. "CET" -> Berlin, ...).
    public static func search(_ rawQuery: String, in zones: [ZoneInfo] = all) -> [ZoneInfo] {
        let query = rawQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return zones.sorted { $0.city < $1.city } }
        let upper = query.uppercased()
        let canonical = TimeZone.abbreviationDictionary[upper].map { currentToListedID[$0] ?? $0 }

        func matches(_ s: String) -> Bool {
            s.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
        func prefix(_ s: String) -> Bool {
            s.range(of: query, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil
        }
        func rank(_ z: ZoneInfo) -> Int? {
            if z.id == canonical { return 0 }
            if prefix(z.city) { return 1 }
            if z.abbreviations.contains(upper) { return 2 }
            if matches(z.city) || z.legacyCity.map(matches) == true { return 3 }
            if matches(z.id.replacingOccurrences(of: "_", with: " ")) || matches(z.genericName) { return 4 }
            return nil
        }
        return zones.compactMap { z in rank(z).map { (z, $0) } }
            .sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.city < $1.0.city }
            .map(\.0)
    }
}

/// Reads zone abbreviations from the POSIX TZ footer of the system tz database
/// (`/usr/share/zoneinfo/<id>`, e.g. "CET-1CEST,M3.5.0,M10.5.0/3"). Foundation only exposes
/// abbreviations like "JST" for some locales, so the tz database is the reliable source.
/// Only names are taken from the file; all time math stays in Foundation.
enum TZDatabase {
    struct Rule { let stdName: String; let stdOffset: Int; let dstName: String?; let dstOffset: Int? }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: Rule?] = [:]

    static func rule(for id: String) -> Rule? {
        lock.lock(); defer { lock.unlock() }
        if let cached = cache[id] { return cached }
        let parsed = loadFooter(id).flatMap(parse)
        cache[id] = parsed
        return parsed
    }

    static func abbreviations(for id: String) -> [String] {
        guard let r = rule(for: id) else { return [] }
        return [r.stdName, r.dstName].compactMap { $0 }.filter { $0.first?.isLetter == true }
    }

    /// Picks the std or dst name whose offset matches the offset Foundation reports at `date`.
    static func abbreviation(for zone: TimeZone, at date: Date) -> String? {
        guard let r = rule(for: zone.identifier) else { return nil }
        let seconds = zone.secondsFromGMT(for: date)
        let name: String?
        if seconds == r.stdOffset { name = r.stdName }
        else if let dst = r.dstOffset, seconds == dst { name = r.dstName }
        else { name = nil } // historical offset the current rule does not describe
        // Numeric names like "-03" add nothing over the UTC offset label.
        guard let n = name, n.first?.isLetter == true else { return nil }
        return n
    }

    private static func loadFooter(_ id: String) -> String? {
        guard !id.contains(".."),
              let data = FileManager.default.contents(atPath: "/usr/share/zoneinfo/" + id),
              data.last == UInt8(ascii: "\n") else { return nil }
        let body = data.dropLast()
        guard let start = body.lastIndex(of: UInt8(ascii: "\n")) else { return nil }
        return String(data: body[(start + 1)...], encoding: .ascii)
    }

    /// Parses "STD offset [DST [offset]] [,rule]". Offsets in POSIX are west-positive.
    static func parse(_ tz: String) -> Rule? {
        var s = Substring(tz.split(separator: ",", maxSplits: 1).first ?? "")
        guard let std = name(&s), let stdPosix = offset(&s) else { return nil }
        let stdOffset = -stdPosix
        guard let dst = name(&s) else { return Rule(stdName: std, stdOffset: stdOffset, dstName: nil, dstOffset: nil) }
        let dstOffset = offset(&s).map { -$0 } ?? stdOffset + 3600
        return Rule(stdName: std, stdOffset: stdOffset, dstName: dst, dstOffset: dstOffset)
    }

    private static func name(_ s: inout Substring) -> String? {
        if s.first == "<" {
            guard let end = s.firstIndex(of: ">") else { return nil }
            let n = String(s[s.index(after: s.startIndex)..<end])
            s = s[s.index(after: end)...]
            return n
        }
        let n = s.prefix { $0.isLetter }
        guard n.count >= 3 else { return nil }
        s = s.dropFirst(n.count)
        return String(n)
    }

    private static func offset(_ s: inout Substring) -> Int? {
        let text = s.prefix { $0.isNumber || $0 == ":" || $0 == "+" || $0 == "-" }
        guard !text.isEmpty else { return nil }
        s = s.dropFirst(text.count)
        var sign = 1, body = Substring(text)
        if body.first == "-" { sign = -1; body = body.dropFirst() } else if body.first == "+" { body = body.dropFirst() }
        let f = body.split(separator: ":").map { Int($0) ?? 0 }
        guard let h = f.first else { return nil }
        return sign * (h * 3600 + (f.count > 1 ? f[1] * 60 : 0) + (f.count > 2 ? f[2] : 0))
    }
}
