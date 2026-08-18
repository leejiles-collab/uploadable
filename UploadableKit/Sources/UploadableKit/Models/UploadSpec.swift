import Foundation
import UniformTypeIdentifiers

/// What one upload form demands of a photo file.
///
/// Deliberately a description of *requirements*, not of a transformation. The
/// engine reads this and works out what to do; nothing here says how.
public struct UploadSpec: Sendable, Identifiable, Hashable {
    public let id: String
    /// Shown to the user. "US Visa (DS-160)".
    public let name: String
    /// Which government or body, for grouping and search.
    public let issuer: String
    public let aspect: AspectRule

    /// Pixel bounds, when the official page states them.
    ///
    /// Optional, and that is not fussiness. Several real specs — India's eVisa,
    /// New Zealand's visa photo page — state a shape and a byte band and say
    /// nothing at all about pixels. Modelling those as a required range would
    /// mean inventing numbers, and an invented minimum could reject a photo the
    /// portal would have accepted.
    public let width: ClosedRange<Int>?
    public let height: ClosedRange<Int>?

    /// A band, not a ceiling. Half of these specs have a floor as well, and a
    /// file under it is rejected exactly as firmly as one over the top.
    public let bytes: ClosedRange<Int>

    /// The formats the portal says it accepts.
    ///
    /// A set, not a single value, because it is not always one. The US
    /// Passport upload page accepts JPG, JPEG, PNG, HEIC and HEIF; saying
    /// "JPEG required" there would be putting words in the State Department's
    /// mouth. What Uploadable *writes* is `output`, and the two are different
    /// questions.
    public let accepted: Set<UTType>

    /// What Uploadable emits. JPEG everywhere, for now.
    ///
    /// It is accepted by every spec verified so far, and it is the only path
    /// whose output is verified end to end — the profile, the metadata and the
    /// byte count are all checked on a JPEG. Emitting a format we do not verify
    /// would be worse than emitting one that is merely allowed rather than
    /// demanded.
    public let output: UTType
    public let color: ColorPolicy
    public let exif: EXIFPolicy
    public let icc: ICCPolicy
    public let source: SpecSource

    /// Anything the official page says that we cannot express as a rule, and
    /// that the user should still read. Kept short.
    public let caveats: [String]

    /// Whether this spec actually rules anything out.
    ///
    /// A preset with no shape rule, no pixel bounds and a byte band wide enough
    /// to admit any photograph is not a specification — it is a rubber stamp,
    /// and one that will happily approve a screenshot. Nothing that fails this
    /// belongs in front of a user.
    public var constrainsSomething: Bool {
        if aspect.value != nil { return true }
        if width != nil || height != nil { return true }
        return bytes.lowerBound > 0
    }

    /// Whether the official page states any pixel floor at all.
    ///
    /// The sanity floor applies only where this is false, so a derived
    /// heuristic can never overrule a government that has actually published a
    /// number.
    public var statesPixelFloor: Bool { width != nil || height != nil }

    /// The shortest edge this spec demands, when it demands one.
    public var shortEdgeMinimum: Int? {
        guard let width, let height else { return nil }
        return min(width.lowerBound, height.lowerBound)
    }

    /// Whether the portal crops the photo again after upload.
    ///
    /// Stated on the US Passport upload page: the applicant crops inside the
    /// State Department's own tool. It matters because it means the pixels that
    /// survive to the final photo are fewer than the ones in the file, which is
    /// the honest reason a technically-acceptable small file is still a bad
    /// idea there.
    public let cropsAfterUpload: Bool

    /// The pixel requirement in words, or nil when the spec states none.
    ///
    /// "and up" is only honest where a spec genuinely publishes no maximum —
    /// UK Passport says at least 600 × 750 and stops there. DS-160 publishes
    /// 600 × 600 *to 1200 × 1200*, and showing that as "600 × 600 and up" hides
    /// half the requirement from the person deciding whether their photo fits.
    public var pixelSummary: String? {
        guard let width, let height else { return nil }
        let low = ByteFormat.size(width.lowerBound, height.lowerBound)
        guard width.upperBound < SpecCatalog.noStatedMaximum else { return "\(low) and up" }
        return "\(low) to \(ByteFormat.size(width.upperBound, height.upperBound))"
    }

    /// The whole requirement on one line, for a list row or a report table.
    public var requirementSummary: String {
        var parts: [String] = []
        if aspect.value != nil { parts.append(aspect.label) }
        parts.append(pixelSummary ?? "any size")
        parts.append(ByteFormat.band(bytes))
        return parts.joined(separator: " · ")
    }

    /// Whether the portal insists on the format we emit, or merely allows it.
    /// Worth saying out loud in the UI: "JPEG" reads as a requirement, and for
    /// several specs it is only a choice.
    public var mandatesOutputFormat: Bool { accepted == [output] }

