import Foundation
import UploadableKit

#if DEBUG
/// Drives the app to a given screen at launch so it can be photographed.
///
/// `#if DEBUG`, so none of this exists in a TestFlight or App Store build — a
/// launch argument that rewrites app state has no business in a shipping
/// binary. It lives in the repository rather than being added and removed for
/// each capture, because the store screenshots have to be regenerated every
/// time the photo or the numbers change, and a pipeline that requires editing
/// source first is a pipeline nobody runs.
///
/// Every state it reaches is produced by the real engine on a real file. The
/// numbers on the screenshots are numbers the app actually produced.
enum ScreenshotHarness {

    static let fixtureName = "screenshot-source.jpg"

    @MainActor
    static func run(store: UploadableStore) async -> Bool {
        guard let argument = ProcessInfo.processInfo.arguments
            .first(where: { $0.hasPrefix("--screen=") })
        else { return false }

        let screen = String(argument.dropFirst("--screen=".count))
        if screen == "home" { return true }

        guard let documents = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first else { return true }
        let source = documents.appendingPathComponent(
            screen == "failure" ? "screenshot-too-small.jpg" : fixtureName
        )
        guard FileManager.default.fileExists(atPath: source.path) else { return true }

        try? store.open(url: source)
        store.select(spec(for: screen))

        // Drag the crop to the top of the photo, which is what a person does
        // and what the crop screen exists for. `select` leaves it centred, and
        // a centred square on a head-and-shoulders portrait clips the crown —
        // a store screenshot demonstrating that exact mistake would be an
        // unusually effective argument against buying the app.
        store.crop = CropRect(
            x: store.crop.x, y: 0, width: store.crop.width, height: store.crop.height
        )
        if screen == "crop" { return true }

        store.start()
        for _ in 0..<900 {
            if case .done = store.phase { break }
            if case .failed = store.phase { break }
            try? await Task.sleep(for: .milliseconds(50))
        }

        if screen == "paywall" {
            // Spend the allowance the way a person would, so the wall appears
            // for the real reason rather than because a flag was set.
            for _ in 0..<Config.freeExports {
                let scratch = FileManager.default.temporaryDirectory
                    .appendingPathComponent("spend-\(UUID().uuidString).jpg")
                try? Data(UUID().uuidString.utf8).write(to: scratch)
                await store.exports.record(scratch)
            }
            await store.refreshEntitlements()
            store.showPaywall()
        }
        return true
    }

    private static func spec(for screen: String) -> UploadSpec {
        screen == "nz" ? SpecCatalog.newZealand : SpecCatalog.usVisa
    }
}
#endif
