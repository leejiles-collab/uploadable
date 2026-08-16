import Foundation

/// How a verification date is written for the user.
///
/// One formatter, in the kit, because there was briefly one per screen and both
/// were wrong in the same way: `SpecCatalog` builds these dates at midnight UTC,
/// and a formatter left on the device's own time zone renders midnight UTC on
/// 15 August as *14 August* anywhere west of Greenwich. A provenance date that
/// reads a day early is worse than no date at all — the whole point of showing
/// it is that it can be trusted.
public enum ProvenanceFormat {

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    /// "15 Aug 2026"
    public static func date(_ date: Date) -> String {
        formatter.string(from: date)
    }

    /// "Requirements verified 15 Aug 2026", or nil when nobody has checked.
    public static func label(for source: SpecSource) -> String? {
        guard let verified = source.verifiedOn else { return nil }
        return "Requirements verified \(date(verified))"
    }
}
