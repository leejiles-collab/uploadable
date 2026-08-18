import Foundation
import Photos

/// Adding a finished file to the photo library.
///
/// This is a `nonisolated` type rather than a method on a view, for one
/// specific reason that cost a shipped crash.
///
/// `PHPhotoLibrary.performChanges` takes a non-`Sendable` block and runs it on
/// its own serial queue, `com.apple.PHPhotoLibrary.changes`. A closure written
/// inside a `@MainActor` context — which every SwiftUI view method is —
/// silently *inherits* that isolation. Nothing is written down and nothing
/// warns, because the compiler believes the promise. Swift 6 then verifies it
/// at runtime when Photos invokes the block off the main actor, the check
/// fails, and the process traps with `EXC_BREAKPOINT`.
///
/// The important part: no `assumeIsolated` appears anywhere. Grepping for one
/// finds nothing. The isolation was inferred, and inference is exactly what
/// makes this class of bug invisible in review.
///
/// Keeping the call in a non-isolated context removes the inference at source,
/// which is why this file exists and why the work does not belong in a view.
public enum PhotosLibrary {

    public enum Failure: LocalizedError {
        case notPermitted

        public var errorDescription: String? {
            switch self {
            case .notPermitted:
                "Uploadable needs permission to add photos. You can grant it in Settings."
            }
        }
    }

    /// Asks for add-only access, then writes the file in as a new asset.
    ///
    /// Add-only on purpose: the app never reads the library, so requesting read
    /// access would be asking for something it has no use for.
    public static func add(_ url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw Failure.notPermitted
        }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset()
                .addResource(with: .photo, fileURL: url, options: nil)
        }
    }
}
