import Foundation

/// The one place the bundle prefix lives. `Tools/generate-project.sh` reads it
/// from here and feeds it to XcodeGen and the entitlements, so changing it here
/// changes it everywhere.
public enum BundleConfig {
    public static let prefix = "com.leejiles"

    public static var appBundleID: String { "\(prefix).fits" }
    public static var shareBundleID: String { "\(prefix).fits.share" }
    public static var appGroupID: String { "group.\(prefix).fits" }
    public static var proProductID: String { "\(prefix).fits.pro" }
}

/// Tunable numbers with exactly one home each.
public enum Config {
    /// TUNING DIAL: exports that are free, for ever. Fits themselves are
    /// unlimited — the result screen is the sales pitch, so it is never hidden.
    /// Two rather than one covers "I picked the wrong spec the first time",
    /// which would otherwise arrive as a refund request.
    public static let freeExports = 2

    /// Hard cap on encodes for a single fit. Expect 5–8; this only exists so a
    /// pathological image cannot spin.
    public static let maxEncodes = 24

    /// Quality range the solver will search. Below the floor a photo of a face
    /// starts showing blocking, and shipping that to a government portal is how
    /// people get rejected for "poor quality".
    public static let qualityFloor = 0.5
    public static let qualityCeiling = 1.0

    /// A landing at or above this quality is good enough to stop looking.
    public static let acceptableQuality = 0.7

    /// Aim this far into the byte band, as a fraction of its width, and keep
    /// this much clearance from either edge.
    public static let bandTargetFraction = 0.6
    public static let bandEdgeClearance = 0.05

    /// How many dimension candidates to build per fit.
    public static let ladderSize = 5

    /// Re-verify presets older than this before submitting a release.
    public static let specStaleAfterDays = 90
}
