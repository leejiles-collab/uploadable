import SwiftUI
import UniformTypeIdentifiers

/// Wrapper so `fileExporter` can hand over a file we already wrote, without
/// reading it into memory first.
public struct ExportedImage: FileDocument {
    public static var readableContentTypes: [UTType] { [.jpeg] }

    public let url: URL

    public init(url: URL) { self.url = url }

    public init(configuration: ReadConfiguration) throws {
        throw CocoaError(.fileReadUnsupportedScheme)
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try FileWrapper(url: url, options: .immediate)
    }
}
