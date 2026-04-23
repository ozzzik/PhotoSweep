//
//  SettingsView.swift
//  PhotosCleanup
//
//  Cleanup options, Analysis & privacy, Ads, Premium, Rate us, About.
//

import StoreKit
import SwiftUI

struct SettingsView: View {
    @AppStorage("protectFavorites") private var protectFavorites = true
    @AppStorage("includeScreenshots") private var includeScreenshots = true
    @AppStorage("includeVideos") private var includeVideos = false
    @AppStorage("advancedOnDeviceAnalysis") private var advancedAnalysis = true
    @AppStorage("personalizedAds") private var personalizedAds = false

    @Environment(\.requestReview) private var requestReview
    @EnvironmentObject private var reviewManager: AppReviewManager
    @ObservedObject var adManager: AdManager
    @ObservedObject var subscriptionManager: SubscriptionManager
    @ObservedObject var lastSmartScanResult: LastSmartScanResult

    @State private var showSubscriptionError = false

    var body: some View {
        List {
            Section("Cleanup options") {
                Toggle("Protect Favorites", isOn: $protectFavorites)
                Toggle("Include screenshots", isOn: $includeScreenshots)
                Toggle("Include videos", isOn: $includeVideos)
            }
            Section("Analysis & privacy") {
                Toggle("Use advanced on-device analysis", isOn: $advancedAnalysis)
                Link("Privacy Policy", destination: URL(string: "https://example.com/privacy")!)
                Text("We never upload your photos. Analysis runs on your device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("PhotoSweep Premium") {
                if adManager.isPremium {
                    Label("Premium active", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.accent)
                    Text("Thank you! Premium keeps scan results saved across launches, remembers which photos you’ve already reviewed (“Seen before”), unlocks full scan scopes, and removes ads.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        lastSmartScanResult.clearPremiumScreeningHistory()
                    } label: {
                        Label("Clear “Seen before” history", systemImage: "eye.slash")
                    }
                } else {
                    Text("Premium removes ads, unlocks Specific dates and All photos, and keeps scan progress across launches. By year stays free.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !subscriptionManager.hasCompletedProductLoad || subscriptionManager.isLoadingProducts {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 8)
                        Text("Loading subscription options…")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } else if subscriptionManager.products.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Couldn’t load subscription options.")
                                .font(.subheadline)
                            Text("In Xcode: Product → Scheme → Edit Scheme → Run → Options → StoreKit Configuration → choose Products.storekit. For TestFlight/App Store, subscriptions must exist in App Store Connect for this bundle ID.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button {
                                Task { await subscriptionManager.loadProducts() }
                            } label: {
                                Label("Try again", systemImage: "arrow.clockwise")
                            }
                        }
                        .padding(.vertical, 4)
                    } else {
                        ForEach(subscriptionManager.productsSortedForDisplay, id: \.id) { product in
                            Button {
                                Task { await subscriptionManager.purchase(product) }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(product.displayName)
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        if let subscription = product.subscription {
                                            Text(subscription.subscriptionPeriod.periodTitle)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Text(product.displayPrice)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(AppTheme.accent)
                                }
                            }
                            .disabled(subscriptionManager.purchaseInProgress)
                        }
                    }

                    Button {
                        Task { await subscriptionManager.restorePurchases() }
                    } label: {
                        Label("Restore purchases", systemImage: "arrow.clockwise")
                    }
                    .disabled(subscriptionManager.purchaseInProgress)
                }

                #if DEBUG
                Group {
                    Text("Developer")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    if adManager.isPremium, !subscriptionManager.hasActiveSubscription {
                        Button(role: .destructive) {
                            adManager.setDebugPremium(false)
                        } label: {
                            Label("Clear debug premium override", systemImage: "xmark.circle.fill")
                        }
                    } else if !adManager.isPremium {
                        Button {
                            adManager.setDebugPremium(true)
                        } label: {
                            Label("Debug: grant premium (local)", systemImage: "crown.fill")
                        }
                    }
                    Button {
                        adManager.resetInterstitialFrequencyLimitsForTesting()
                    } label: {
                        Label("Debug: reset group-screening ad counter", systemImage: "arrow.counterclockwise.circle")
                    }
                }
                #endif
            }
            Section("Ads") {
                Toggle("Personalized ads", isOn: $personalizedAds)
                    .disabled(adManager.isPremium)
                Link("Why am I seeing ads?", destination: URL(string: "https://example.com/ads")!)
            }
            Section("Support") {
                Button {
                    requestReview()
                    reviewManager.markReviewRequested()
                } label: {
                    Label("Rate PhotoSweep", systemImage: "star.fill")
                }
            }
            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
        .task {
            await subscriptionManager.loadProducts()
        }
        .onChange(of: subscriptionManager.lastErrorMessage) { _, new in
            showSubscriptionError = new != nil
        }
        .alert("Subscription", isPresented: $showSubscriptionError) {
            Button("OK", role: .cancel) {
                subscriptionManager.clearLastError()
            }
        } message: {
            Text(subscriptionManager.lastErrorMessage ?? "")
        }
    }
}

private extension Product.SubscriptionPeriod {
    var periodTitle: String {
        let n = value
        switch unit {
        case .day: return n == 1 ? "Renews every day" : "Renews every \(n) days"
        case .week: return n == 1 ? "Renews every week" : "Renews every \(n) weeks"
        case .month: return n == 1 ? "Renews every month" : "Renews every \(n) months"
        case .year: return n == 1 ? "Renews every year" : "Renews every \(n) years"
        @unknown default: return "Subscription"
        }
    }
}

#Preview {
    let sub = SubscriptionManager()
    let ad = AdManager(subscriptionManager: sub)
    NavigationStack {
        SettingsView(
            adManager: ad,
            subscriptionManager: sub,
            lastSmartScanResult: LastSmartScanResult(adManager: ad)
        )
        .environmentObject(AppReviewManager())
    }
}
