import SwiftUI
import PhotosUI
import UploadableKit

/// One thing to do. Everything else on this screen is there to explain that
/// there is only one thing to do.
struct HomeView: View {
    let onPicked: (Data, String) -> Void
    let onFailed: () -> Void
    /// Only ever called from a test build. See `ResetOnLongPress` below.
    let onResetExports: () -> Void
    /// Shown only in a test build, so a tester can see the meter move.
    let exportsRemaining: Int

    @State private var selection: PhotosPickerItem?
    @State private var isLoading = false
    @State private var askingToReset = false

    var body: some View {
        // Read here and capture by value. `body` is main-actor isolated but
        // PhotosPicker's label closure is not, so referencing `isLoading`
        // inside it is a Swift 6 isolation violation — a warning today, an
        // error on a stricter toolchain. The local is re-made every time body
        // runs, so it is never stale.
        let loading = isLoading

        return VStack(spacing: Metrics.stackSpacing) {
            Spacer()

            VStack(spacing: 8) {
                Text("Uploadable")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                Text("Make your photo fit.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                if BuildEnvironment.isTestBuild, !BuildEnvironment.isCapturingScreenshots {
                    // Says so out loud. A hidden control a tester cannot see is
                    // one they will not find when they need it, and one nobody
                    // remembers to check for before release.
                    Text("Test build · \(exportsRemaining) free "
                         + "export\(exportsRemaining == 1 ? "" : "s") left · "
                         + "hold the title to reset")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
            }
            .accessibilityElement(children: .combine)
            .modifier(ResetOnLongPress(
                isEnabled: BuildEnvironment.isTestBuild && !BuildEnvironment.isCapturingScreenshots
            ) {
                askingToReset = true
            })
            .confirmationDialog(
                "Reset the free export count?",
                isPresented: $askingToReset,
                titleVisibility: .visible
            ) {
                Button("Reset", role: .destructive, action: onResetExports)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Puts the meter back to \(Config.freeExports) free exports. "
                     + "Test builds only.")
            }

            Spacer()

            // No `photoLibrary:` argument on purpose. That variant binds the
            // picker to the app's own library access, which exists so you can
            // receive asset identifiers — we load `Data` and never touch an
            // identifier, so it buys nothing and costs a read-authorisation
            // prompt the app has no reason to ask for. Without it the picker
            // runs out of process and needs no permission at all.
            PhotosPicker(selection: $selection, matching: .images) {
                Group {
                    if loading {
                        ProgressView()
                    } else {
                        Text("Select Photo").font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(loading)

            Text("Or share a photo to Uploadable from any app.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer().frame(height: 24)
        }
        .padding(.horizontal, Metrics.screenPadding)
        .frame(maxWidth: Metrics.contentWidth)
        .frame(maxWidth: .infinity)
        .onChange(of: selection) { _, item in
            guard let item else { return }
            isLoading = true
            Task {
                defer { isLoading = false; selection = nil }
                guard let data = try? await item.loadTransferable(type: Data.self) else {
                    onFailed()
                    return
                }
                // The picker's own filename when it has one; otherwise something
                // stable, because the output is named after the input.
                let name = item.supportedContentTypes.first?.preferredFilenameExtension
                    .map { "Photo.\($0)" } ?? "Photo.jpg"
                onPicked(data, name)
            }
        }
    }
}

/// Attaches the reset gesture only when this is a test build.
///
/// A `ViewModifier` rather than a conditional `.onLongPressGesture`, because
/// applying a gesture conditionally inside a view builder changes the view's
/// identity between branches and SwiftUI rebuilds the subtree. Here the branch
/// is on whether the gesture exists at all, and in a production build the
/// closure is never installed.
private struct ResetOnLongPress: ViewModifier {
    let isEnabled: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            // Two seconds. Long enough that nobody arrives here by accident
            // while waiting for the picker.
            content.onLongPressGesture(minimumDuration: 2.0, perform: action)
        } else {
            content
        }
    }
}
