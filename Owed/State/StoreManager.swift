import Foundation
import Observation
import StoreKit

/// StoreKit 2 wrapper for the single $5.99 non-consumable.
///
/// Deliberate call: no RevenueCat. For one non-consumable, StoreKit 2 gives
/// on-device receipt validation (`VerificationResult`), `Transaction.updates`
/// for Ask-to-Buy/refunds, and `AppStore.sync()` for restore — a dependency
/// would add an SDK, a dashboard, and a privacy-manifest entry to replace
/// ~80 lines. Revisit only if the backend needs server-side entitlements.
///
/// `@MainActor` matches `AppModel`: entitlement flags are observed by views
/// and must never race the UI isolation domain.
@Observable @MainActor
final class StoreManager {
    static let lifetimeID = "AvaResearchLLC.Owed.lifetime"

    private(set) var product: Product?
    private(set) var owned = false
    private(set) var purchasing = false
    private(set) var loadFailed = false

    var displayPrice: String { product?.displayPrice ?? "$5.99" }

    init() {
        // Process-lifetime listener; StoreManager outlives UI so no deinit cancel.
        Task { [weak self] in
            // Ask-to-Buy approvals, refunds, family-share revocation.
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
        Task { await bootstrap() }
    }

    private func bootstrap() async {
        await refreshEntitlement()
        do {
            product = try await Product.products(for: [Self.lifetimeID]).first
            loadFailed = product == nil
        } catch {
            loadFailed = true
        }
    }

    func purchase() async {
        guard let product, !purchasing else { return }
        purchasing = true
        defer { purchasing = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                await handle(verification)
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            // Surface nothing scary; the paywall stays up and the user can retry.
        }
    }

    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlement()
    }

    private func handle(_ verification: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = verification else { return }
        if transaction.productID == Self.lifetimeID {
            owned = transaction.revocationDate == nil
        }
        await transaction.finish()
    }

    private func refreshEntitlement() async {
        // Recompute from scratch so a refund/revocation discovered on
        // restore clears the flag instead of leaving it stuck on.
        var found = false
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let t) = entitlement,
               t.productID == Self.lifetimeID, t.revocationDate == nil {
                found = true
            }
        }
        owned = found
    }
}
