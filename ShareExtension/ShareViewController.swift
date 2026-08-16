import UIKit
import SwiftUI
import FitsKit

/// Hosts the sheet.
///
/// The shape is Smaller's, because the reasons for it were expensive. A plain
/// UIKit view is installed first and the SwiftUI host is layered over it
/// opaque, so a run where SwiftUI never draws leaves something readable rather
/// than a blank white sheet — and a watchdog reveals it if the host attaches
/// and then draws nothing.
final class ShareViewController: UIViewController {

    private static let firstFrameDeadline: Duration = .seconds(3)

    private let fallback = FallbackView()
    private let model = ShareModel()
    private var hasDrawn = false
    private var watchdog: Task<Void, Never>?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        fallback.onClose = { [weak self] in self?.cancel() }
        pin(fallback, to: view)

        let providers = (extensionContext?.inputItems as? [NSExtensionItem])?
            .compactMap(\.attachments)
            .flatMap { $0 } ?? []

        let flow = ShareFlowView(
            model: model,
            onShare: { [weak self] url in self?.share(url) },
            onClose: { [weak self] in self?.cancel() },
            providers: providers
        )
        .onAppear { [weak self] in self?.noteDrawn() }

        let host = UIHostingController(rootView: flow)
        host.view.backgroundColor = .systemBackground
        addChild(host)
        pin(host.view, to: view)
        host.didMove(toParent: self)

        startWatchdog()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        watchdog?.cancel()
    }

    // MARK: - Leaving

    private func cancel() {
        extensionContext?.cancelRequest(withError: NSError(
            domain: NSCocoaErrorDomain, code: NSUserCancelledError
        ))
    }

    /// Opens the system share sheet on the finished file.
    ///
    /// Presented from UIKit rather than SwiftUI's `ShareLink`: inside an
    /// extension the presentation has to come from the view controller the host
    /// installed. Nothing is handed back to the host — a share extension is
    /// terminal, and most hosts discard returned items.
    private func share(_ url: URL) {
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = view
        sheet.popoverPresentationController?.sourceRect = CGRect(
            x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1
        )
        sheet.completionWithItemsHandler = { [weak self] _, completed, _, _ in
            guard completed else { return }
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
        present(sheet, animated: true)
    }

    // MARK: - Making sure something is on screen

    private func noteDrawn() {
        hasDrawn = true
        watchdog?.cancel()
        watchdog = nil
    }

    private func startWatchdog() {
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: Self.firstFrameDeadline)
            guard !Task.isCancelled, let self, !self.hasDrawn else { return }
            self.fallback.show(
                message: "Fits couldn't open here.",
                detail: "Open the photo in the Fits app instead — it can do everything this sheet can."
            )
            self.view.bringSubviewToFront(self.fallback)
        }
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

/// The floor under everything. Built from nothing but UIKit primitives: it is
/// what has to work when the interesting parts did not.
private final class FallbackView: UIView {

    var onClose: (() -> Void)?

    private let title = UILabel()
    private let detail = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemBackground

        title.text = "Fits couldn't start."
        title.font = .preferredFont(forTextStyle: .headline)
        detail.text = "Close this and open the photo in the Fits app instead."
        detail.font = .preferredFont(forTextStyle: .subheadline)
        detail.textColor = .secondaryLabel

        for label in [title, detail] {
            label.numberOfLines = 0
            label.textAlignment = .center
            label.adjustsFontForContentSizeCategory = true
        }

        var configuration = UIButton.Configuration.borderedProminent()
        configuration.title = "Close"
        let close = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
            self?.onClose?()
        })

        let stack = UIStackView(arrangedSubviews: [title, detail, close])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.setCustomSpacing(20, after: detail)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -32)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func show(message: String, detail: String) {
        title.text = message
        self.detail.text = detail
    }
}
