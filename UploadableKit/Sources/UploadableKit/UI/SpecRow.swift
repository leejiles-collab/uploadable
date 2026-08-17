import SwiftUI

/// One destination. The verification date is on the row rather than buried,
/// because a preset nobody has checked recently is worth noticing before you
/// rely on it.
public struct SpecRow: View {
    let spec: UploadSpec
    let isSelected: Bool
    var subtitleOverride: String?
    let action: () -> Void

    public init(spec: UploadSpec, isSelected: Bool, subtitleOverride: String? = nil,
                action: @escaping () -> Void) {
        self.spec = spec
        self.isSelected = isSelected
        self.subtitleOverride = subtitleOverride
        self.action = action
    }

    public var body: some View {
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
