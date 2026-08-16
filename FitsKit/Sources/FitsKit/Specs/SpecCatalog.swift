import Foundation
import UniformTypeIdentifiers

/// The presets, and where each one's numbers came from.
///
/// ## How to read this file
///
/// Every entry's `SpecSource` records the page the numbers were read off and
/// the day someone read it. `verifiedOn: nil` means the official page could not
/// be reached — the numbers are the best available but nobody has confirmed
/// them, and the UI says so.
///
/// Several official pages state a shape and a byte band and *no pixel
/// dimensions at all*. Those presets carry `width: nil, height: nil` rather
/// than a plausible-looking guess. An invented minimum would reject photos the
/// portal accepts, which is a worse failure than having no bound.
public enum SpecCatalog {

    /// A stand-in ceiling for specs that state a minimum and no maximum. Far
    /// above any phone camera, so it never binds in practice; it exists because
    /// a range needs two ends.
    public static let noStatedMaximum = 20_000

    /// The presets the app offers. Every one of these has been read off its
    /// official page by a person.
    public static var all: [UploadSpec] {
        [usVisa, usPassport, indiaEVisa, canadaPR, newZealand, ukPassport]
    }

    /// Started, but not fit to offer, and never shown as a choice.
    ///
    /// The DV Lottery has no published instructions outside its registration
    /// window and every secondary source disagrees with the others. Schengen's
    /// official page has been taken down. Guessing at either would be guessing
    /// at a one-shot immigration application, which is the worst place to be
    /// approximately right.
    public static var drafts: [UploadSpec] { [usDVLottery, schengen] }

    public static func spec(id: String) -> UploadSpec? {
        (all + drafts).first { $0.id == id }
    }

    // MARK: - Verified

    /// Read 15 August 2026. The State Department's own digital image page.
    ///
    /// Notable: this spec states the colour space outright — "in sRGB color
    /// space" — which makes sRGB conversion a documented requirement here
    /// rather than a precaution.
    public static let usVisa = UploadSpec(
        id: "us-visa-ds160",
        name: "US Visa (DS-160)",
        issuer: "US Department of State",
        aspect: .square,
        width: 600...1200,
        height: 600...1200,
        bytes: 0...240_000,
        source: SpecSource(
            url: URL(string: "https://adoption.state.gov/content/travel/en/us-visas/visa-information-resources/photos/digital-image-requirements.html")!,
            verifiedOn: day(2026, 8, 15),
            note: "State Department digital image requirements. travel.state.gov "
                + "serves the same page but blocks automated requests, so this "
                + "state.gov copy was read instead."
        ),
        caveats: [
            "The page also asks for a compression ratio of 20:1 or lower. Fits "
            + "does not target a ratio directly; it lands inside the byte band "
            + "at the highest quality that fits."
        ]
    )

    /// Read 15 August 2026. Official page, square requirement stated as
    /// "height and width must be equal"; no pixel dimensions given anywhere.
    public static let indiaEVisa = UploadSpec(
        id: "india-evisa",
        name: "India eVisa",
        issuer: "Government of India",
        aspect: .square,
        width: nil,
        height: nil,
        bytes: 10_000...1_000_000,
        source: SpecSource(
            url: URL(string: "https://indianvisaonline.gov.in/evisa/tvoa.html")!,
            verifiedOn: day(2026, 8, 15)
        ),
        caveats: [
            "The official page states no pixel dimensions — only that the photo "
            + "must be square. Fits keeps as much resolution as the byte band allows."
        ]
    )

    /// Read 15 August 2026. Dimensions and ceiling stated; no byte floor.
    /// 715×1000 and 2000×2800 are both 5:7 to within a tenth of a percent.
    public static let canadaPR = UploadSpec(
        id: "canada-pr",
        name: "Canada PR Card",
        issuer: "Immigration, Refugees and Citizenship Canada",
        aspect: .ratio(w: 5, h: 7, tolerance: 0.01),
        width: 715...2000,
        height: 1000...2800,
        bytes: 0...4_000_000,
        source: SpecSource(
            url: URL(string: "https://www.canada.ca/en/immigration-refugees-citizenship/services/permanent-residents/card/photos.html")!,
            verifiedOn: day(2026, 8, 15)
        )
    )

    /// Read 15 August 2026. The official page gives a 3:4 ratio and a byte band
    /// and states no pixel dimensions.
    public static let newZealand = UploadSpec(
        id: "nz-visa",
        name: "New Zealand Visa / NZeTA",
        issuer: "Immigration New Zealand",
        aspect: .ratio(w: 3, h: 4, tolerance: 0.005),
        width: nil,
        height: nil,
        bytes: 512_000...3_140_000,
        source: SpecSource(
            url: URL(string: "https://www.immigration.govt.nz/process-to-apply/applying-for-a-visa/applying-online/uploading-documents-and-photos/visa-and-nzeta-photos/")!,
            verifiedOn: day(2026, 8, 15)
        ),
        caveats: [
            "Portrait orientation is required.",
            "The widely-quoted 900×1200 to 2250×3000 pixel range does not appear "
            + "on the official page and could not be confirmed, so it is not enforced."
        ]
    )

