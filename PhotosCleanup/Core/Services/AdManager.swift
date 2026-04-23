//
//  AdManager.swift
//  PhotosCleanup
//
//  Banner + interstitial: see `AppConfig` / `InterstitialAdWaterfall` for network order.
//  Premium = active StoreKit subscription OR (DEBUG) local override.
//

import Combine
import Foundation
#if DEBUG
import os.log
#endif

private enum AdDefaults {
    static let groupScreeningsCompletedTotal = "adManager.groupScreeningsCompletedTotal"
    static let isPremium = "adManager.isPremium"
    static let debugPremiumOverride = "adManager.debugPremiumOverride"
}

#if DEBUG
private let adDebugLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PhotosCleanup", category: "Ads")
#endif

@MainActor
final class AdManager: ObservableObject {
    private let subscriptionManager: SubscriptionManager
    private weak var analyticsService: AnalyticsService?
    private var cancellables = Set<AnyCancellable>()

    private let interstitialWaterfall = InterstitialAdWaterfall()

    /// DEBUG / review builds: local “pretend premium” without App Store (stored in UserDefaults).
    @Published var debugPremiumOverride: Bool {
        didSet {
            defaults.set(debugPremiumOverride, forKey: AdDefaults.debugPremiumOverride)
        }
    }

    /// True when the user has premium: active subscription or debug override.
    var isPremium: Bool {
        subscriptionManager.hasActiveSubscription || debugPremiumOverride
    }

    private let defaults = UserDefaults.standard

    init(subscriptionManager: SubscriptionManager, analyticsService: AnalyticsService? = nil) {
        self.subscriptionManager = subscriptionManager
        self.analyticsService = analyticsService
        var debug = defaults.bool(forKey: AdDefaults.debugPremiumOverride)
        if defaults.bool(forKey: AdDefaults.isPremium) {
            debug = true
            defaults.set(false, forKey: AdDefaults.isPremium)
        }
        defaults.set(debug, forKey: AdDefaults.debugPremiumOverride)
        self.debugPremiumOverride = debug
        subscriptionManager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        interstitialWaterfall.onInterstitialPresented = { [weak self] network in
            self?.analyticsService?.trackAdShown(type: "interstitial_\(network)")
        }
        interstitialWaterfall.onInterstitialFinished = { [weak self] in
            self?.handleInterstitialFinished()
        }
    }

    #if DEBUG
    func setDebugPremium(_ value: Bool) {
        debugPremiumOverride = value
    }

    /// Clears the group-screening counter (UserDefaults). Optional when testing the “every N groups” interstitial.
    func resetInterstitialFrequencyLimitsForTesting() {
        defaults.removeObject(forKey: AdDefaults.groupScreeningsCompletedTotal)
        adDebugLog.debug("Reset group screening interstitial counter for testing")
    }
    #endif

    /// Call once after onboarding + photo permission (e.g. from RootView). Initializes Unity + preloads AdMob.
    func prepareAds() {
        guard !isPremium else { return }
        interstitialWaterfall.bootstrap()
    }

    /// Banner: home and results list bottom. Real banners load in `BannerAdWaterfallView` when `prepareAds` has run.
    func loadBanner() {
        prepareAds()
    }

    /// Interstitial: preload both networks (AdMob first when showing — see `InterstitialAdWaterfall`).
    func preloadInterstitial() {
        prepareAds()
    }

    /// Call after the user leaves a duplicate or similar **group detail** screen (`onMarkReviewed`). Every `AppConfig.groupScreeningsPerInterstitial` visits (non‑premium) tries an interstitial.
    func recordGroupScreening() {
        guard !isPremium else { return }
        prepareAds()
        let next = defaults.integer(forKey: AdDefaults.groupScreeningsCompletedTotal) + 1
        defaults.set(next, forKey: AdDefaults.groupScreeningsCompletedTotal)
        guard next % AppConfig.groupScreeningsPerInterstitial == 0 else { return }
        showInterstitialForGroupScreeningMilestone()
    }

    func showInterstitialIfEligible() {
        guard !isPremium else {
            #if DEBUG
            adDebugLog.debug("Interstitial skipped: user is premium (subscription or debug override)")
            #endif
            return
        }
        // Defer so SwiftUI modals (e.g. cleanup complete) can leave the hierarchy before the ad SDK presents.
        interstitialWaterfall.presentInterstitial(presentationDelay: 0.65)
    }

    private func showInterstitialForGroupScreeningMilestone() {
        guard !isPremium else { return }
        interstitialWaterfall.presentInterstitial(presentationDelay: 0.45)
    }

    private func handleInterstitialFinished() {
        objectWillChange.send()
    }

    /// Rewarded: e.g. "Watch ad to lift 200-item limit this run."
    func loadRewarded() {
        // TODO: Unity rewarded primary, AdMob fallback
    }

    func showRewarded(onReward: @escaping () -> Void) {
        guard !isPremium else { onReward(); return }
        onReward()
    }
}
