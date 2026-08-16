import Foundation
import UniformTypeIdentifiers

/// What the source file actually is, as opposed to what its extension claims.
///
/// A HEIC renamed to `.jpg` is the single most common cause of "File Must Be
/// JPEG", so the type here is read from the bytes, never from the name.
public struct SourceFacts: Sendable, Hashable {
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let byteCount: Int
    /// Read from the file's content, not its path extension.
    public let type: UTType?
    /// The ICC profile description the file carries, if any.
    public let profileName: String?
    public let hasEXIF: Bool
    public let hasGPS: Bool
    /// Orientation as recorded in EXIF (1 when absent or upright).
    public let orientation: Int

    public init(
        pixelWidth: Int, pixelHeight: Int, byteCount: Int, type: UTType?,
        profileName: String?, hasEXIF: Bool, hasGPS: Bool, orientation: Int
    ) {
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.byteCount = byteCount
        self.type = type
        self.profileName = profileName
        self.hasEXIF = hasEXIF
        self.hasGPS = hasGPS
        self.orientation = orientation
    }
}

/// One thing the engine did, in the order it did it. Shown on the working
/// screen, because these steps *are* the product.
public enum Transformation: Sendable, Hashable {
    case decoded(from: String)
    case convertedColor(from: String, to: String)
    case strippedMetadata(kinds: [String])
    case cropped(to: String, from: String)
    case resized(to: String)
    case encoded(quality: Double)

    public var label: String {
        switch self {
        case .decoded(let from): "Decoded \(from)"
        case .convertedColor(let from, let to): "Converted \(from) to \(to)"
        case .strippedMetadata(let kinds):
            kinds.isEmpty ? "No metadata to remove" : "Removed \(kinds.joined(separator: ", "))"
        case .cropped(let to, let from): "Cropped \(from) to \(to)"
        case .resized(let to): "Resized to \(to)"
        case .encoded(let q): "Encoded at quality \(String(format: "%.2f", q))"
        }
    }
}

/// One independently-measured check on the file that was written.
///
/// Each is re-read from disk. On Smaller this step caught two real bugs that
/// nothing upstream noticed, which is why it is not optional here.
public struct Check: Sendable, Hashable {
    public let name: String
    public let passed: Bool
    public let detail: String

    public init(name: String, passed: Bool, detail: String) {
        self.name = name
        self.passed = passed
        self.detail = detail
    }
}

public struct Verification: Sendable, Hashable {
    public let checks: [Check]
    public var passed: Bool { checks.allSatisfy(\.passed) }
    public var failures: [Check] { checks.filter { !$0.passed } }

    public init(checks: [Check]) { self.checks = checks }
}

/// Something true about a result that the green ticks do not cover.
///
/// A warning never turns a pass into a failure. The file does meet the stated
/// requirements — that is measured — and Fits does not get to overrule a
/// government about its own form. It sits alongside the ticks, not instead of
/// them.
///
/// Both cases are deliberately about the *file*. Fits changes files, not
/// photographs, and a warning that strayed into commenting on the picture would
/// be the app doing exactly the thing it promises not to.
public enum FitWarning: Sendable, Hashable {
    /// The form states no minimum size, and the result is smaller than every
    /// form that does state one.
    case belowCommonMinimum(short: Int, floor: Int, size: String, cropsAfterUpload: Bool)
    /// In band, but compressed harder than we would choose. "Blurry" and
    /// "pixelated" are named rejection reasons on State's own page.
    case softerThanPreferred(quality: Double)

    public var message: String {
        switch self {
        case .belowCommonMinimum(_, _, let size, let crops):
            "This is \(size). The form doesn't state a minimum, but it's smaller "
            + "than every other form we know of requires"
            + (crops ? ", and you'll be cropping it further during upload." : ".")
        case .softerThanPreferred:
            "This had to be compressed harder than we'd like to fit the size limit."
        }
    }

