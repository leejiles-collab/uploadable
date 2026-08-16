import Testing
import Foundation
import Security
@testable import FitsKit

/// The meter: what it counts, what it refuses to count twice, and the thing
/// that makes it one meter rather than two.
struct ExportStoreTests {

    /// A private suite per test, so these never touch the real App Group count
    /// and never depend on each other's leftovers.
    private func freshStore(_ name: String = UUID().uuidString) -> ExportStore {
        UserDefaults().removePersistentDomain(forName: name)
        return ExportStore(suiteName: name, mirrorsToKeychain: false)
    }

    private func writeFile(_ contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-\(UUID().uuidString).jpg")
        try Data(contents.utf8).write(to: url)
        return url
    }

    // MARK: - Not charging three times for one photo

    /// Saving one result to Photos, then to Files, then sharing it is one
    /// export. Charging for each destination earns a one-star review and
    /// deserves to.
    @Test func theSameFileExportedThreeTimesCostsOnce() async throws {
        let store = freshStore()
        let file = try writeFile("the same finished photo")
        defer { try? FileManager.default.removeItem(at: file) }

        await store.record(file)
        await store.record(file)
        await store.record(file)

        #expect(await store.used == 1, "one photo, three destinations, should cost one")
        #expect(await store.remaining == Config.freeExports - 1)
        #expect(await store.isAlreadyExported(file))
    }

    /// Different bytes are a different export, even for the same source photo
    /// fitted twice.
    @Test func aDifferentResultIsADifferentExport() async throws {
        let store = freshStore()
        let first = try writeFile("fitted for DS-160")
        let second = try writeFile("fitted for New Zealand")
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }

        await store.record(first)
        await store.record(second)
        #expect(await store.used == 2)
    }

    // MARK: - The allowance

    @Test func twoAreFreeAndTheThirdIsBlocked() async throws {
        let store = freshStore()
        let files = try (1...3).map { try writeFile("result \($0)") }
        defer { files.forEach { try? FileManager.default.removeItem(at: $0) } }

        #expect(await store.isAllowed(files[0], isPro: false))
        await store.record(files[0])
        #expect(await store.isAllowed(files[1], isPro: false))
        await store.record(files[1])

        #expect(await store.isExhausted)
        #expect(await store.isAllowed(files[2], isPro: false) == false,
                "a third new export should be blocked")

        // Two, not one, because the second covers picking the wrong spec first.
        #expect(Config.freeExports == 2)
    }

    /// An already-paid-for file stays free after the allowance runs out —
    /// otherwise saving a photo to Files and then wanting it in Photos too
    /// would hit a paywall for something already bought.
    @Test func anAlreadyExportedFileStaysFreeOnceExhausted() async throws {
        let store = freshStore()
        let files = try (1...2).map { try writeFile("result \($0)") }
        defer { files.forEach { try? FileManager.default.removeItem(at: $0) } }

        for file in files { await store.record(file) }
        #expect(await store.isExhausted)

        #expect(await store.isAllowed(files[0], isPro: false),
                "a file already exported should not be charged again")
    }

    @Test func proIsAllowedEverything() async throws {
        let store = freshStore()
        let files = try (1...5).map { try writeFile("result \($0)") }
        defer { files.forEach { try? FileManager.default.removeItem(at: $0) } }

        for file in files {
            #expect(await store.isAllowed(file, isPro: true))
            await store.record(file)
        }
        #expect(await store.used == 5)
    }

    // MARK: - One meter, not two

    /// The app and the share extension are separate processes with separate
    /// containers. An export from the share sheet must decrement the same
    /// counter the app reads, or the free tier is worth double.
    @Test func theAppAndTheExtensionShareOneCount() async throws {
        let suite = UUID().uuidString
        // Two stores over the same App Group suite: the app's and the
        // extension's, as far as the storage layer is concerned.
        let app = freshStore(suite)
        let extensionSide = ExportStore(suiteName: suite, mirrorsToKeychain: false)

        let file = try writeFile("fitted in the share sheet")
        defer { try? FileManager.default.removeItem(at: file) }

        await extensionSide.record(file)

        #expect(await app.used == 1, "an export from the extension did not reach the app's count")
        #expect(await app.remaining == Config.freeExports - 1)
        #expect(await app.isAlreadyExported(file),
                "the app cannot see which files the extension already exported")
    }

    /// The reason that works, and the thing that would silently break it.
    ///
    /// Without `kSecAttrAccessGroup` each target writes its mirror to its own
    /// `application-identifier` default group — two items, same service, same
    /// account, invisible to each other, with the larger silently winning. That
    /// shipped in Smaller and took a day to find. See SCALLAPP.md.
    @Test func theKeychainMirrorIsScopedToTheAppGroup() {
        let query = ExportStore.query()
        #expect(query[kSecAttrAccessGroup as String] as? String == BundleConfig.appGroupID,
                "mirror not scoped to the app group: app and extension keep separate counts")
        #expect(query[kSecAttrService as String] as? String == BundleConfig.appGroupID)
        #expect(query[kSecAttrAccount as String] as? String != nil)
    }

    // MARK: - Identity

    @Test func identicalBytesHashTheSameAndDifferentBytesDoNot() throws {
        let a = try writeFile("identical")
        let b = try writeFile("identical")
        let c = try writeFile("different")
        defer { [a, b, c].forEach { try? FileManager.default.removeItem(at: $0) } }

        #expect(ExportStore.hash(of: a) == ExportStore.hash(of: b))
        #expect(ExportStore.hash(of: a) != ExportStore.hash(of: c))
        #expect(ExportStore.hash(of: a)?.count == 64)
    }
}
