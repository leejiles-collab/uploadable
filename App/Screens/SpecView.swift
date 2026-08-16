import SwiftUI
import FitsKit

/// Where is this going, and which part of the photo is going there.
///
/// The two questions belong together: the crop only makes sense once a shape is
/// chosen, so picking a destination is what reveals it.
struct SpecView: View {
    let photo: ImportedPhoto
    @Binding var selected: UploadSpec?
    @Binding var crop: CropRect
    @Binding var customWidth: String
    @Binding var customHeight: String
    @Binding var customMinKB: String
    @Binding var customMaxKB: String
    let customSpec: UploadSpec
    let onSelect: (UploadSpec) -> Void
    let onStart: () -> Void
    let onClose: () -> Void

    @State private var search = ""
    @State private var showingCustom = false

    private var matches: [UploadSpec] {
        guard !search.isEmpty else { return SpecCatalog.all }
        return SpecCatalog.all.filter {
            $0.name.localizedCaseInsensitiveContains(search)
                || $0.issuer.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.stackSpacing) {
                photoHeader

                if let selected, selected.aspect.value != nil, let preview = photo.preview {
                    cropSection(preview: preview, spec: selected)
                }

                searchField

                VStack(spacing: Metrics.cardSpacing) {
                    ForEach(matches) { spec in
                        SpecRow(spec: spec, isSelected: selected?.id == spec.id) {
                            showingCustom = false
                            onSelect(spec)
                        }
                    }
                    customRow
                }

                if selected != nil {
                    Button(action: onStart) {
                        Text("Make it fit")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.top, Metrics.stackSpacing)
            .padding(.bottom, Metrics.stackSpacing)
            .frame(maxWidth: Metrics.contentWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close", action: onClose)
            }
        }
    }

    /// Inline rather than `.searchable`.
    ///
    /// The system search field floats over the bottom of the scroll view and
    /// will not move: with seven destinations it permanently covers one of
    /// them, which reads as a broken layout even though the list does scroll
    /// underneath. A field in the content costs nothing and stays where it is
    /// put.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search destinations", text: $search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.secondary.opacity(0.10))
        )
    }

    // MARK: - The photo

    private var photoHeader: some View {
        HStack(spacing: 14) {
            if let preview = photo.preview {
                Image(decorative: preview, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(ByteFormat.size(photo.size.width, photo.size.height))
                    .font(.headline)
                Text(ByteFormat.string(photo.facts.byteCount))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - The crop

    @ViewBuilder
    private func cropSection(preview: CGImage, spec: UploadSpec) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            CropBox(
                image: preview,
                imageSize: photo.size,
                aspect: spec.aspect,
                crop: $crop
            )
            .frame(maxHeight: 340)

            Text("Drag to move, pinch to resize. \(spec.aspect.label) for \(spec.name).")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Custom

    private var customRow: some View {
        VStack(alignment: .leading, spacing: Metrics.cardSpacing) {
            SpecRow(
                spec: customSpec,
                isSelected: showingCustom,
                subtitleOverride: "Type the numbers your form asks for"
            ) {
                showingCustom = true
                onSelect(customSpec)
            }

            if showingCustom {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        NumberField(title: "Width", text: $customWidth, unit: "px")
                        NumberField(title: "Height", text: $customHeight, unit: "px")
                    }
                    HStack(spacing: 10) {
                        NumberField(title: "Min size", text: $customMinKB, unit: "KB")
                        NumberField(title: "Max size", text: $customMaxKB, unit: "KB")
                    }
                }
                .padding(.horizontal, 4)
                .onChange(of: customWidth) { _, _ in onSelect(customSpec) }
                .onChange(of: customHeight) { _, _ in onSelect(customSpec) }
                .onChange(of: customMinKB) { _, _ in onSelect(customSpec) }
                .onChange(of: customMaxKB) { _, _ in onSelect(customSpec) }
            }
        }
    }
}

/// One destination. The verification date is on the row rather than buried,
/// because a preset nobody has checked recently is worth noticing before you
/// rely on it.
struct SpecRow: View {
    let spec: UploadSpec
    let isSelected: Bool
    var subtitleOverride: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.4))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(spec.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitleOverride ?? spec.requirementSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                    if let label = ProvenanceFormat.label(for: spec.source) {
                        Text(label)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(Metrics.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

}

private struct NumberField: View {
    let title: String
    @Binding var text: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                TextField("0", text: $text)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) in \(unit)")
    }
}