    /// What it means for the person, without straying into their photograph.
    public var detail: String? {
        switch self {
        case .belowCommonMinimum:
            "The file is within the stated requirements, so it will upload. "
            + "A larger original would leave more detail in the finished photo."
        case .softerThanPreferred:
            "It meets the size requirement. A higher-resolution original would "
            + "let it meet the same limit with less compression."
        }
    }
}

/// A file that meets the spec.
public struct Fit: Sendable, Hashable {
    public let url: URL
    public let spec: UploadSpec
    public let source: SourceFacts
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let byteCount: Int
    public let quality: Double
    /// Every dimension candidate tried, largest first.
    public let candidatesTried: [String]
    public let encodeCount: Int
    /// True when the search stopped because it ran out of encode budget rather
    /// than because it was finished. The result is still verified and still
    /// meets the spec — but a better one may have existed, so it is worth
    /// knowing rather than silently accepting.
    public let hitEncodeCap: Bool
    public let elapsed: TimeInterval
    public let transformations: [Transformation]
    public let verification: Verification
    /// True things the ticks do not cover. Never a failure.
    public let warnings: [FitWarning]

    public init(
        url: URL, spec: UploadSpec, source: SourceFacts,
        pixelWidth: Int, pixelHeight: Int, byteCount: Int, quality: Double,
        candidatesTried: [String], encodeCount: Int, hitEncodeCap: Bool,
        elapsed: TimeInterval,
        transformations: [Transformation], verification: Verification,
        warnings: [FitWarning] = []
    ) {
        self.url = url
        self.spec = spec
        self.source = source
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.byteCount = byteCount
        self.quality = quality
        self.candidatesTried = candidatesTried
        self.encodeCount = encodeCount
        self.hitEncodeCap = hitEncodeCap
        self.elapsed = elapsed
        self.transformations = transformations
        self.verification = verification
        self.warnings = warnings
    }
}

/// Why no file was produced.
///
/// Every case carries the numbers needed to tell the user what would fix it. A
/// failure that only says "couldn't do it" is barely better than a file that
/// gets rejected.
public enum FitFailure: Error, Sendable, Hashable {
    /// The source has fewer pixels than the spec's minimum, after the
    /// aspect-correct crop. Upscaling would invent detail, so we stop.
    case upscaleRequired(have: String, need: String)
    /// At the largest non-upscaling size and maximum quality, still under the
    /// spec's byte floor.
    case belowMinimumBytes(got: Int, need: Int, atSize: String)
    /// At the spec's minimum legal size and lowest acceptable quality, still
    /// over the byte ceiling.
    case aboveMaximumBytes(got: Int, limit: Int, atSize: String)
    /// The source could not be read as an image at all.
    case unreadableSource(String)
    /// A file was produced but failed its own verification, so it was discarded.
    case verificationFailed([Check])

    public var message: String {
        switch self {
        case .upscaleRequired(let have, let need):
            "This photo is \(have). The form needs at least \(need)."
        case .belowMinimumBytes(let got, let need, let atSize):
            "At \(atSize) and full quality this photo is \(ByteFormat.string(got)), "
            + "under the \(ByteFormat.string(need)) minimum."
        case .aboveMaximumBytes(let got, let limit, let atSize):
            "Even at \(atSize) this photo is \(ByteFormat.string(got)), "
            + "over the \(ByteFormat.string(limit)) limit."
        case .unreadableSource(let why):
            "We couldn't read that image. \(why)"
        case .verificationFailed(let checks):
            "The file we made didn't pass its own checks: "
            + checks.map(\.name).joined(separator: ", ") + "."
        }
    }

    /// What the user could actually do about it.
    public var remedy: String? {
        switch self {
        case .upscaleRequired:
            "You'll need a higher-resolution original. Enlarging this one would "
            + "invent detail that isn't there, and the form would likely reject it."
        case .belowMinimumBytes:
            "A photo with more detail — taken at higher resolution, or less "
            + "heavily compressed already — would clear the minimum."
        case .aboveMaximumBytes:
            "This is unusual. Send it to us if you see it."
        case .unreadableSource:
            "Try exporting it from Photos first."
        case .verificationFailed:
            "Nothing was saved. Send us the photo if this keeps happening."
        }
    }
}
