import Foundation

/// The App Group container, which is the only ground the app and the share
/// extension share.
public enum SharedContainer {

    public static var url: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: BundleConfig.appGroupID
        )
    }

    /// Where the extension leaves a finished file for the app to file.
    ///
    /// Deliberately not swept on a timer: this is the user's photo, and it
    /// waits as long as it takes for them to open the app.
    public static func handoffDirectory() -> URL? {
        guard let base = url else { return nil }
        let directory = base.appendingPathComponent("handoff", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

/// The Fits folder — where a saved photo goes and how it gets there.
///
/// `UIFileSharingEnabled` publishes exactly one directory to the Files app: the
/// *app's* Documents. An app extension has its own container and cannot write
/// there, so the extension stages into the App Group and the app files it on
/// next launch. Same shape as Smaller, same reason.
public enum FilesLibrary {

    public static let userFacingLocation = "Files → Fits"

    /// "IMG_1335.jpeg" fitted for DS-160 -> "IMG_1335-us-visa-ds160.jpg"
    public static func outputName(for originalName: String, spec: UploadSpec) -> String {
        let base = (originalName as NSString).deletingPathExtension
        return "\(base)-\(spec.id).jpg"
    }

    /// The app's Documents directory, shown in Files as *On My iPhone → Fits*.
    /// Meaningless inside an extension, which has its own container.
    public static var visibleDirectory: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    @discardableResult
    public static func save(_ file: URL, as preferredName: String) throws -> URL {
        guard let directory = visibleDirectory else { throw CocoaError(.fileNoSuchFile) }
        let destination = uniqueURL(in: directory, preferredName: preferredName)
        try FileManager.default.copyItem(at: file, to: destination)
        return destination
    }

    /// The extension's half of `save`: same naming, a directory it is allowed
    /// to write to.
    @discardableResult
    public static func stage(_ file: URL, as preferredName: String) throws -> URL {
        guard let directory = SharedContainer.handoffDirectory() else {
            throw CocoaError(.fileNoSuchFile)
        }
        let destination = uniqueURL(in: directory, preferredName: preferredName)
        try FileManager.default.copyItem(at: file, to: destination)
        return destination
    }

    /// Moves everything the extension staged into the visible folder. Called on
    /// app launch, which is the first moment anything is able to.
    @discardableResult
    public static func adoptStaged() -> [URL] {
        guard let staging = SharedContainer.handoffDirectory(), visibleDirectory != nil else {
            return []
        }
        let staged = (try? FileManager.default.contentsOfDirectory(
            at: staging, includingPropertiesForKeys: nil
        )) ?? []

        var adopted: [URL] = []
        for file in staged.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let landed = try? save(file, as: file.lastPathComponent) else { continue }
            try? FileManager.default.removeItem(at: file)
            adopted.append(landed)
        }
        return adopted
    }

    /// Never overwrites. Someone fitting the same photo to two specs, or twice
    /// at different crops, wants both.
    public static func uniqueURL(in directory: URL, preferredName: String) -> URL {
        let name = preferredName as NSString
        let base = name.deletingPathExtension
        let ext = name.pathExtension.isEmpty ? "jpg" : name.pathExtension

        var candidate = directory.appendingPathComponent("\(base).\(ext)")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base)-\(counter).\(ext)")
            counter += 1
        }
        return candidate
    }
}
