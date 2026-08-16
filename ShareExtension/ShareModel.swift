import Foundation
import Observation
import CoreGraphics
import UniformTypeIdentifiers
import FitsKit

/// The share sheet's state machine.
///
/// Smaller than the app's: one photo, it arrived rather than being chosen, and
/// the only way out is back to whatever the user was doing.
@MainActor
@Observable
final class ShareModel {

    enum Phase {
        case loading
        case choosing(ImportedPhoto)
        case working(UploadSpec)
        case done(Fit)
        case failed(String, String?)
    }

    struct ImportedPhoto {
        let url: URL
        let facts: SourceFacts
        let preview: CGImage?
        var size: PixelSize { facts.uprightSize }
    }

    private(set) var phase: Phase = .loading
    private(set) var steps: [FitStep] = []
    private(set) var exportsRemaining = Config.freeExports
    var isShowingPaywall = false

    var spec: UploadSpec?
    var crop: CropRect = .full

    let purchases = PurchaseStore()
    private let exports = ExportStore()
    private var engine: FitEngine?
    private var task: Task<Void, Never>?
    private let inbox: URL

    init() {
        inbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("fits-share-inbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
    }

    // MARK: - Loading

    func load(from providers: [NSItemProvider]) {
        task = Task { [weak self] in
            guard let self else { return }
            await self.purchases.start()
            self.exportsRemaining = await self.exports.remaining

            guard !providers.isEmpty else {
                self.phase = .failed("Nothing came through with that share.", nil)
                return
            }
            guard let provider = providers.first(where: {
                $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
            }) else {
                self.phase = .failed("That doesn't look like a photo.", nil)
                return
            }

            do {
                let url = try await self.copyIn(provider)
                let facts = try ImageNormaliser.facts(of: url)
                self.phase = .choosing(ImportedPhoto(
                    url: url, facts: facts, preview: ImageNormaliser.preview(url: url)
                ))
            } catch let failure as FitFailure {
                self.phase = .failed(failure.message, failure.remedy)
            } catch {
                self.phase = .failed("We couldn't read that photo.", nil)
            }
        }
    }

    private func copyIn(_ provider: NSItemProvider) async throws -> URL {
        let inbox = self.inbox
        return try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, error in
                guard let url else {
                    continuation.resume(throwing: error ?? CocoaError(.fileNoSuchFile))
                    return
                }
                // The URL is only valid inside this callback, so the copy has to
                // happen here rather than after it returns.
                let destination = inbox.appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.removeItem(at: destination)
                do {
                    try FileManager.default.copyItem(at: url, to: destination)
                    continuation.resume(returning: destination)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Choosing

    func select(_ chosen: UploadSpec) {
        spec = chosen
        guard case .choosing(let photo) = phase else { return }
        crop = .centred(aspect: chosen.aspect.value, in: photo.size)
    }

    // MARK: - Fitting

    func start() {
        guard case .choosing(let photo) = phase, let spec else { return }
        steps = []
        phase = .working(spec)

        let url = photo.url
        let rect = crop
        let name = (photo.url.deletingPathExtension().lastPathComponent) + "-\(spec.id)"
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let engine = try self.makeEngine()
                let fit = try await engine.fit(
                    url: url, to: spec, crop: rect, outputName: name
                ) { step in
                    Task { @MainActor [weak self] in self?.note(step) }
                }
                self.phase = .done(fit)
            } catch let failure as FitFailure {
                self.phase = .failed(failure.message, failure.remedy)
            } catch {
                self.phase = .failed("Something went wrong fitting that photo.", nil)
            }
        }
    }

    private func note(_ step: FitStep) {
        if case .resizing = step,
           steps.contains(where: { if case .resizing = $0 { true } else { false } }) { return }
        if steps.last != step { steps.append(step) }
    }

    // MARK: - Exporting

    func mayExport(_ fit: Fit) async -> Bool {
        await exports.isAllowed(fit.url, isPro: purchases.isPro)
    }

    func recordExport(_ fit: Fit) async {
        await exports.record(fit.url)
        exportsRemaining = await exports.remaining
    }

    /// Save to Files, from a process that cannot reach the Files folder.
    ///
    /// An extension has its own container, so this stages into the App Group
    /// and the app files it into *On My iPhone → Fits* the next time it runs.
    /// The sheet says so rather than claiming the photo is somewhere it is not
    /// yet — the same honesty Smaller needed for exactly the same reason.
    func saveToFiles(_ fit: Fit) -> String {
        do {
            _ = try FilesLibrary.stage(fit.url, as: fit.url.lastPathComponent)
            return "Saved. It'll be in \(FilesLibrary.userFacingLocation) next time you open Fits."
        } catch {
            return "Couldn't save that. \(error.localizedDescription)"
        }
    }

    func showPaywall() { isShowingPaywall = true }
    func dismissPaywall() { isShowingPaywall = false }

    func cancel() {
        task?.cancel()
        task = nil
    }

    func tearDown() {
        cancel()
        let engine = self.engine
        Task { await engine?.discardOutputs() }
        try? FileManager.default.removeItem(at: inbox)
    }

    private func makeEngine() throws -> FitEngine {
        if let engine { return engine }
        let made = try FitEngine()
        engine = made
        return made
    }
}
