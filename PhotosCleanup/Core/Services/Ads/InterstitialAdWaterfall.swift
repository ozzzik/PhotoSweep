//
//  InterstitialAdWaterfall.swift
//  PhotosCleanup
//
//  AdMob interstitial when filled; Unity after AdMob miss or short wait (see `attemptPresentInterstitial`).
//

import Foundation
@preconcurrency import GoogleMobileAds
import UIKit
@preconcurrency import UnityAds
#if DEBUG
import os.log
fileprivate let interstitialAdLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PhotosCleanup", category: "Ads")
#endif

/// Loads and presents interstitials. **AdMob first** when loaded; Unity when AdMob isn’t available or after AdMob present failure.
@MainActor
final class InterstitialAdWaterfall: NSObject, UnityAdsInitializationDelegate, UnityAdsLoadDelegate, UnityAdsShowDelegate, FullScreenContentDelegate {

    /// Called when an interstitial is actually presented (unity | admob).
    var onInterstitialPresented: ((String) -> Void)?

    /// Called when the user dismisses any interstitial (or show fails before display).
    var onInterstitialFinished: (() -> Void)?

    private var unityInitialized = false
    /// Prevents calling `UnityAds.initialize` twice before the first callback (duplicate `bootstrap()`).
    private var unityInitializationStarted = false
    private var unityInterstitialReady = false
    private var adMobInterstitial: GoogleMobileAds.InterstitialAd?
    private var isLoadingAdMob = false
    private var pendingShowAfterAdMobLoad = false
    /// When AdMob is not ready yet, wait briefly for a fill before showing Unity (Unity often finishes loading first).
    private var adMobFillWaitWorkItem: DispatchWorkItem?

    func bootstrap() {
        startUnityIfNeeded()
        loadAdMobInterstitial()
    }

