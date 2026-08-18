import SwiftUI
import UploadableKit

@main
struct UploadableApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// One screen at a time, chosen by what the engine is doing.
struct RootView: View {
    @State private var store = UploadableStore()
    /// Recomputed whenever the allowance or the entitlement changes, so buying
    /// Pro unlocks the buttons behind the paywall without another round trip.
    @State private var canExport = true

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.easeInOut(duration: 0.2), value: phaseID)
        }
        .task {
            #if DEBUG
            if await ScreenshotHarness.run(store: store) { return }
            #endif
            // Before anything else: file whatever the share extension saved
            // while the app was not running. It cannot reach the Files folder
            // from its own sandbox, so this is the moment its work shows up.
            store.adoptExtensionOutput()
            await store.refreshEntitlements()
        }
        .sheet(isPresented: Binding(
            get: { store.isShowingPaywall },
            set: { if !$0 { store.dismissPaywall() } }
        )) {
            NavigationStack {
                PaywallView(purchases: store.purchases) { store.dismissPaywall() }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .home:
            HomeView(
                onPicked: { data, name in store.open(data: data, suggestedName: name) },
                onFailed: { store.failedToPick() },
                onResetExports: { Task { await store.resetExportsForTesting() } },
                exportsRemaining: store.exportsRemaining
            )
            // The meter is read on the way in, so returning Home after spending
            // an export shows the truth rather than a stale number.
            .task { await store.refreshEntitlements() }

        case .choosing(let photo):
            SpecView(
                photo: photo,
                selected: Binding(get: { store.spec }, set: { store.spec = $0 }),
                crop: Binding(get: { store.crop }, set: { store.crop = $0 }),
                customWidth: Binding(get: { store.customWidth }, set: { store.customWidth = $0 }),
                customHeight: Binding(get: { store.customHeight }, set: { store.customHeight = $0 }),
                customMinKB: Binding(get: { store.customMinKB }, set: { store.customMinKB = $0 }),
                customMaxKB: Binding(get: { store.customMaxKB }, set: { store.customMaxKB = $0 }),
                customSpec: store.customSpec,
                onSelect: { store.select($0) },
                onStart: { store.start() },
                onClose: { store.startOver() }
            )

        case .working(_, let spec):
            WorkingView(
                spec: spec,
                steps: store.steps,
                onCancel: { store.cancelWork() }
            )

        case .done(let fit):
            DoneView(
                fit: fit,
                mayExport: canExport,
                onExported: { Task { await store.recordExport(fit) } },
                onBlocked: { store.showPaywall() },
                onStartOver: { store.startOver() }
            )
            .task(id: store.exportsRemaining) { canExport = await store.mayExport(fit) }
            .task(id: store.purchases.isPro) { canExport = await store.mayExport(fit) }

        case .failed(let failure, let spec):
            FailureView(
                failure: failure,
                spec: spec,
                onChooseAgain: { store.chooseAgain() },
                onStartOver: { store.startOver() }
            )
        }
    }

    /// Animate between screens, not on every step the engine reports.
    private var phaseID: String {
        switch store.phase {
        case .home: "home"
        case .choosing: "choosing"
        case .working: "working"
        case .done: "done"
        case .failed: "failed"
        }
    }
}
