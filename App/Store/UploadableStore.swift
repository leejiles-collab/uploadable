import Foundation
import Observation
import CoreGraphics
import UploadableKit

/// A photo the user handed us, copied somewhere we control.
struct ImportedPhoto: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let facts: SourceFacts
    /// Small, upright, for the crop screen. Nil only if the file will not decode
    /// at all, which the import already refuses.
    let preview: CGImage?

    var displayName: String { url.lastPathComponent }
    /// After the orientation flag is applied — the frame the user actually sees.
    var size: PixelSize { facts.uprightSize }
}

/// One screen at a time, chosen by what the engine is doing.
@MainActor
@Observable
final class UploadableStore {

    enum Phase {
        case home
        /// Photo in hand, choosing where it is going and placing the crop.
        case choosing(ImportedPhoto)
        case working(ImportedPhoto, UploadSpec)
        case done(Fit)
        /// Refused, with the numbers that explain it.
        case failed(FitFailure, UploadSpec?)
    }

    private(set) var phase: Phase = .home
    private(set) var steps: [FitStep] = []

    /// The chosen destination, and where in the photograph to take it from.
    var spec: UploadSpec?
    var crop: CropRect = .full

    /// Custom spec fields, kept as text so a half-typed number is not a crash.
    var customWidth = "600"
    var customHeight = "600"
    var customMinKB = "0"
    var customMaxKB = "240"

    /// Fitting a photo is free and unlimited; getting the file out is metered.
    let purchases = PurchaseStore()
    let exports = ExportStore()
    private(set) var exportsRemaining = Config.freeExports
    /// Shown only when an export is actually blocked.
    var isShowingPaywall = false

    private var engine: FitEngine?
    private var task: Task<Void, Never>?
    private let inbox: URL

    init() {
        inbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("uploadable-inbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
    }

    // MARK: - Launch

    /// Files whatever the share extension saved while the app was not running.
    /// The extension cannot reach the Files folder from its own sandbox, so
    /// this is the moment its work becomes visible.
    func adoptExtensionOutput() {
        FilesLibrary.adoptStaged()
    }

    /// Puts the free-export meter back, for testing on a real device.
    ///
    /// Reachable only where `BuildEnvironment.isTestBuild` is true, which is
    /// Xcode, the simulator, TestFlight and App Review — never an App Store
    /// purchase. The method itself is unconditional so that the gate lives in
    /// exactly one place and is testable; the caller is what is gated.
    func resetExportsForTesting() async {
        await exports.reset()
        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        await purchases.start()
        exportsRemaining = await exports.remaining
    }

    // MARK: - Exporting

    /// Whether this file may leave, without changing anything.
    ///
    /// The same bytes exported a second time are free: saving one result to
    /// Photos and then to Files and then sharing it is one export, not three.
    func mayExport(_ fit: Fit) async -> Bool {
        await exports.isAllowed(fit.url, isPro: purchases.isPro)
    }

    /// Called after an export lands, never before — a save that fails should
    /// cost nothing.
    func recordExport(_ fit: Fit) async {
        await exports.record(fit.url)
        exportsRemaining = await exports.remaining
    }

    func showPaywall() { isShowingPaywall = true }
    func dismissPaywall() { isShowingPaywall = false }

    // MARK: - Getting a photo in

    func open(data: Data, suggestedName: String) {
        let destination = inbox.appendingPathComponent(suggestedName)
        try? FileManager.default.removeItem(at: destination)
        do {
            try data.write(to: destination)
            try open(url: destination)
        } catch {
            phase = .failed(.unreadableSource("It could not be saved to work on."), nil)
        }
    }

    func open(url: URL) throws {
        let facts = try ImageNormaliser.facts(of: url)
        let photo = ImportedPhoto(
            url: url,
            facts: facts,
            preview: ImageNormaliser.preview(url: url)
        )
        spec = nil
        crop = .full
        phase = .choosing(photo)
    }

    func failedToPick() {
        phase = .failed(.unreadableSource("That photo could not be opened."), nil)
    }

    // MARK: - Choosing

    /// Picking a destination is also what reveals the crop, so the two happen
    /// together: the rect starts centred, which is what the engine would have
    /// done unaided.
    func select(_ chosen: UploadSpec) {
        spec = chosen
        guard case .choosing(let photo) = phase else { return }
        crop = .centred(aspect: chosen.aspect.value, in: photo.size)
    }

    var customSpec: UploadSpec {
        let width = max(1, Int(customWidth) ?? 600)
        let height = max(1, Int(customHeight) ?? 600)
        let minBytes = max(0, (Int(customMinKB) ?? 0) * 1000)
        let maxBytes = max(minBytes + 1, (Int(customMaxKB) ?? 240) * 1000)
        // The shape comes from the numbers typed. Someone entering 600 × 600 is
        // describing a square, and asking them to say so twice would be rude.
        let aspect: AspectRule = width == height
            ? .square
            : .ratio(w: width, h: height, tolerance: 0.01)
        return SpecCatalog.custom(
            width: width...width,
            height: height...height,
            bytes: minBytes...maxBytes,
            aspect: aspect
        )
    }

    // MARK: - Fitting

    func start() {
        guard case .choosing(let photo) = phase, let spec else { return }
        steps = []
        phase = .working(photo, spec)

        let url = photo.url
        let rect = crop
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let engine = try self.makeEngine()
                let fit = try await engine.fit(
                    url: url,
                    to: spec,
                    crop: rect,
                    outputName: Self.outputName(for: photo, spec: spec)
                ) { step in
                    Task { @MainActor [weak self] in self?.note(step) }
                }
                self.phase = .done(fit)
            } catch let failure as FitFailure {
                self.phase = .failed(failure, spec)
            } catch {
                self.phase = .failed(.unreadableSource("\(error.localizedDescription)"), spec)
            }
        }
    }

    private func note(_ step: FitStep) {
        // Resizing is reported once per candidate size; showing every one of
        // them would flicker, and the person does not care which rung it is on.
        if case .resizing = step, steps.contains(where: { if case .resizing = $0 { true } else { false } }) {
            return
        }
        if steps.last != step { steps.append(step) }
    }

    private static func outputName(for photo: ImportedPhoto, spec: UploadSpec) -> String {
        let base = (photo.displayName as NSString).deletingPathExtension
        return "\(base)-\(spec.id)"
    }

    // MARK: - Getting out

    func startOver() {
        task?.cancel()
        task = nil
        let engine = self.engine
        Task { await engine?.discardOutputs() }
        spec = nil
        crop = .full
        steps = []
        phase = .home
    }

    /// Back to the spec screen with the same photo, which is what someone wants
    /// after a refusal that a different destination would not have.
    func chooseAgain() {
        switch phase {
        case .working(let photo, _), .choosing(let photo):
            phase = .choosing(photo)
        default:
            startOver()
        }
        steps = []
    }

    func cancelWork() {
        task?.cancel()
        task = nil
        chooseAgain()
    }

    private func makeEngine() throws -> FitEngine {
        if let engine { return engine }
        let made = try FitEngine()
        engine = made
        return made
    }
}
