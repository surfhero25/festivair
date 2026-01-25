import Foundation
import StoreKit

/// Manages in-app subscriptions using StoreKit 2
@MainActor
final class SubscriptionManager: ObservableObject {

    // MARK: - Singleton
    static let shared = SubscriptionManager()

    // MARK: - Published State
    @Published private(set) var currentTier: PremiumTier = .free
    @Published private(set) var availableProducts: [Product] = []
    @Published private(set) var purchasedProductIDs: Set<String> = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    // MARK: - Product IDs
    enum ProductID: String, CaseIterable {
        case basicMonthly = "com.festivair.basic.monthly"
        case basicYearly = "com.festivair.basic.yearly"
        case vipMonthly = "com.festivair.vip.monthly"
        case vipYearly = "com.festivair.vip.yearly"

        var tier: PremiumTier {
            switch self {
            case .basicMonthly, .basicYearly: return .basic
            case .vipMonthly, .vipYearly: return .vip
            }
        }

        var isYearly: Bool {
            switch self {
            case .basicYearly, .vipYearly: return true
            default: return false
            }
        }
    }

    // MARK: - Private
    private var updateListenerTask: Task<Void, Error>?

    // MARK: - Init
    private init() {
        // Start listening for transaction updates
        updateListenerTask = listenForTransactions()

        // Load products and check entitlements
        Task {
            await loadProducts()
            await updatePurchasedProducts()
        }
    }

    deinit {
        updateListenerTask?.cancel()
    }

    // MARK: - Public API

    /// Load available products from App Store
    func loadProducts() async {
        isLoading = true
        errorMessage = nil

        do {
            let productIDs = ProductID.allCases.map { $0.rawValue }
            let products = try await Product.products(for: productIDs)
            availableProducts = products.sorted { $0.price < $1.price }
        } catch {
            errorMessage = "Failed to load products: \(error.localizedDescription)"
            print("[Subscription] Failed to load products: \(error)")
        }

        isLoading = false
    }

    /// Purchase a product
    func purchase(_ product: Product) async throws -> Transaction? {
        isLoading = true
        errorMessage = nil

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await updatePurchasedProducts()
                isLoading = false
                return transaction

            case .userCancelled:
                isLoading = false
                return nil

            case .pending:
                isLoading = false
                errorMessage = "Purchase pending approval"
                return nil

            @unknown default:
                isLoading = false
                return nil
            }
        } catch {
            isLoading = false
            errorMessage = "Purchase failed: \(error.localizedDescription)"
            throw error
        }
    }

    /// Restore purchases
    func restorePurchases() async {
        isLoading = true
        errorMessage = nil

        do {
            try await AppStore.sync()
            await updatePurchasedProducts()
        } catch {
            errorMessage = "Restore failed: \(error.localizedDescription)"
        }

        isLoading = false
    }

    /// Check if user has a specific tier or higher
    func hasAccess(to tier: PremiumTier) -> Bool {
        switch tier {
        case .free: return true
        case .basic: return currentTier == .basic || currentTier == .vip
        case .vip: return currentTier == .vip
        }
    }

    /// Get the squad member limit for current tier
    var squadLimit: Int {
        currentTier.squadLimit
    }

    /// Check if user can host exclusive parties (VIP only)
    var canHostExclusiveParties: Bool {
        currentTier == .vip
    }

    /// Check if user can upload gallery photos (Basic+)
    var canUploadGallery: Bool {
        currentTier != .free
    }

    /// Check if user can create parties (Basic+ for open, VIP for exclusive)
    func canCreateParty(accessType: String) -> Bool {
        switch accessType {
        case "open": return currentTier != .free
        case "approval", "inviteOnly": return currentTier == .vip
        default: return false
        }
    }

    // MARK: - Product Helpers

    func product(for productID: ProductID) -> Product? {
        availableProducts.first { $0.id == productID.rawValue }
    }

    func basicProducts() -> [Product] {
        availableProducts.filter {
            $0.id == ProductID.basicMonthly.rawValue ||
            $0.id == ProductID.basicYearly.rawValue
        }
    }

    func vipProducts() -> [Product] {
        availableProducts.filter {
            $0.id == ProductID.vipMonthly.rawValue ||
            $0.id == ProductID.vipYearly.rawValue
        }
    }

    // MARK: - Private Helpers

    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached {
            for await result in Transaction.updates {
                do {
                    let transaction = try await self.checkVerified(result)
                    await self.updatePurchasedProducts()
                    await transaction.finish()
                } catch {
                    print("[Subscription] Transaction verification failed: \(error)")
                }
            }
        }
    }

    private func updatePurchasedProducts() async {
        var purchased: Set<String> = []
        var highestTier: PremiumTier = .free

        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)

                if transaction.revocationDate == nil {
                    purchased.insert(transaction.productID)

                    // Determine tier from product ID
                    if let productID = ProductID(rawValue: transaction.productID) {
                        if productID.tier.rawValue > highestTier.rawValue {
                            highestTier = productID.tier
                        }
                    }
                }
            } catch {
                print("[Subscription] Failed to verify transaction: \(error)")
            }
        }

        purchasedProductIDs = purchased
        currentTier = highestTier

        // Also update UserDefaults for offline access
        UserDefaults.standard.set(currentTier.rawValue, forKey: "FestivAir.PremiumTier")
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw SubscriptionError.verificationFailed
        case .verified(let safe):
            return safe
        }
    }
}

// MARK: - Errors

enum SubscriptionError: LocalizedError {
    case verificationFailed
    case purchaseFailed
    case productNotFound

    var errorDescription: String? {
        switch self {
        case .verificationFailed: return "Transaction verification failed"
        case .purchaseFailed: return "Purchase could not be completed"
        case .productNotFound: return "Product not found"
        }
    }
}

// MARK: - PremiumTier Comparable Extension

extension PremiumTier: Comparable {
    static func < (lhs: PremiumTier, rhs: PremiumTier) -> Bool {
        let order: [PremiumTier] = [.free, .basic, .vip]
        guard let lhsIndex = order.firstIndex(of: lhs),
              let rhsIndex = order.firstIndex(of: rhs) else {
            return false
        }
        return lhsIndex < rhsIndex
    }
}
