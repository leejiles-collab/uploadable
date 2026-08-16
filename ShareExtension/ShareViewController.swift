import UIKit
import SwiftUI
import FitsKit

/// PHASE 0 PLACEHOLDER. The real sheet arrives in phase 3.
///
/// The shape is already the one Smaller ended up with, because the reasons for
/// it were expensive: a plain UIKit view is installed first and the SwiftUI
/// host is layered over it opaque, so a run where SwiftUI never draws leaves
/// something readable on screen rather than a blank white sheet.
final class ShareViewController: UIViewController {

    private let fallback = FallbackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        pin(fallback, to: view)

        let host = UIHostingController(rootView: ScaffoldSheet(
            onCancel: { [weak self] in self?.cancel() }
        ))
        host.view.backgroundColor = .systemBackground
        addChild(host)
        pin(host.view, to: view)
        host.didMove(toParent: self)
    }

    private func cancel() {
        extensionContext?.cancelRequest(withError: NSError(
            domain: NSCocoaErrorDomain, code: NSUserCancelledError
        ))
    }

    private func pin(_ child: UIView, to parent: UIView) {
        child.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(child)
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            child.topAnchor.constraint(equalTo: parent.topAnchor),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor)
        ])
    }
}

private struct ScaffoldSheet: View {
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("Fits").font(.headline)
            Text("Engine ready · \(SpecCatalog.all.count) specs")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Close", action: onCancel).padding(.top, 8)
        }
        .padding()
    }
}

/// The floor. Whatever else happens, the sheet is never empty.
private final class FallbackView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemBackground
        let label = UILabel()
        label.text = "Fits couldn't start.\nOpen the photo in the Fits app instead."
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 32),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -32)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }
}