    /// Safe to offer as a choice: it constrains something, and if nobody has
    /// confirmed its numbers it at least says why.
    public var isOfferable: Bool {
        constrainsSomething && (source.isVerified || source.note != nil)
    }

    public init(
        id: String,
        name: String,
        issuer: String,
        aspect: AspectRule,
        width: ClosedRange<Int>?,
        height: ClosedRange<Int>?,
        bytes: ClosedRange<Int>,
        accepted: Set<UTType> = [.jpeg],
        output: UTType = .jpeg,
        color: ColorPolicy = .sRGB,
        exif: EXIFPolicy = .stripAll,
        icc: ICCPolicy = .embedSRGB,
        source: SpecSource,
        caveats: [String] = [],
        cropsAfterUpload: Bool = false
    ) {
        self.id = id
        self.name = name
        self.issuer = issuer
        self.aspect = aspect
        self.width = width
        self.height = height
        self.bytes = bytes
        self.accepted = accepted
        self.output = output
        self.color = color
        self.exif = exif
        self.icc = icc
        self.source = source
        self.caveats = caveats
        self.cropsAfterUpload = cropsAfterUpload
    }
}

/// The shape requirement.
public enum AspectRule: Sendable, Hashable {
    case square
    /// `tolerance` is a fraction of the ratio, so 0.005 is ±0.5%.
    case ratio(w: Int, h: Int, tolerance: Double)
    case free

    /// Width divided by height. Nil when the spec does not constrain shape.
    public var value: Double? {
        switch self {
        case .square: 1.0
        case .ratio(let w, let h, _): Double(w) / Double(h)
        case .free: nil
        }
    }

    public var tolerance: Double {
        switch self {
        case .square: 0
        case .ratio(_, _, let t): t
        case .free: .infinity
        }
    }

    /// Whether a concrete pixel size satisfies the rule.
    public func admits(width: Int, height: Int) -> Bool {
        guard let wanted = value else { return true }
        guard height > 0 else { return false }
        if case .square = self { return width == height }
        let actual = Double(width) / Double(height)
        return abs(actual - wanted) <= wanted * tolerance
    }

    public var label: String {
        switch self {
        case .square: "Square"
        case .ratio(let w, let h, _): "\(w):\(h)"
        case .free: "Any shape"
        }
    }
}

/// Colour handling. One case today; the type exists because a spec demanding
/// something else would otherwise be unrepresentable.
public enum ColorPolicy: Sendable, Hashable {
    case sRGB
}

/// What to do with EXIF, GPS, TIFF and maker notes.
public enum EXIFPolicy: Sendable, Hashable {
    case stripAll
    case keepOrientationOnly
}

/// What to do with the colour profile.
///
/// Separate from `EXIFPolicy` on purpose. The ICC profile *is* metadata, so
/// "strip metadata" and "tag as sRGB" pull against each other: an untagged JPEG
/// is read as sRGB by convention in some validators and rejected outright by
/// others. Embedding is the safe default and stripping exists only for a spec
/// that demands it.
public enum ICCPolicy: Sendable, Hashable {
    case embedSRGB
    case stripAll
}

/// Where a spec's numbers came from, and when someone last looked.
///
/// Governments change these without announcement. A stale preset turns a
/// portal's rejection into our fault, so provenance is part of the data rather
/// than a comment.
public struct SpecSource: Sendable, Hashable {
    public let url: URL
    /// Nil when the official page could not be read. Such a preset renders as
    /// unverified rather than silently claiming a date.
    public let verifiedOn: Date?
    /// Why it is unverified, when it is.
    public let note: String?
    /// The page has gone. Kept so the catalog does not hand anyone a link that
    /// 404s, and so it is obvious the numbers have no live source at all.
    public let urlIsDead: Bool

    public init(url: URL, verifiedOn: Date?, note: String? = nil, urlIsDead: Bool = false) {
        self.url = url
        self.verifiedOn = verifiedOn
        self.note = note
        self.urlIsDead = urlIsDead
    }

    public var isVerified: Bool { verifiedOn != nil }

    /// Whether this URL can be put in front of someone.
    ///
    /// Custom carries a placeholder URL and no verification, and a dead source
    /// is kept deliberately so the catalog does not pretend the numbers have a
    /// live origin. Neither should ever become a tappable link.
    public var isLinkable: Bool { isVerified && !urlIsDead }

    /// Days since anyone confirmed these numbers, or nil if never.
    public func age(asOf now: Date = Date()) -> Int? {
        guard let verifiedOn else { return nil }
        return Calendar(identifier: .gregorian)
            .dateComponents([.day], from: verifiedOn, to: now).day
    }
}