    /// Attempts to show an interstitial: AdMob when already loaded; otherwise load AdMob and wait ~2.5s before Unity fallback.
    /// - Parameter presentationDelay: Seconds to wait so SwiftUI sheets can finish dismissing (e.g. cleanup complete).
    func presentInterstitial(presentationDelay: TimeInterval = 0) {
        if presentationDelay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + presentationDelay) { [weak self] in
                Task { @MainActor [weak self] in
                    self?.attemptPresentInterstitial()
                }
            }
        } else {
            attemptPresentInterstitial()
        }
    }

    private func attemptPresentInterstitial() {
        guard let presenter = UIApplication.shared.adsStablePresenterForFullscreenAd() else {
            #if DEBUG
            interstitialAdLog.debug("Interstitial not shown: no UIViewController to present from (sheet still dismissing?)")
            #endif
            pendingShowAfterAdMobLoad = false
            adMobFillWaitWorkItem?.cancel()
            adMobFillWaitWorkItem = nil
            onInterstitialFinished?()
            return
        }

        if let ad = adMobInterstitial {
            pendingShowAfterAdMobLoad = false
            adMobFillWaitWorkItem?.cancel()
            adMobFillWaitWorkItem = nil
            ad.fullScreenContentDelegate = self
            ad.present(from: presenter)
            return
        }

        // No AdMob fill yet: load and wait before Unity so AdMob can win when it fills a moment later.
        pendingShowAfterAdMobLoad = true
        adMobFillWaitWorkItem?.cancel()
        loadAdMobInterstitial()

        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.presentInterstitialAfterAdMobWaitIfStillPending()
            }
        }
        adMobFillWaitWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }

    /// After a short wait for AdMob, show cached AdMob, else Unity, else finish (so `onInterstitialFinished` always runs when we had a pending show).
    private func presentInterstitialAfterAdMobWaitIfStillPending() {
        adMobFillWaitWorkItem = nil
        guard pendingShowAfterAdMobLoad else { return }

        guard let presenter = UIApplication.shared.adsStablePresenterForFullscreenAd() else {
            pendingShowAfterAdMobLoad = false
            onInterstitialFinished?()
            return
        }

        if let ad = adMobInterstitial {
            pendingShowAfterAdMobLoad = false
            ad.fullScreenContentDelegate = self
            ad.present(from: presenter)
            return
        }

        pendingShowAfterAdMobLoad = false
        if AppConfig.useUnityInterstitialFallbackWhenAdMobUnavailable,
           AppConfig.isUnityAdsConfigured, unityInitialized, unityInterstitialReady {
            UnityAds.show(presenter, placementId: AppConfig.unityInterstitialPlacementID, showDelegate: self)
            return
        }

        onInterstitialFinished?()
    }

    private func startUnityIfNeeded() {
        guard AppConfig.isUnityAdsConfigured else {
            unityInitialized = false
            unityInitializationStarted = false
            return
        }
        guard !unityInitialized else {
            loadUnityInterstitialIfNeeded()
            return
        }
        guard !unityInitializationStarted else { return }
        unityInitializationStarted = true
        #if DEBUG
        let testMode = true
        #else
        let testMode = false
        #endif
        UnityAds.initialize(AppConfig.unityGameID, testMode: testMode, initializationDelegate: self)
    }

    private func loadUnityInterstitialIfNeeded() {
        guard AppConfig.isUnityAdsConfigured, unityInitialized else { return }
        unityInterstitialReady = false
        UnityAds.load(AppConfig.unityInterstitialPlacementID, loadDelegate: self)
    }

    private func loadAdMobInterstitial() {
        guard !isLoadingAdMob else { return }
        isLoadingAdMob = true
        GoogleMobileAds.InterstitialAd.load(
            with: AppConfig.resolvedAdMobInterstitialUnitID,
            request: Request()
        ) { [weak self] ad, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isLoadingAdMob = false
                if let ad {
                    self.adMobInterstitial = ad
                    ad.fullScreenContentDelegate = self
                    if self.pendingShowAfterAdMobLoad {
                        self.adMobFillWaitWorkItem?.cancel()
                        self.adMobFillWaitWorkItem = nil
                        self.pendingShowAfterAdMobLoad = false
                        self.presentInterstitial(presentationDelay: 0)
                    }
                } else {
                    #if DEBUG
                    let errMsg = error.map { String(describing: $0) } ?? "nil"
                    interstitialAdLog.debug("AdMob interstitial load failed: \(errMsg, privacy: .public)")
                    #endif
                    self.adMobInterstitial = nil
                    if self.pendingShowAfterAdMobLoad {
                        self.adMobFillWaitWorkItem?.cancel()
                        self.adMobFillWaitWorkItem = nil
                        self.presentInterstitialAfterAdMobWaitIfStillPending()
                    }
                }
            }
        }
    }

    // MARK: - UnityAdsInitializationDelegate

    nonisolated func initializationComplete() {
        Task { @MainActor [weak self] in
            self?.didCompleteUnityInitialization()
        }
    }

    private func didCompleteUnityInitialization() {
        unityInitialized = true
        loadUnityInterstitialIfNeeded()
        NotificationCenter.default.post(name: .unityAdsInitializationResolved, object: nil)
    }

    nonisolated func initializationFailed(_ error: UnityAdsInitializationError, withMessage message: String) {
        Task { @MainActor [weak self] in
            self?.didFailUnityInitialization()
        }
    }

    private func didFailUnityInitialization() {
        unityInitialized = false
        unityInitializationStarted = false
        unityInterstitialReady = false
        loadAdMobInterstitial()
        NotificationCenter.default.post(name: .unityAdsInitializationResolved, object: nil)
    }

    // MARK: - UnityAdsLoadDelegate

    nonisolated func unityAdsAdLoaded(_ placementId: String) {
        Task { @MainActor [weak self] in
            self?.unityInterstitialReady = true
        }
    }

    nonisolated func unityAdsAdFailed(toLoad placementId: String, withError error: UnityAdsLoadError, withMessage message: String) {
        Task { @MainActor [weak self] in
            self?.unityInterstitialReady = false
            self?.loadAdMobInterstitial()
        }
    }

    // MARK: - UnityAdsShowDelegate

    nonisolated func unityAdsShowComplete(_ placementId: String, withFinish state: UnityAdsShowCompletionState) {
        Task { @MainActor [weak self] in
            self?.handleUnityShowComplete()
        }
    }

    private func handleUnityShowComplete() {
        unityInterstitialReady = false
        onInterstitialFinished?()
        loadUnityInterstitialIfNeeded()
        loadAdMobInterstitial()
    }

    nonisolated func unityAdsShowFailed(_ placementId: String, withError error: UnityAdsShowError, withMessage message: String) {
        Task { @MainActor [weak self] in
            self?.handleUnityShowFailed()
        }
    }

    private func handleUnityShowFailed() {
        unityInterstitialReady = false
        if let presenter = UIApplication.shared.adsStablePresenterForFullscreenAd(), let ad = adMobInterstitial {
            ad.fullScreenContentDelegate = self
            ad.present(from: presenter)
        } else {
            onInterstitialFinished?()
            loadAdMobInterstitial()
        }
    }

    private func handleAdMobPresentFailedWithUnityFallback() {
        adMobInterstitial = nil
        loadAdMobInterstitial()
        guard AppConfig.useUnityInterstitialFallbackWhenAdMobUnavailable else {
            onInterstitialFinished?()
            return
        }
        if AppConfig.isUnityAdsConfigured, unityInitialized, unityInterstitialReady,
           let presenter = UIApplication.shared.adsStablePresenterForFullscreenAd() {
            UnityAds.show(presenter, placementId: AppConfig.unityInterstitialPlacementID, showDelegate: self)
            return
        }
        onInterstitialFinished?()
    }

    nonisolated func unityAdsShowStart(_ placementId: String) {
        Task { @MainActor [weak self] in
            self?.onInterstitialPresented?("unity")
        }
    }

    nonisolated func unityAdsShowClick(_ placementId: String) {}

    // MARK: - FullScreenContentDelegate (AdMob)

    nonisolated func adWillPresentFullScreenContent(_ ad: any FullScreenPresentingAd) {
        Task { @MainActor [weak self] in
            self?.onInterstitialPresented?("admob")
        }
    }

    nonisolated func adDidDismissFullScreenContent(_ ad: any FullScreenPresentingAd) {
        Task { @MainActor [weak self] in
            self?.handleAdMobDismissed()
        }
    }

    private func handleAdMobDismissed() {
        adMobInterstitial = nil
        onInterstitialFinished?()
        loadAdMobInterstitial()
    }

    nonisolated func ad(_ ad: any FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.handleAdMobPresentFailed()
        }
    }

    private func handleAdMobPresentFailed() {
        handleAdMobPresentFailedWithUnityFallback()
    }
}

extension Notification.Name {
    /// Posted when Unity Ads finishes initializing (success or failure) so UI (e.g. banners) can retry loading.
    static let unityAdsInitializationResolved = Notification.Name("PhotosCleanup.unityAdsInitializationResolved")
}
