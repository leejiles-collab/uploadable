import Foundation
import CoreGraphics

/// Byte-level surgery on an encoded JPEG.
///
/// ## Why this exists
///
/// ImageIO will not embed an ICC profile for sRGB. Asked to write a JPEG from
/// an sRGB image — even from a colour space built out of raw ICC bytes — it
/// emits no `APP2/ICC_PROFILE` segment at all and instead declares sRGB with
/// the EXIF `ColorSpace` tag. It then *reports* the profile as
/// "sRGB IEC61966-2.1" when the file is read back, which is true in substance
/// and misleading in form: there is no profile in the file.
///
/// That has two consequences we care about:
///
/// - A validator that looks for an embedded profile finds nothing.
/// - The EXIF block becomes load-bearing, so stripping EXIF would delete the
///   only statement of colour space in the file.
///
/// Writing the APP2 segment ourselves resolves both. The profile is then
/// explicit, and EXIF can be removed without losing anything.
enum JPEGSegments {

    /// The sRGB profile Core Graphics ships, about 3.1 KB.
    static let sRGBProfile: Data? = {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let data = space.copyICCData()
        else { return nil }
        return data as Data
    }()

    /// Rewrites a JPEG: drops metadata segments, adds the colour profile.
    ///
    /// Returns nil when the input does not parse as a JPEG, in which case the
    /// caller should leave the file alone rather than write something worse.
    static func rewrite(_ data: Data, stripEXIF: Bool, embedSRGB: Bool) -> Data? {
        guard data.count > 4, data[0] == 0xFF, data[1] == 0xD8 else { return nil }

        var out = Data([0xFF, 0xD8])
        var injected = false
        var index = 2

        func injectProfileIfNeeded() {
            guard embedSRGB, !injected, let profile = sRGBProfile else { return }
            out.append(iccSegment(profile))
            injected = true
        }

        while index + 4 <= data.count {
            guard data[index] == 0xFF else { return nil }
            let marker = data[index + 1]

            // Start of scan: the profile must already be in, then copy the rest
            // of the file verbatim — entropy-coded data has no segment headers.
            if marker == 0xDA {
                injectProfileIfNeeded()
                out.append(data[index...])
                return out
            }

            let length = Int(data[index + 2]) << 8 | Int(data[index + 3])
            guard length >= 2, index + 2 + length <= data.count else { return nil }
            let segment = data[index..<(index + 2 + length)]

            switch marker {
            case 0xE0:
                // JFIF. Keep it, and put the profile straight after, which is
                // where every other encoder puts it.
                out.append(segment)
                injectProfileIfNeeded()
            case 0xE1 where stripEXIF:
                break  // Exif / XMP
            case 0xE2 where embedSRGB && isICC(segment):
                break  // an existing profile; ours replaces it
            case 0xED:
                break  // Photoshop IPTC block, which ImageIO adds and nothing needs
            default:
                injectProfileIfNeeded()
                out.append(segment)
            }

            index += 2 + length
        }
        return nil
    }

    private static func isICC(_ segment: Data) -> Bool {
        let marker = Array("ICC_PROFILE\0".utf8)
        guard segment.count > 4 + marker.count else { return false }
        let start = segment.startIndex + 4
        return Array(segment[start..<(start + marker.count)]) == marker
    }

    /// One APP2 segment carrying the whole profile.
    ///
    /// The format allows a profile to be split across numbered chunks; sRGB is
    /// about 3 KB and a segment holds just under 64 KB, so one is always enough
    /// here. Anything larger is refused rather than silently truncated.
    private static func iccSegment(_ profile: Data) -> Data {
        let identifier = Data("ICC_PROFILE\0".utf8)
        let payload = identifier + Data([1, 1]) + profile   // chunk 1 of 1
        let length = payload.count + 2
        guard length <= 0xFFFF else { return Data() }
        return Data([0xFF, 0xE2, UInt8(length >> 8), UInt8(length & 0xFF)]) + payload
    }
}
