import Foundation

/// Whether this copy of the app is a test build.
///
/// `#if DEBUG` cannot answer this. Archive uses the Release configuration, and
/// — the part that actually settles it — **the TestFlight build and the App
/// Store build are the same binary**. One archive is uploaded, TestFlight serves
/// it to testers, and the identical bits are released. Any compile-time flag
/// that is on for a tester is on for a customer, unless you ship something you
/// never tested, which is worse than the problem it solves.
///
/// So the gate is a runtime one. Apple issues a *sandbox* receipt to builds
/// installed through TestFlight and a production receipt to App Store
/// purchases, and the filename differs. Reading it is local — no network call,
/// which matters for an app whose privacy page says it makes none.
public enum BuildEnvironment {

    /// True in Xcode and simulator builds, and in TestFlight installs.
    ///
    /// Also true under App Review, which runs against a sandbox receipt. That is
    /// deliberate — a reviewer testing the purchase flow is in the same position
    /// as any other tester — and it is the reason anything behind this gate must
    /// be harmless in a stranger's hands, not merely hidden.
    public static var isTestBuild: Bool {
        #if DEBUG
        true
        #else
        isTestBuild(receiptName: Bundle.main.appStoreReceiptURL?.lastPathComponent)
        #endif
    }

    /// True while the screenshot pipeline is driving the app.
    ///
    /// The screenshots are built Debug — they have to be, the harness that
    /// drives them is `#if DEBUG` — so without this the test-build furniture
    /// would appear in a store listing image. An explicit flag rather than
    /// inferring it from `--screen=`, because the UI tests use `--screen=` too
    /// and do need to see the furniture.
    public static var isCapturingScreenshots: Bool {
        ProcessInfo.processInfo.arguments.contains("--for-screenshots")
    }

    /// The decision, separated from `Bundle.main` so it can be tested.
    ///
    /// Fails closed: anything other than an explicit sandbox receipt — including
    /// no receipt at all — is treated as production.
    static func isTestBuild(receiptName: String?) -> Bool {
        receiptName == "sandboxReceipt"
    }
}
