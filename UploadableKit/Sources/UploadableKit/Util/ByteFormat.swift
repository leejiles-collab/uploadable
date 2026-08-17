import Foundation

/// Byte counts the way an upload form writes them.
///
/// Decimal, not binary: every spec we have read says "240 kB" meaning 240,000,
/// and showing 234 KiB next to a form that says 240 kB would read as a failure.
public enum ByteFormat {
    public static func string(_ bytes: Int) -> String {
        let mb = Double(bytes) / 1_000_000
        if mb >= 1 {
            return String(format: mb >= 10 ? "%.0f MB" : "%.1f MB", mb)
        }
        let kb = Double(bytes) / 1_000
        return String(format: kb >= 100 ? "%.0f KB" : "%.1f KB", kb)
    }

    /// "600 × 600"
    public static func size(_ width: Int, _ height: Int) -> String {
        "\(width) × \(height)"
    }

    /// "240 KB" or "50 KB – 10 MB", whichever the band actually is.
    public static func band(_ range: ClosedRange<Int>) -> String {
        range.lowerBound == 0
            ? "up to \(string(range.upperBound))"
            : "\(string(range.lowerBound)) – \(string(range.upperBound))"
    }
}