    /// Read 15 August 2026. States a pixel floor and a byte band; no maximum
    /// dimension and no shape requirement are given.
    public static let ukPassport = UploadSpec(
        id: "uk-passport",
        name: "UK Passport",
        issuer: "HM Passport Office",
        aspect: .free,
        width: 600...noStatedMaximum,
        height: 750...noStatedMaximum,
        bytes: 50_000...10_000_000,
        source: SpecSource(
            url: URL(string: "https://www.gov.uk/photos-for-passports")!,
            verifiedOn: day(2026, 8, 15)
        ),
        caveats: [
            "The official page states a minimum of 600 × 750 pixels and no "
            + "maximum, and does not require a particular shape or file format."
        ]
    )

    // MARK: - Unverified

    /// DRAFT. Cannot be verified outside the registration window.
    public static let usDVLottery = UploadSpec(
        id: "us-dv-lottery",
        name: "US Diversity Visa (DV Lottery)",
        issuer: "US Department of State",
        aspect: .square,
        width: 600...1200,
        height: 600...1200,
        bytes: 0...240_000,
        source: SpecSource(
            url: URL(string: "https://dvprogram.state.gov/")!,
            verifiedOn: nil,
            note: "Checked 15 August 2026: dvprogram.state.gov shows no open "
                + "entry period and still displays DV-2026, which closed in "
                + "November 2024. The photo instructions publish only when "
                + "registration opens, around early October. Secondary sources "
                + "disagree over whether the requirement is exactly 600 × 600 "
                + "or a 600–1200 range, and this is a one-entry-per-year "
                + "application with no appeal, so nothing is offered until the "
                + "DV-YYYY Program Instructions PDF can be read."
        )
    )

    /// Read 15 August 2026 from the online-renewal upload page, which carries
    /// its own "Last Updated: May 04, 2026".
    ///
    /// States a byte band and a list of accepted formats, and nothing else. No
    /// pixel dimensions and no aspect ratio, because the applicant crops inside
    /// State's own tool after uploading.
    ///
    /// This preset previously claimed square and 600–1200. Both were carried
    /// over from DS-160 by assumption and appear nowhere in the source. The
    /// page that *was* linked covers printed photos — two inches square, head
    /// 25–35 mm — and has no digital file requirements on it at all.
    public static let usPassport = UploadSpec(
        id: "us-passport",
        name: "US Passport",
        issuer: "US Department of State",
        aspect: .free,
        width: nil,
        height: nil,
        bytes: 54_000...10_000_000,
        accepted: [.jpeg, .png, .heic, .heif],
        source: SpecSource(
            url: URL(string: "https://travel.state.gov/en/passports/renew-replace/online/upload-digital-photo.html")!,
            verifiedOn: day(2026, 8, 15)
        ),
        caveats: [
            "The page states no pixel dimensions and no aspect ratio — you crop "
            + "the photo inside the State Department's own tool after uploading.",
            "JPG, JPEG, PNG, HEIC and HEIF are all accepted. Fits writes JPEG, "
            + "which is on the list."
        ]
    )

    /// DRAFT. The official page has been removed.
    public static let schengen = UploadSpec(
        id: "schengen-france",
        name: "Schengen Visa (France)",
        issuer: "France-Visas",
        aspect: .free,
        width: nil,
        height: nil,
        bytes: 0...10_000_000,
        source: SpecSource(
            url: URL(string: "https://france-visas.gouv.fr/en/web/france-visas/photo")!,
            verifiedOn: nil,
            note: "Checked 15 August 2026: the page returns 404 — it has been "
                + "taken down, not merely blocked. No digital file requirements "
                + "could be confirmed anywhere, so this preset constrains almost "
                + "nothing and must not be offered.",
            urlIsDead: true
        )
    )

    // MARK: - Custom

    /// What the user types in when their form is not in the list.
    public static func custom(
        width: ClosedRange<Int>?,
        height: ClosedRange<Int>?,
        bytes: ClosedRange<Int>,
        aspect: AspectRule
    ) -> UploadSpec {
        UploadSpec(
            id: "custom",
            name: "Custom",
            issuer: "You",
            aspect: aspect,
            width: width,
            height: height,
            bytes: bytes,
            source: SpecSource(
                url: URL(string: "https://example.invalid/custom")!,
                verifiedOn: nil,
                note: "Numbers you entered."
            )
        )
    }

    // MARK: - Helpers

    private static func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(
            year: year, month: month, day: dayOfMonth
        ))!
    }
}
