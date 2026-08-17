import Foundation
import StoreKit

/// Uploadable Pro: one payment, forever, no account.
///
/// Non-consumable, so it restores on any device signed into the same Apple
/// Account and cannot lapse. There is no subscription and there will not be one.
@MainActor
@Observable
public final class PurchaseStore {

    public private(set) var product: Product?
    public private(set) var isPro = false
    public private(set) var isWorking = false
    /// Something the user should read, when a purchase or restore did not go
    /// through. Nil the rest of the time.
    public private(set) var message: String?

    private var updates: Task<Void, Never>?

    public init() {}

    /// Stops listening. The listener lives as long as the app does in practice,
    /// so this exists for tests rather than for teardown — `deinit` cannot touch
    /// main-actor state, and reaching for `nonisolated(unsafe)` to work around
    /// that would be trading a compiler complaint for a data race.
    public func stop() {
        updates?.cancel()
        updates = nil
    }

    /// Loads the product and the current entitlement, and starts listening for
    /// transactions that arrive from elsewhere — a purchase made on another
    /// device, or one that finishes after the app was killed.
    public func start() async {
        updates = updates ?? listenForUpdates()
        await refreshEntitlement()
        await loadProduct()
    }

    public var displayPrice: String? { product?.displayPrice }

    // MARK: - Buying

    public func buy() async {
        guard let product else {
            message = "The store isn't available right now. Try again in a moment."
            return
        }
        isWorking = true
        message = nil
        defer { isWorking = false }

        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    message = "That purchase could not be verified."
                    return
                }
                await transaction.finish()
                await refreshEntitlement()
            case .userCancelled:
                break
            case .pending:
                message = "That purchase is waiting for approval. Uploadable will unlock once it goes through."
            @unknown default:
                break
            }
        } catch {
            message = "The purchase didn't go through. \(error.localizedDescription)"
        }
    }

    /// Restore is not optional and never buried: a non-consumable that cannot be
    /// restored is indistinguishable from a purchase that was lost.
    public func restore() async {
        isWorking = true
        message = nil
        defer { isWorking = false }

        try? await AppStore.sync()
        await refreshEntitlement()
        if !isPro {
            message = "No previous purchase found on this Apple Account."
        }
    }

    // MARK: - State

    private func loadProduct() async {
        guard product == nil else { return }
        product = try? await Product.products(for: [BundleConfig.proProductID]).first
    }

    private func refreshEntitlement() async {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == BundleConfig.proProductID,
               transaction.revocationDate == nil {
                isPro = true
                return
            }
        }
        isPro = false
    }

    private func listenForUpdates() -> Task<Void, Never> {
        Task { [weak self] in
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                await transaction.finish()
                await self?.refreshEntitlement()
            }
        }
    }
}
