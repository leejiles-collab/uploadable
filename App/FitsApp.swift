import SwiftUI
import FitsKit

@main
struct FitsApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// One screen at a time, chosen by what the engine is doing.
struct RootView: View {
    @State private var store = FitsStore()

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.easeInOut(duration: 0.2), value: phaseID)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .home:
            HomeView(
                onPicked: { data, name in store.open(data: data, suggestedName: name) },
                onFailed: { store.failedToPick() }
            )

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
            DoneView(fit: fit, onStartOver: { store.startOver() })

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
