import SwiftUI

/// Shown at one moment only: an export the free allowance will not cover.
///
/// Never on launch, never after a fit. Fitting is free and unlimited, and the
/// Done screen with its column of ticks is the reason to pay — putting a wall
/// in front of that would hide the argument.
///
/// One sentence on what it is, the price, a way to buy it, a way to restore it,
/// and a way out. No timer, no crossed-out price, no "3 people are viewing".
public struct PaywallView: View {
    let purchases: PurchaseStore
    let onClose: () -> Void

    public init(purchases: PurchaseStore, onClose: @escaping () -> Void) {
        self.purchases = purchases
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: Metrics.stackSpacing) {
            Spacer()

            VStack(spacing: 10) {
                Text("Uploadable Pro")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                Text("Save and share as many photos as you like.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            Text("You've used your \(Config.freeExports) free exports. Fitting photos stays free and unlimited.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let message = purchases.message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    Task { await purchases.buy() }
                } label: {
                    Group {
                        if purchases.isWorking {
                            ProgressView()
                        } else {
                            Text(purchases.displayPrice.map { "Get Uploadable Pro — \($0)" } ?? "Get Uploadable Pro")
                                .font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(purchases.isWorking)

                Text("One payment, forever. No subscription, no account.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button("Restore Purchases") {
                    Task { await purchases.restore() }
                }
                .font(.callout)
                .disabled(purchases.isWorking)
            }

            Spacer().frame(height: 16)
        }
        .padding(.horizontal, Metrics.screenPadding)
        .frame(maxWidth: Metrics.contentWidth)
        .frame(maxWidth: .infinity)
        // The kit builds for macOS as well, because that is where the tests
        // run; `topBarLeading` does not exist there.
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close", action: onClose)
            }
        }
        #endif
        .onChange(of: purchases.isPro) { _, isPro in
            // Bought or restored: get out of the way immediately.
            if isPro { onClose() }
        }
    }
}
