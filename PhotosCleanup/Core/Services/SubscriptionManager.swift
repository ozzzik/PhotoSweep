//
//  SubscriptionManager.swift
//  PhotosCleanup
//
//  StoreKit 2: load products, purchase, restore, observe transactions.
//  Product IDs must match App Store Connect (and PhotosCleanup/Configuration/Products.storekit for local testing).
//

import Foundation
import StoreKit

@MainActor
final class SubscriptionManager: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var hasActiveSubscription = false
    @Published private(set) var purchaseInProgress = false
    @Published var lastErrorMessage: String?
    /// True until the first `loadProducts()` finishes (success or failure).
    @Published private(set) var hasCompletedProductLoad = false
    /// True while a product load request is in flight (starts true until first load finishes).
    @Published private(set) var isLoadingProducts = true

    private var updatesTask: Task<Void, Never>?

    private var productIDs: Set<String> {
        Set([AppConfig.subscriptionMonthlyProductID, AppConfig.subscriptionYearlyProductID])
    }

    init() {
        updatesTask = Task { @MainActor [weak self] in
            await self?.listenForTransactions()
        }
        Task {
            await updateEntitlements()
            await loadProducts()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    /// Sorted: yearly first (best value), then monthly.
    var productsSortedForDisplay: [Product] {
        products.sorted { lhs, rhs in
            if lhs.id == AppConfig.subscriptionYearlyProductID { return true }
            if rhs.id == AppConfig.subscriptionYearlyProductID { return false }
            return lhs.displayName < rhs.displayName
        }
    }

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            await handle(transactionResult: result)
        }
    }

    private func handle(transactionResult: VerificationResult<Transaction>) async {
        switch transactionResult {
        case .verified(let transaction):
            await updateEntitlements()
            await transaction.finish()
        case .unverified:
            break
        }
    }

    func loadProducts() async {
        isLoadingProducts = true
        defer {
            isLoadingProducts = false
            hasCompletedProductLoad = true
        }
        do {
            let loaded = try await Product.products(for: Array(productIDs))
            products = loaded
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func updateEntitlements() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard productIDs.contains(transaction.productID) else { continue }
            if transaction.revocationDate == nil {
                active = true
                break
            }
        }
        if hasActiveSubscription != active {
            hasActiveSubscription = active
        }
    }

    func purchase(_ product: Product) async {
        purchaseInProgress = true
        lastErrorMessage = nil
        defer { purchaseInProgress = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await updateEntitlements()
                    await transaction.finish()
                case .unverified:
                    lastErrorMessage = "Purchase could not be verified."
                }
            case .userCancelled:
                break
            case .pending:
                lastErrorMessage = "Purchase is pending approval."
            @unknown default:
                break
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func restorePurchases() async {
        lastErrorMessage = nil
        do {
            try await AppStore.sync()
            await updateEntitlements()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func clearLastError() {
        lastErrorMessage = nil
    }
}
