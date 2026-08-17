import SwiftUI
import Photos
import UploadableKit

/// The spec being met, one line per requirement.
///
/// Not "83% smaller" — nobody is here to make a file small. They are here to
/// make it acceptable, so the payoff is the requirement and a tick beside it.
struct DoneView: View {
    let fit: Fit
    /// Whether this file may leave. Recomputed when the entitlement changes, so
    /// buying Pro on the paywall unlocks the buttons behind it without a
    /// round trip through another screen.
    let mayExport: Bool
    let onExported: () -> Void
    let onBlocked: () -> Void
    let onStartOver: () -> Void

    @State private var saveMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: Metrics.stackSpacing) {
                headline
                requirements

                if !fit.warnings.isEmpty {
                    VStack(spacing: Metrics.cardSpacing) {
                        ForEach(Array(fit.warnings.enumerated()), id: \.offset) { _, warning in
                            NoteRow(warning: warning)
                        }
                    }
                }

                actions

                if let saveMessage {
                    Text(saveMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button("Fit another photo", action: onStartOver)
                    .font(.callout)
                    .padding(.top, 4)
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.vertical, Metrics.stackSpacing)
            .frame(maxWidth: Metrics.contentWidth)
            .frame(maxWidth: .infinity)
        }
        .sensoryFeedback(.success, trigger: fit.byteCount)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done", action: onStartOver)
            }
        }
    }

    // MARK: - The payoff

    private var headline: some View {
        VStack(spacing: 6) {
            Text(ByteFormat.size(fit.pixelWidth, fit.pixelHeight))
                .font(.hugeNumber)
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(fit.spec.name)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(fit.pixelWidth) by \(fit.pixelHeight) pixels, ready for \(fit.spec.name)"
        )
    }

    private var requirements: some View {
        VStack(spacing: 0) {
            TickRow(
                value: ByteFormat.string(fit.byteCount),
                requirement: sizeRequirement
            )
            TickRow(
                value: "\(fit.spec.output.preferredFilenameExtension?.uppercased() ?? "JPEG"), sRGB",
                requirement: fit.spec.mandatesOutputFormat
                    ? "the only format accepted"
                    : "an accepted format"
            )
            if fit.spec.exif == .stripAll {
                TickRow(value: "Location data removed", requirement: nil)
            }
            if let label = ProvenanceFormat.label(for: fit.spec.source) {
                TickRow(
                    value: label,
                    requirement: nil,
                    muted: true
                )
            }
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private var sizeRequirement: String {
        let band = fit.spec.bytes
        if band.lowerBound == 0 {
            return "under \(ByteFormat.string(band.upperBound))"
        }
        return "between \(ByteFormat.string(band.lowerBound)) and \(ByteFormat.string(band.upperBound))"
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: Metrics.cardSpacing) {
            Button {
                guarded { saveToPhotos() }
            } label: {
                Text("Save to Photos")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button {
                guarded { saveToFiles() }
            } label: {
                Text("Save to Files")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            // ShareLink cannot be intercepted, so when an export is blocked the
            // button is a plain one that opens the paywall instead. Same words,
            // same place; only the destination differs.
            if mayExport {
                ShareLink(item: fit.url) {
                    Text("Share")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .simultaneousGesture(TapGesture().onEnded { onExported() })
            } else {
                Button(action: onBlocked) {
                    Text("Share")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }

    /// Every export goes through here. Blocked ones open the paywall rather
    /// than failing quietly, and nothing is counted until it has landed.
    private func guarded(_ action: () -> Void) {
        guard mayExport else {
            onBlocked()
            return
        }
        action()
    }

    /// Straight into the app's own Documents, which the Files app shows as
    /// On My iPhone → Uploadable. No picker: the answer to "where did it go" should
    /// be the same every time, and the share sheet covers anywhere else.
    private func saveToFiles() {
        do {
            // The engine already named it "<original>-<spec>.jpg".
            _ = try FilesLibrary.save(fit.url, as: fit.url.lastPathComponent)
            saveMessage = "Saved to \(FilesLibrary.userFacingLocation)."
            onExported()
        } catch {
            saveMessage = "Couldn't save to Files. \(error.localizedDescription)"
        }
    }

    private func saveToPhotos() {
        let url = fit.url
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                saveMessage = "Uploadable needs permission to add photos. You can grant it in Settings."
                return
            }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetCreationRequest.forAsset()
                        .addResource(with: .photo, fileURL: url, options: nil)
                }
                saveMessage = "Saved to Photos."
                onExported()
            } catch {
                saveMessage = "Couldn't save to Photos. \(error.localizedDescription)"
            }
        }
    }
}

/// One requirement, met.
private struct TickRow: View {
    let value: String
    let requirement: String?
    var muted = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(muted ? Color.secondary : Color.green)
                .accessibilityHidden(true)
            Text(value)
                .font(.subheadline.weight(muted ? .regular : .medium))
                .foregroundStyle(muted ? .secondary : .primary)
            Spacer(minLength: 6)
            if let requirement {
                Text(requirement)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.horizontal, Metrics.cardPadding)
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }
}

/// A warning. Sits beside the ticks, never instead of them — the file does meet
/// the stated requirements, and Uploadable does not overrule a government about its
/// own form.
private struct NoteRow: View {
    let warning: FitWarning

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(warning.message)
                    .font(.footnote.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = warning.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .multilineTextAlignment(.leading)
        .padding(Metrics.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        )
        .accessibilityElement(children: .combine)
    }
}
