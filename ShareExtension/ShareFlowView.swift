import SwiftUI
import UploadableKit

/// The compact sheet. Same job as the app, less room to do it in.
///
/// The crop is here for the same reason it is on the Spec screen: centre-crop
/// on a portrait clips the top of the head, and a correct file of the wrong
/// part of the photograph is the failure NOTES.md exists to prevent. Coming in
/// through the share sheet must not quietly produce a worse result than opening
/// the app.
///
/// It fits because the crop is revealed by choosing a destination rather than
/// shown alongside one — the same two-step the app uses. Everything is in one
/// scroll view, so a small phone scrolls rather than truncating.
struct ShareFlowView: View {
    @Bindable var model: ShareModel
    let onShare: (URL) -> Void
    let onClose: () -> Void

    @State private var canExport = true
    @State private var message: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            Group {
                switch model.phase {
                case .loading:
                    centred { ProgressView().controlSize(.large) }

                case .choosing(let photo):
                    choosing(photo)

                case .working(let spec):
                    working(spec)

                case .done(let fit):
                    done(fit)

                case .failed(let message, let remedy):
                    failure(message, remedy)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task { model.load(from: providers) }
        .onDisappear { model.tearDown() }
        .sheet(isPresented: $model.isShowingPaywall) {
            NavigationStack {
                PaywallView(purchases: model.purchases) { model.dismissPaywall() }
            }
        }
    }

    let providers: [NSItemProvider]

    // MARK: - Chrome

    private var header: some View {
        HStack {
            Button("Cancel", action: onClose)
            Spacer()
            Text("Uploadable").font(.headline)
            Spacer()
            // Balances the cancel button so the title sits centred.
            Button("Cancel") {}.opacity(0).disabled(true).accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func centred<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack { Spacer(); content(); Spacer() }
    }

    // MARK: - Choosing

    private func choosing(_ photo: ShareModel.ImportedPhoto) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    if let preview = photo.preview {
                        Image(decorative: preview, scale: 1)
                            .resizable().scaledToFill()
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ByteFormat.size(photo.size.width, photo.size.height))
                            .font(.subheadline.weight(.semibold))
                        Text(ByteFormat.string(photo.facts.byteCount))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)

                if let spec = model.spec, spec.aspect.value != nil, let preview = photo.preview {
                    CropBox(
                        image: preview,
                        imageSize: photo.size,
                        aspect: spec.aspect,
                        crop: $model.crop
                    )
                    .frame(maxHeight: 260)
                    Text("Drag to move, pinch to resize.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                VStack(spacing: 8) {
                    ForEach(SpecCatalog.all) { spec in
                        SpecRow(spec: spec, isSelected: model.spec?.id == spec.id) {
                            model.select(spec)
                        }
                    }
                }

                if model.spec != nil {
                    Button {
                        model.start()
                    } label: {
                        Text("Make it fit")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(16)
        }
    }

    // MARK: - Working

    private func working(_ spec: UploadSpec) -> some View {
        centred {
            VStack(spacing: 14) {
                ProgressView().controlSize(.large)
                Text("Fitting for \(spec.name)")
                    .font(.callout.weight(.medium))
                    .multilineTextAlignment(.center)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(model.steps.enumerated()), id: \.offset) { index, step in
                        HStack(spacing: 8) {
                            Image(systemName: index == model.steps.count - 1
                                  ? "circle.dotted" : "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(index == model.steps.count - 1
                                                 ? Color.secondary : Color.accentColor)
                                .accessibilityHidden(true)
                            Text(step.label).font(.footnote)
                                .foregroundStyle(index == model.steps.count - 1 ? .primary : .secondary)
                            Spacer(minLength: 0)
                        }
                        .frame(height: 24)
                    }
                }
                .padding(.horizontal, 34)
            }
        }
    }

    // MARK: - Done

    private func done(_ fit: Fit) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                Text(ByteFormat.size(fit.pixelWidth, fit.pixelHeight))
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(fit.spec.name)
                    .font(.footnote).foregroundStyle(.secondary)

                VStack(spacing: 0) {
                    ShareTick(value: ByteFormat.string(fit.byteCount),
                              detail: ByteFormat.band(fit.spec.bytes))
                    ShareTick(value: "JPEG, sRGB", detail: nil)
                    ShareTick(value: "Location data removed", detail: nil)
                }
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.secondary.opacity(0.08))
                )

                ForEach(Array(fit.warnings.enumerated()), id: \.offset) { _, warning in
                    Text(warning.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // The same three actions, in the same words, as the app.
                VStack(spacing: 8) {
                    Button {
                        guarded(fit) { message = model.saveToFiles(fit); export(fit) }
                    } label: {
                        Text("Save to Files").font(.headline)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button {
                        guarded(fit) { onShare(fit.url); export(fit) }
                    } label: {
                        Text("Share").font(.headline)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                if let message {
                    Text(message)
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
        }
        .task(id: model.exportsRemaining) { canExport = await model.mayExport(fit) }
        .task(id: model.purchases.isPro) { canExport = await model.mayExport(fit) }
    }

    private func guarded(_ fit: Fit, _ action: () -> Void) {
        guard canExport else {
            model.showPaywall()
            return
        }
        action()
    }

    private func export(_ fit: Fit) {
        Task { await model.recordExport(fit) }
    }

    // MARK: - Failure

    private func failure(_ text: String, _ remedy: String?) -> some View {
        centred {
            VStack(spacing: 10) {
                Text(text)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let remedy {
                    Text(remedy)
                        .font(.footnote).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("Close", action: onClose).padding(.top, 4)
            }
            .padding(.horizontal, 24)
        }
    }
}

private struct ShareTick: View {
    let value: String
    let detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.green)
                .accessibilityHidden(true)
            Text(value).font(.footnote.weight(.medium))
            Spacer(minLength: 4)
            if let detail {
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }
}
