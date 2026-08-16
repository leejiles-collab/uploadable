import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import FitsKit

// The harness. Everything here runs the same engine the app runs, so a number
// printed here is a number the app would produce.

let usage = """
fitscli — FitsKit test harness

  fitscli inspect <images...>
      What each file actually is: real format, colour profile, dimensions,
      whether it carries EXIF or location data.

  fitscli fit --spec <id> <images...> --out DIR
      Fit each image to one spec and write the result.

  fitscli report <images...> [--out DIR] > report.md
      Every image against every spec, with verification detail and 1:1 PNG
      renders written to <out>/visual/.

  fitscli pair --spec <id> <image> --out DIR
      The same photo twice — identical pixels and size, one tagged sRGB and
      one tagged Display P3 — so a portal can settle the question by upload.

  fitscli specs --check
      Every preset with its numbers, source URL and verification date,
      oldest first.

Specs: \(SpecCatalog.all.map(\.id).joined(separator: ", "))
"""

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else {
    print(usage)
    exit(0)
}

func value(for flag: String) -> String? {
    guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
    return arguments[i + 1]
}

func imagePaths() -> [URL] {
    var skipNext = false
    var out: [URL] = []
    for argument in arguments.dropFirst() {
        if skipNext { skipNext = false; continue }
        if argument.hasPrefix("--") {
            skipNext = ["--spec", "--out"].contains(argument)
            continue
        }
        out.append(URL(fileURLWithPath: argument))
    }
    return out
}

let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "d MMM yyyy"
    f.timeZone = TimeZone(identifier: "UTC")
    return f
}()

func verifiedLabel(_ spec: UploadSpec) -> String {
    guard let date = spec.source.verifiedOn else { return "UNVERIFIED" }
    let age = spec.source.age() ?? 0
    let stale = age > Config.specStaleAfterDays ? " (STALE)" : ""
    return dateFormatter.string(from: date) + stale
}

func describe(_ spec: UploadSpec) -> String {
    let formats = spec.accepted
        .compactMap { $0.preferredFilenameExtension?.uppercased() }
        .sorted()
        .joined(separator: "/")
    return "\(spec.requirementSummary) · \(formats)"
}

// MARK: - inspect

func inspect(_ urls: [URL]) throws {
    for url in urls {
        print(url.lastPathComponent)
        do {
            let facts = try ImageNormaliser.facts(of: url)
            let claimed = url.pathExtension.lowercased()
            let actual = facts.type?.preferredFilenameExtension?.lowercased() ?? "unknown"
            print("  real format     \(facts.type?.identifier ?? "unknown")")
            if !claimed.isEmpty, actual != "unknown", claimed != actual,
               !(claimed == "jpg" && actual == "jpeg") {
                print("  MISMATCH        named .\(claimed) but it is really .\(actual)")
            }
            print("  dimensions      \(ByteFormat.size(facts.pixelWidth, facts.pixelHeight))")
            print("  size            \(ByteFormat.string(facts.byteCount)) (\(facts.byteCount) bytes)")
            print("  colour profile  \(facts.profileName ?? "untagged")")
            print("  orientation     \(facts.orientation)")
            print("  EXIF            \(facts.hasEXIF ? "present" : "none")")
            print("  location data   \(facts.hasGPS ? "PRESENT" : "none")")
        } catch {
            print("  unreadable      \((error as? FitFailure)?.message ?? "\(error)")")
        }
        print()
    }
}

// MARK: - fit

func fit(_ urls: [URL], specID: String, outDirectory: URL) async throws {
    guard let spec = SpecCatalog.spec(id: specID) else {
        print("unknown spec '\(specID)'. Known: \(SpecCatalog.all.map(\.id).joined(separator: ", "))")
        exit(1)
    }
    try FileManager.default.createDirectory(at: outDirectory, withIntermediateDirectories: true)
    let engine = try FitEngine()

    for url in urls {
        let stem = url.deletingPathExtension().lastPathComponent
        do {
            let result = try await engine.fit(url: url, to: spec, outputName: "\(stem)-\(spec.id)")
            let destination = outDirectory.appendingPathComponent(result.url.lastPathComponent)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: result.url, to: destination)
            print("\(url.lastPathComponent)  ->  \(ByteFormat.size(result.pixelWidth, result.pixelHeight))"
                + "  \(ByteFormat.string(result.byteCount))"
                + "  q\(String(format: "%.2f", result.quality))"
                + "  \(result.encodeCount) encodes"
                + "  \(String(format: "%.2fs", result.elapsed))"
                + "  \(result.verification.passed ? "verified" : "VERIFICATION FAILED")"
                + "\(result.hitEncodeCap ? "  ENCODE CAP HIT" : "")")
            for warning in result.warnings { print("      warning: \(warning.message)") }
        } catch let failure as FitFailure {
            print("\(url.lastPathComponent)  ->  \(failure.message)")
        }
    }
    await engine.discardOutputs()
}

// MARK: - specs --check

