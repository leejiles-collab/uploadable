import Foundation
import CoreGraphics
import ImageIO

/// Re-reads the file that was written and checks it against the spec.
///
/// Nothing here trusts the encoder. Where it can, it also avoids trusting
/// ImageIO: the dimensions are read twice, once through `CGImageSource` and
/// once by walking the JPEG's own segment headers. A library that wrote a file
/// wrongly can read it back wrongly in the same way, and two paths that agree
/// are worth more than one that is confident.
public enum OutputVerifier {

    public static func verify(_ url: URL, against spec: UploadSpec, expecting size: PixelSize) -> Verification {
        var checks: [Check] = []
        let bytes = (try? Data(contentsOf: url, options: .mappedIfSafe)) ?? Data()

        // 1. It is actually a JPEG, by its first two bytes.
        let soi = bytes.count >= 2 && bytes[0] == 0xFF && bytes[1] == 0xD8
        checks.append(Check(
            name: "JPEG format",
            passed: soi,
            detail: soi ? "starts with SOI marker FFD8"
                        : "does not start with FFD8 — this is not a JPEG"
        ))

        // 2. Byte count, from the filesystem rather than from anything we held.
        let onDisk = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? nil
        let count = onDisk ?? -1
        let inBand = spec.bytes.contains(count)
        checks.append(Check(
            name: "File size in range",
            passed: inBand,
            detail: count < 0 ? "could not be measured"
                : "\(ByteFormat.string(count)) — required \(ByteFormat.band(spec.bytes))"
        ))

        // 3. Dimensions via ImageIO.
        let reported = imageIODimensions(url)
        let dimensionsMatch = reported.map { $0 == size } ?? false
        checks.append(Check(
            name: "Dimensions",
            passed: dimensionsMatch,
            detail: reported.map { "\($0.label) (expected \(size.label))" } ?? "could not be read"
        ))

        // 4. Dimensions again, parsed straight out of the JPEG's SOF segment.
        let parsed = rawJPEGDimensions(bytes)
        let independentMatch = parsed.map { $0 == size } ?? false
        checks.append(Check(
            name: "Dimensions, independently parsed",
            passed: independentMatch,
            detail: parsed.map { "SOF header says \($0.label)" } ?? "no SOF segment found"
        ))

        // 5. Shape, against the spec's own rule.
        let shapeOK = spec.aspect.admits(width: size.width, height: size.height)
        checks.append(Check(
            name: "Aspect ratio",
            passed: shapeOK,
            detail: "\(size.label) against \(spec.aspect.label)"
        ))

        // 6. The colour profile, read back off disk.
        let profile = iccDescription(url) ?? rawICCDescription(bytes)
        switch spec.icc {
        case .embedSRGB:
            let name = profile ?? ""
            let looksSRGB = name.localizedCaseInsensitiveContains("srgb")
            checks.append(Check(
                name: "sRGB profile embedded",
                passed: looksSRGB,
                detail: profile.map { "profile reads \"\($0)\"" } ?? "no ICC profile found"
            ))
        case .stripAll:
            checks.append(Check(
                name: "No colour profile",
                passed: profile == nil,
                detail: profile.map { "unexpected profile \"\($0)\"" } ?? "none embedded"
            ))
        }

        // 7. Metadata that should not have survived.
        let properties = imageIOProperties(url)
        let hasEXIF = properties?[kCGImagePropertyExifDictionary] != nil
        let hasGPS = properties?[kCGImagePropertyGPSDictionary] != nil
        if spec.exif == .stripAll {
            checks.append(Check(
                name: "EXIF removed",
                passed: !hasEXIF,
                detail: hasEXIF ? "an EXIF dictionary is still present" : "none present"
            ))
            checks.append(Check(
                name: "Location data removed",
                passed: !hasGPS,
                detail: hasGPS ? "GPS tags are still present" : "none present"
            ))
        }

        return Verification(checks: checks)
    }

    // MARK: - Reading it back

