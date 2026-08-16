import SwiftUI
import FitsKit

/// Why it cannot be done, and what would fix it.
///
/// Never a file the portal will reject dressed up as a success. Every failure
/// the engine raises carries the numbers, so this screen states them rather than
/// apologising in general terms — "this photo is 400 × 400, the form needs at
/// least 600 × 600" is something a person can act on.
struct FailureView: View {
    let failure: FitFailure
    let spec: UploadSpec?
    let onChooseAgain: () -> Void
    let onStartOver: () -> Void

    var body: some View {
        VStack(spacing: Metrics.stackSpacing) {
            Spacer()

            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(spacing: 10) {
                Text(failure.message)
                    .font(.title3.weight(.medium))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if let remedy = failure.remedy {
                    Text(remedy)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)

            Spacer()

            VStack(spacing: Metrics.cardSpacing) {
                if spec != nil {
                    Button {
                        onChooseAgain()
                    } label: {
                        Text("Try another destination")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                Button("Choose a different photo", action: onStartOver)
                    .font(.callout)
            }

            Spacer().frame(height: 20)
        }
        .padding(.horizontal, Metrics.screenPadding)
        .frame(maxWidth: Metrics.contentWidth)
        .frame(maxWidth: .infinity)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close", action: onStartOver)
            }
        }
    }
}