func checkSpecs() {
    func show(_ spec: UploadSpec) {
        print("\(spec.id)")
        print("  name          \(spec.name)  (\(spec.issuer))")
        print("  requirements  \(describe(spec))")
        print("  emits         \(spec.output.preferredFilenameExtension?.uppercased() ?? "?")"
            + " (\(spec.mandatesOutputFormat ? "the only format accepted" : "one of several accepted"))")
        print("  verified      \(verifiedLabel(spec))")
        print("  source        \(spec.source.url.absoluteString)\(spec.source.urlIsDead ? "   [DEAD LINK]" : "")")
        if let note = spec.source.note { print("  note          \(note)") }
        for caveat in spec.caveats { print("  caveat        \(caveat)") }
        print()
    }

    let offered = SpecCatalog.all.sorted {
        ($0.source.verifiedOn ?? .distantPast) < ($1.source.verifiedOn ?? .distantPast)
    }
    print("OFFERED — shown to the user")
    print()
    for spec in offered { show(spec) }

    print("DRAFTS — never offered, not in the report")
    print()
    for spec in SpecCatalog.drafts { show(spec) }

    let unverifiedOffered = SpecCatalog.all.filter { !$0.source.isVerified }
    let stale = SpecCatalog.all.filter { ($0.source.age() ?? 0) > Config.specStaleAfterDays }
    let toothless = SpecCatalog.all.filter { !$0.constrainsSomething }

    print("\(SpecCatalog.all.count) offered · \(SpecCatalog.drafts.count) drafts"
        + " · \(unverifiedOffered.count) offered but unverified"
        + " · \(stale.count) older than \(Config.specStaleAfterDays) days")

    if !unverifiedOffered.isEmpty {
        print("PROBLEM: unverified presets are being offered: "
            + unverifiedOffered.map(\.id).joined(separator: ", "))
    }
    if !toothless.isEmpty {
        print("PROBLEM: offered presets that rule nothing out: "
            + toothless.map(\.id).joined(separator: ", "))
    }
    if !stale.isEmpty {
        print("re-read the official pages for: " + stale.map(\.id).joined(separator: ", "))
    }
    if unverifiedOffered.isEmpty && toothless.isEmpty && stale.isEmpty {
        print("every offered preset was read off its official page and is current")
    }
}

// MARK: - report

func writePNG(_ url: URL, to destination: URL, maxEdge: Int = 900) {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
          let space = CGColorSpace(name: CGColorSpace.sRGB)
    else { return }
    let scale = min(1.0, Double(maxEdge) / Double(max(image.width, image.height)))
    let width = max(1, Int(Double(image.width) * scale))
    let height = max(1, Int(Double(image.height) * scale))
    guard let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { return }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let out = context.makeImage(),
          let d = CGImageDestinationCreateWithURL(
              destination as CFURL, UTType.png.identifier as CFString, 1, nil
          ) else { return }
    CGImageDestinationAddImage(d, out, nil)
    CGImageDestinationFinalize(d)
}

func report(_ urls: [URL], outDirectory: URL) async throws {
    let visual = outDirectory.appendingPathComponent("visual", isDirectory: true)
    try FileManager.default.createDirectory(at: visual, withIntermediateDirectories: true)
    let engine = try FitEngine()

    print("# Fits engine report")
    print()
    print("Generated \(dateFormatter.string(from: Date())) · \(urls.count) fixtures · \(SpecCatalog.all.count) specs")
    print()

    print("## Presets")
    print()
    print("| Spec | Requirements | Verified | Source |")
    print("|---|---|---|---|")
    for spec in SpecCatalog.all {
        print("| \(spec.name) | \(describe(spec)) | \(verifiedLabel(spec)) | [link](\(spec.source.url.absoluteString)) |")
    }
    print()

    for url in urls {
        print("## \(url.lastPathComponent)")
        print()
        guard let facts = try? ImageNormaliser.facts(of: url) else {
            print("Could not be read as an image.")
            print()
            continue
        }
        print("- real format: `\(facts.type?.identifier ?? "unknown")`")
        print("- dimensions: \(ByteFormat.size(facts.pixelWidth, facts.pixelHeight))")
        print("- size: \(ByteFormat.string(facts.byteCount))")
        print("- colour profile: \(facts.profileName ?? "untagged")")
        print("- EXIF: \(facts.hasEXIF ? "present" : "none") · location: \(facts.hasGPS ? "PRESENT" : "none")")
        print("- orientation flag: \(facts.orientation)")
        print()

        let stem = url.deletingPathExtension().lastPathComponent
        writePNG(url, to: visual.appendingPathComponent("\(stem)-source.png"))

        print("| Spec | Result | Size | Bytes | In band | Quality | Candidates | Encodes | Time | Checks |")
        print("|---|---|---|---|---|---|---|---|---|---|")
        for spec in SpecCatalog.all {
            do {
                let fit = try await engine.fit(url: url, to: spec, outputName: "\(stem)-\(spec.id)")
                let out = visual.appendingPathComponent("\(stem)-\(spec.id).png")
                writePNG(fit.url, to: out)
                var checks = fit.verification.checks
                    .map { "\($0.passed ? "ok" : "FAIL") \($0.name)" }
                    .joined(separator: "<br>")
                if !fit.warnings.isEmpty {
                    checks += "<br>" + fit.warnings
                        .map { "WARN \($0.message)" }
                        .joined(separator: "<br>")
                }
                print("| \(spec.name) | fit | \(ByteFormat.size(fit.pixelWidth, fit.pixelHeight)) "
                    + "| \(ByteFormat.string(fit.byteCount)) "
                    + "| \(spec.bytes.contains(fit.byteCount) ? "yes" : "NO") "
                    + "| \(String(format: "%.2f", fit.quality)) "
                    + "| \(fit.candidatesTried.joined(separator: ", ")) "
                    + "| \(fit.encodeCount)\(fit.hitEncodeCap ? " CAPPED" : "") "
                    + "| \(String(format: "%.2fs", fit.elapsed)) | \(checks) |")
            } catch let failure as FitFailure {
                print("| \(spec.name) | refused | — | — | — | — | — | — | — | \(failure.message) |")
            }
        }
        print()
    }
    await engine.discardOutputs()
}

