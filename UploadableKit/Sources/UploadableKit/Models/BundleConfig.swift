import Foundation

/// The one place the bundle prefix lives. `Tools/generate-project.sh` reads it
/// from here and feeds it to XcodeGen and the entitlements, so changing it here
/// changes it everywhere.
public enum BundleConfig {
    public static let prefix = "com.leejiles"

    public static var appBundleID: String { "\(prefix).uploadable" }
    public static var shareBundleID: String { "\(prefix).uploadable.share" }
    public static var appGroupID: String { "group.\(prefix).uploadable" }
    public static var proProductID: String { "\(prefix).uploadable.pro" }
}

/// Tunable numbers with exactly one home each.
public enum Config {
    /// TUNING DIAL: exports that are free, for ever. Fitting a photo is
    /// unlimited — the result screen is the sales pitch, so it is never hidden.
    /// Two rather than one covers "I picked the wrong spec the first time",
    /// which would otherwise arrive as a refund request.
    public static let freeExports = 2

    /// Hard cap on encodes for a single fit. Expect 5–8; this only exists so a
    /// pathological image cannot spin.
    public static let maxEncodes = 32

    /// How low the quality bisection may probe.
    ///
    /// Separate from `shipQualityFloor` on purpose. One number meaning both
    /// "how far the search may look" and "what we are willing to ship" cannot
    /// be reasoned about: raising one to protect the user silently narrows the
    /// search, and widening the search silently lowers what ships. They are
    /// equal today and that is a coincidence, not a definition.
    public static let searchQualityFloor = 0.5

    /// The lowest quality that may ever leave the app.
    ///
    /// Reached only when the smallest legal dimensions still cannot meet the
    /// byte limit at anything better. A result down here keeps the softness
    /// warning, because "blurry" and "pixelated" are named rejection reasons on
    /// the State Department's own page.
    public static let shipQualityFloor = 0.5

    public static let qualityCeiling = 1.0

    /// What we will not go below while there is still a smaller size to try.
    ///
    /// Against a fixed byte ceiling, resolution is bought with compression —
    /// they are not independent. A face at q0.50 with visible blocking is a
    /// worse submission than a smaller one at q0.70, so dimensions give way
    /// first and quality only falls when nothing else can.
    public static let acceptableQuality = 0.7

    /// Aim this far into the byte band, as a fraction of its width, and keep
    /// this much clearance from either edge.
    public static let bandTargetFraction = 0.6
    public static let bandEdgeClearance = 0.05

    /// How many dimension candidates the initial ladder suggests. The search
    /// brackets and predicts from there, so this is a starting spread rather
    /// than the set of sizes actually tried.
    public static let ladderSize = 5

    /// Quality bisection steps per size.
    public static let qualitySteps = 4

    /// Where the quality search begins. A photograph destined for a government
    /// portal wants to look like a photograph, so it starts high and comes down
    /// only as far as the byte band forces it.
    public static let startingQuality = 0.8

    /// How much to shrink the image when a size lands in band but only at a
    /// quality we would rather not ship. Fewer pixels carry the same byte
    /// budget at higher quality; this is how that trade is made.
    public static let qualityRecoveryStep = 0.8

    /// How many distinct sizes one fit may try. Each costs a handful of
    /// encodes, so this is what actually keeps a fit inside `maxEncodes`
    /// rather than the encode count noticing too late.
    public static let maxSizes = 6

    /// What a photograph should weigh when the spec leaves room to choose.
    ///
    /// Byte bands vary enormously — DS-160 allows 240 KB, UK Passport allows
    /// 10 MB — and aiming at a fraction of the ceiling produces a six-megabyte
    /// passport photo, which is in range and plainly wrong. This caps the
    /// proportional target: generous for a photograph, absurd for anything
    /// that is merely "under the limit".
    public static let preferredBytes = 1_500_000

    /// Re-verify presets older than this before submitting a release.
    public static let specStaleAfterDays = 90
}
