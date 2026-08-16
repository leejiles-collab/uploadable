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
    public let format: UTType
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
        format: UTType = .jpeg,
        color: ColorPolicy = .sRGB,
        exif: EXIFPolicy = .stripAll,
        icc: ICCPolicy = .embedSRGB,
        source: SpecSource,
        caveats: [String] = []
    ) {
        self.id = id
        self.name = name
        self.issuer = issuer
        self.aspect = aspect
        self.width = width
        self.height = height
        self.bytes = bytes
        self.format = format
        self.color = color
        self.exif = exif
        self.icc = icc
        self.source = source
        self.caveats = caveats
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

    public init(url: URL, verifiedOn: Date?, note: String? = nil) {
        self.url = url
        self.verifiedOn = verifiedOn
        self.note = note
    }

    public var isVerified: Bool { verifiedOn != nil }

    /// Days since anyone confirmed these numbers, or nil if never.
    public func age(asOf now: Date = Date()) -> Int? {
        guard let verifiedOn else { return nil }
        return Calendar(identifier: .gregorian)
            .dateComponents([.day], from: verifiedOn, to: now).day
    }
}
