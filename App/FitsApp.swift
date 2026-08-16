import SwiftUI
import FitsKit

@main
struct FitsApp: App {
    var body: some Scene {
        WindowGroup {
            ScaffoldView()
        }
    }
}

/// PHASE 0 PLACEHOLDER. The four screens land in phase 2, once the engine
/// numbers have been looked at against real photographs. It exists so the
/// target builds and signs; nothing here is the product.
struct ScaffoldView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Fits")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text("Engine ready · \(SpecCatalog.all.count) specs")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("\(SpecCatalog.all.filter(\.source.isVerified).count) verified against their official pages")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
