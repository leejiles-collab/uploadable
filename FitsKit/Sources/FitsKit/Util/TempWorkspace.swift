import Foundation

/// A directory that cleans up after itself.
///
/// Every intermediate encode lands here. The solver writes several candidates
/// before picking one, and none of them should outlive the run.
public final class TempWorkspace: @unchecked Sendable {
    public let root: URL
    private let lock = NSLock()

    public init(name: String) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    public func url(named name: String) -> URL {
        root.appendingPathComponent(name)
    }

    /// Drops everything except the file that won.
    public func discardAll(except keeper: URL?) {
        lock.lock()
        defer { lock.unlock() }
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil
        )) ?? []
        for file in contents where file.standardizedFileURL != keeper?.standardizedFileURL {
            try? FileManager.default.removeItem(at: file)
        }
    }

    public func cleanUp() {
        try? FileManager.default.removeItem(at: root)
    }

    deinit { try? FileManager.default.removeItem(at: root) }
}
