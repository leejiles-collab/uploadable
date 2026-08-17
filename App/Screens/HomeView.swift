import SwiftUI
import PhotosUI
import UploadableKit

/// One thing to do. Everything else on this screen is there to explain that
/// there is only one thing to do.
struct HomeView: View {
    let onPicked: (Data, String) -> Void
    let onFailed: () -> Void

    @State private var selection: PhotosPickerItem?
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: Metrics.stackSpacing) {
            Spacer()

            VStack(spacing: 8) {
                Text("Uploadable")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                Text("Make your photo fit.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            Spacer()

            // No `photoLibrary:` argument on purpose. That variant binds the
            // picker to the app's own library access, which exists so you can
            // receive asset identifiers — we load `Data` and never touch an
            // identifier, so it buys nothing and costs a read-authorisation
            // prompt the app has no reason to ask for. Without it the picker
            // runs out of process and needs no permission at all.
            PhotosPicker(selection: $selection, matching: .images) {
                Group {
                    if isLoading {
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
            .disabled(isLoading)

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