// MARK: - pair

/// Writes the same photograph twice: identical pixels and dimensions, one
/// tagged sRGB and one tagged Display P3.
///
/// This exists to settle one question by experiment rather than assertion —
/// whether a portal actually rejects a non-sRGB profile. Upload both and see.
/// Everything else about the two files is held constant so that a difference in
/// outcome can only be the colour tag.
func pair(_ url: URL, specID: String, outDirectory: URL) async throws {
    guard let spec = SpecCatalog.spec(id: specID) else {
        print("unknown spec '\(specID)'")
        exit(1)
    }
    try FileManager.default.createDirectory(at: outDirectory, withIntermediateDirectories: true)

    let engine = try FitEngine()
    let stem = url.deletingPathExtension().lastPathComponent
    let fit = try await engine.fit(url: url, to: spec, outputName: "\(stem)-srgb")

    let srgbURL = outDirectory.appendingPathComponent("\(stem)-\(spec.id)-srgb.jpg")
    try? FileManager.default.removeItem(at: srgbURL)
    try FileManager.default.copyItem(at: fit.url, to: srgbURL)

    // Redraw the finished sRGB image into Display P3. Drawing converts the
    // values, so the two files look the same on screen; only the tag differs.
    guard let source = CGImageSourceCreateWithURL(srgbURL as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
          let p3 = CGColorSpace(name: CGColorSpace.displayP3),
          let context = CGContext(
              data: nil, width: image.width, height: image.height,
              bitsPerComponent: 8, bytesPerRow: 0, space: p3,
              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
          )
    else {
        print("could not build the Display P3 variant")
        exit(1)
    }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    guard let p3Image = context.makeImage() else { exit(1) }

    let p3URL = outDirectory.appendingPathComponent("\(stem)-\(spec.id)-displayp3.jpg")
    guard let destination = CGImageDestinationCreateWithURL(
        p3URL as CFURL, UTType.jpeg.identifier as CFString, 1, nil
    ) else { exit(1) }
    CGImageDestinationAddImage(destination, p3Image, [
        kCGImageDestinationLossyCompressionQuality: fit.quality
    ] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { exit(1) }

    func describeFile(_ file: URL) -> String {
        let bytes = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0
        let data = (try? Data(contentsOf: file)) ?? Data()
        let viaImageIO = OutputVerifier.iccDescription(file) ?? "none"
        let embedded = OutputVerifier.rawICCDescription(data) ?? "none embedded"
        let size = OutputVerifier.imageIODimensions(file)?.label ?? "?"
        return """
          \(file.lastPathComponent)
            dimensions              \(size)
            bytes                   \(ByteFormat.string(bytes)) (\(bytes))
            ImageIO reports         \(viaImageIO)
            profile in the file     \(embedded)
        """
    }

    print("Matched pair for \(spec.name), quality \(String(format: "%.2f", fit.quality)):")
    print()
    print(describeFile(srgbURL))
    print(describeFile(p3URL))
    let a = (try? FileManager.default.attributesOfItem(atPath: srgbURL.path)[.size] as? Int) ?? 0
    let b = (try? FileManager.default.attributesOfItem(atPath: p3URL.path)[.size] as? Int) ?? 0
    print()
    print("  byte difference         \(abs(a - b)) bytes")
    print("  both in \(spec.name) band  \(spec.bytes.contains(a) && spec.bytes.contains(b) ? "yes" : "NO")")
    await engine.discardOutputs()
}

// MARK: - dispatch

let out = URL(fileURLWithPath: value(for: "--out") ?? "./out")

switch command {
case "inspect":
    try inspect(imagePaths())
case "fit":
    guard let spec = value(for: "--spec") else {
        print("fit needs --spec <id>")
        exit(1)
    }
    try await fit(imagePaths(), specID: spec, outDirectory: out)
case "report":
    try await report(imagePaths(), outDirectory: out)
case "pair":
    guard let image = imagePaths().first else {
        print("pair needs one image")
        exit(1)
    }
    try await pair(image, specID: value(for: "--spec") ?? "us-visa-ds160", outDirectory: out)
case "specs":
    checkSpecs()
default:
    print(usage)
}
