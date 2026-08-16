import SwiftUI
import FitsKit

/// Brief, but real.
///
/// Every line here is a step the engine actually reported as it happened. That
/// matters more than it looks: converting to sRGB and searching for the right
/// quality *are* the product, and a spinner would hide the only interesting
/// thing the app does. Nothing on this screen is on a timer.
struct WorkingView: View {
    let spec: UploadSpec
    let steps: [FitStep]
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: Metrics.stackSpacing) {
            Spacer()

            ProgressView()
                .controlSize(.large)

            Text("Fitting for \(spec.name)")
                .font(.title3.weight(.medium))
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(spacing: 9) {
                        Image(systemName: index == steps.count - 1
                              ? "circle.dotted" : "checkmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(index == steps.count - 1
                                             ? Color.secondary : Color.accentColor)
                            .accessibilityHidden(true)
                        Text(step.label)
                            .font(.callout)
                            .foregroundStyle(index == steps.count - 1 ? .primary : .secondary)
                        Spacer(minLength: 0)
                    }
                    // A fixed height, and no transition. Animating rows in made
                    // them slide over one another while the list grew, which
                    // reads as a broken screen rather than a lively one.
                    .frame(height: 30)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 30)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(steps.last?.label ?? "Working")

            Spacer()
        }
        .padding(.horizontal, Metrics.screenPadding)
        .frame(maxWidth: Metrics.contentWidth)
        .frame(maxWidth: .infinity)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel", role: .cancel, action: onCancel)
            }
        }
    }
}