    public static func imageIOProperties(_ url: URL) -> [CFString: Any]? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    }

    public static func imageIODimensions(_ url: URL) -> PixelSize? {
        guard let properties = imageIOProperties(url),
              let w = properties[kCGImagePropertyPixelWidth] as? Int,
              let h = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return PixelSize(width: w, height: h)
    }

    public static func iccDescription(_ url: URL) -> String? {
        imageIOProperties(url)?[kCGImagePropertyProfileName] as? String
    }

    // MARK: - The independent path

    /// Walks JPEG marker segments to the frame header and reads the size from
    /// it. Knows nothing about ImageIO.
    public static func rawJPEGDimensions(_ data: Data) -> PixelSize? {
        var i = 2  // past SOI
        while i + 4 <= data.count {
            guard data[i] == 0xFF else { i += 1; continue }
            let marker = data[i + 1]
            // Standalone markers carry no length.
            if marker == 0xD8 || marker == 0x01 || (0xD0...0xD7).contains(marker) {
                i += 2
                continue
            }
            guard i + 4 <= data.count else { return nil }
            let length = Int(data[i + 2]) << 8 | Int(data[i + 3])
            // SOF0/1/2/3/5/6/7/9/10/11/13/14/15 — every frame header except
            // DHT (C4), JPG (C8) and DAC (CC), which share the C0 block.
            if (0xC0...0xCF).contains(marker), marker != 0xC4, marker != 0xC8, marker != 0xCC {
                guard i + 9 < data.count else { return nil }
                let height = Int(data[i + 5]) << 8 | Int(data[i + 6])
                let width = Int(data[i + 7]) << 8 | Int(data[i + 8])
                return PixelSize(width: width, height: height)
            }
            if marker == 0xDA { return nil }  // start of scan, no header ahead
            i += 2 + length
        }
        return nil
    }

    /// Pulls the ICC profile out of the APP2 segments and reads its description
    /// tag, without asking ImageIO what it thinks the profile is.
    public static func rawICCDescription(_ data: Data) -> String? {
        guard let profile = rawICCProfile(data), profile.count > 132 else { return nil }
        let tagCount = be32(profile, 128)
        guard tagCount > 0, tagCount < 1000 else { return nil }

        for t in 0..<Int(tagCount) {
            let entry = 132 + t * 12
            guard entry + 12 <= profile.count else { break }
            let signature = String(bytes: profile[entry..<(entry + 4)], encoding: .ascii)
            guard signature == "desc" else { continue }
            let offset = Int(be32(profile, entry + 4))
            let size = Int(be32(profile, entry + 8))
            guard offset + size <= profile.count, size > 12 else { return nil }

            let type = String(bytes: profile[offset..<(offset + 4)], encoding: .ascii)
            if type == "desc" {
                // ICC v2: ASCII count then the string.
                let length = Int(be32(profile, offset + 8))
                let start = offset + 12
                guard length > 0, start + length <= profile.count else { return nil }
                return String(bytes: profile[start..<(start + length - 1)], encoding: .ascii)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if type == "mluc" {
                // ICC v4: first record, UTF-16BE.
                guard offset + 28 <= profile.count else { return nil }
                let length = Int(be32(profile, offset + 20))
                let start = offset + Int(be32(profile, offset + 24))
                guard length > 0, start + length <= profile.count else { return nil }
                return String(bytes: profile[start..<(start + length)], encoding: .utf16BigEndian)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    public static func rawICCProfile(_ data: Data) -> [UInt8]? {
        var chunks: [(Int, [UInt8])] = []
        var i = 2
        let marker = Array("ICC_PROFILE\0".utf8)
        while i + 4 <= data.count {
            guard data[i] == 0xFF else { i += 1; continue }
            let kind = data[i + 1]
            if kind == 0xD8 || kind == 0x01 || (0xD0...0xD7).contains(kind) { i += 2; continue }
            guard i + 4 <= data.count else { break }
            let length = Int(data[i + 2]) << 8 | Int(data[i + 3])
            if kind == 0xE2, i + 4 + marker.count + 2 <= data.count {
                let head = Array(data[(i + 4)..<(i + 4 + marker.count)])
                if head == marker {
                    let seq = Int(data[i + 4 + marker.count])
                    let start = i + 4 + marker.count + 2
                    let end = min(i + 2 + length, data.count)
                    if start < end { chunks.append((seq, Array(data[start..<end]))) }
                }
            }
            if kind == 0xDA { break }
            i += 2 + length
        }
        guard !chunks.isEmpty else { return nil }
        return chunks.sorted { $0.0 < $1.0 }.flatMap(\.1)
    }

    private static func be32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        guard offset + 4 <= bytes.count else { return 0 }
        return UInt32(bytes[offset]) << 24 | UInt32(bytes[offset + 1]) << 16
            | UInt32(bytes[offset + 2]) << 8 | UInt32(bytes[offset + 3])
    }
}
