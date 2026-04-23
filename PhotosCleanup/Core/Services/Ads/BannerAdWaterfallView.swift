//
//  BannerAdWaterfallView.swift
//  PhotosCleanup
//
//  Banner order is configured via AppConfig (Unity→AdMob or AdMob→Unity fallback).
//

@preconcurrency import GoogleMobileAds
import SwiftUI
import UIKit
@preconcurrency import UnityAds

/// Bottom banner slot: either Unity → AdMob, or AdMob → Unity (see `AppConfig.useUnityBanner` and `useUnityBannerFallbackWhenAdMobFails`).
struct BannerAdWaterfallView: UIViewRepresentable {

    var isPremium: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.update(container: uiView, isPremium: isPremium)
    }

    /// UIKit + SDK callbacks are handled on the main thread (`updateUIView`, `.main` notification queue, UIKit delegates).
    final class Coordinator: NSObject, UADSBannerViewDelegate, BannerViewDelegate {
        private var unityBanner: UADSBannerView?
        private var admobBanner: BannerView?
        private var triedAdMobFallback = false
        private var admobLoadAttempts = 0
        /// AdMob penalizes rapid repeat requests; keep retries sparse (see `adMobBannerRetryDelay`).
        private let maxAdMobLoadAttempts = 2
        private var admobPendingRetry: DispatchWorkItem?
        /// After "too many failed requests", SDK asks to wait — honor before loading again.
        private var admobRateLimitUntil: Date?

        /// AdMob-first mode: switched after AdMob exhausts retries or is rate-limited; then we show Unity banner.
        private var switchedToUnityBannerFallback = false
        private var admobRematchAdMobWork: DispatchWorkItem?
        private var mobileAdsStartObserver: NSObjectProtocol?

        /// SwiftUI may not call `updateUIView` again when Unity finishes initializing; we poll + listen for `unityAdsInitializationResolved`.
        private var unityWaitStartedAt: Date?
        private var unityInitRetryWork: DispatchWorkItem?
        private var unityInitObserver: NSObjectProtocol?

        private weak var lastContainer: UIView?
        private var lastWidth: CGFloat = 0
        private var lastPremium: Bool = false

        override init() {
            super.init()
            unityInitObserver = NotificationCenter.default.addObserver(
                forName: .unityAdsInitializationResolved,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.onUnityInitResolved()
            }
            mobileAdsStartObserver = NotificationCenter.default.addObserver(
                forName: .googleMobileAdsStartCompleted,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.onMobileAdsStartCompleted()
            }
        }

        deinit {
            unityInitRetryWork?.cancel()
            admobPendingRetry?.cancel()
            admobRematchAdMobWork?.cancel()
            if let unityInitObserver {
                NotificationCenter.default.removeObserver(unityInitObserver)
            }
            if let mobileAdsStartObserver {
                NotificationCenter.default.removeObserver(mobileAdsStartObserver)
            }
        }

        private func onUnityInitResolved() {
            guard let container = lastContainer, !lastPremium else { return }
            let width = lastWidth > 0 ? lastWidth : (container.bounds.width > 0 ? container.bounds.width : UIScreen.main.bounds.width)
            guard width > 0 else { return }
            update(container: container, isPremium: lastPremium)
        }

        private func onMobileAdsStartCompleted() {
            guard let container = lastContainer, !lastPremium else { return }
            update(container: container, isPremium: lastPremium)
        }

        func update(container: UIView, isPremium: Bool) {
            lastContainer = container
            lastPremium = isPremium

            if isPremium {
                clear(container: container)
                return
            }

            let width = container.bounds.width > 0 ? container.bounds.width : UIScreen.main.bounds.width
            lastWidth = width
            guard width > 0 else { return }

            if let until = admobRateLimitUntil, Date() >= until {
                admobRateLimitUntil = nil
                admobLoadAttempts = 0
                switchedToUnityBannerFallback = false
                unityBanner?.removeFromSuperview()
                unityBanner = nil
            }

            // AdMob first; optional Unity banner fallback (Unity interstitials stay separate).
            if !AppConfig.useUnityBanner {
                if AppConfig.useUnityBannerFallbackWhenAdMobFails, switchedToUnityBannerFallback {
                    loadUnityFallbackIfNeeded(container: container, width: width, isPremium: isPremium)
                    return
                }
                unityInitRetryWork?.cancel()
                unityInitRetryWork = nil
                unityWaitStartedAt = nil
                if let until = admobRateLimitUntil, Date() < until {
                    return
                }
                if admobBanner == nil, admobLoadAttempts < maxAdMobLoadAttempts {
                    let w = max(width, UIScreen.main.bounds.width)
                    loadAdMobBanner(container: container, width: w)
                }
                return
            }

            // No Unity project ID yet — use AdMob banner only.
            if !AppConfig.isUnityAdsConfigured {
                if let until = admobRateLimitUntil, Date() < until {
                    return
                }
                if admobBanner == nil, admobLoadAttempts < maxAdMobLoadAttempts {
                    loadAdMobBanner(container: container, width: width)
                }
                return
            }

            // Unity not ready yet: SwiftUI won't always re-run update when init completes — schedule retries + timeout AdMob.
            if !UnityAds.isInitialized() {
                if unityWaitStartedAt == nil { unityWaitStartedAt = Date() }
                let elapsed = Date().timeIntervalSince(unityWaitStartedAt ?? Date())
                if elapsed >= 6, admobBanner == nil, !triedAdMobFallback {
                    unityInitRetryWork?.cancel()
                    unityInitRetryWork = nil
                    loadAdMobBanner(container: container, width: width)
                    return
                }
                unityInitRetryWork?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    self?.unityInitRetryWork = nil
                    self?.update(container: container, isPremium: isPremium)
                }
                unityInitRetryWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
                return
            }

            unityWaitStartedAt = nil
            unityInitRetryWork?.cancel()
            unityInitRetryWork = nil

            if unityBanner == nil, admobBanner == nil, !triedAdMobFallback {
                loadUnityBanner(container: container, width: width)
            }
        }

        private func clear(container: UIView) {
            unityInitRetryWork?.cancel()
            unityInitRetryWork = nil
            unityWaitStartedAt = nil
            admobPendingRetry?.cancel()
            admobPendingRetry = nil
            admobRematchAdMobWork?.cancel()
            admobRematchAdMobWork = nil
            admobRateLimitUntil = nil
            unityBanner?.removeFromSuperview()
            unityBanner = nil
            admobBanner?.removeFromSuperview()
            admobBanner = nil
            triedAdMobFallback = false
            admobLoadAttempts = 0
            switchedToUnityBannerFallback = false
        }

        private func promoteToUnityBannerFallbackIfPossible(scheduleAdMobRematchAfterUnity: Bool) {
            guard AppConfig.useUnityBannerFallbackWhenAdMobFails, AppConfig.isUnityAdsConfigured else { return }
            switchedToUnityBannerFallback = true
            admobPendingRetry?.cancel()
            admobPendingRetry = nil
            DispatchQueue.main.async { [weak self] in
                guard let self, let c = self.lastContainer, !self.lastPremium else { return }
                self.update(container: c, isPremium: self.lastPremium)
            }
            guard scheduleAdMobRematchAfterUnity else { return }
            admobRematchAdMobWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, let c = self.lastContainer, !self.lastPremium else { return }
                self.admobRematchAdMobWork = nil
                self.switchedToUnityBannerFallback = false
                self.unityBanner?.removeFromSuperview()
                self.unityBanner = nil
                self.admobLoadAttempts = 0
                self.update(container: c, isPremium: self.lastPremium)
            }
            admobRematchAdMobWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 90, execute: work)
        }

        /// After AdMob gives up, poll until Unity Ads is ready then load `UADSBannerView`.
        private func loadUnityFallbackIfNeeded(container: UIView, width: CGFloat, isPremium: Bool) {
            guard AppConfig.isUnityAdsConfigured else { return }
            if UnityAds.isInitialized() {
                unityWaitStartedAt = nil
                unityInitRetryWork?.cancel()
                unityInitRetryWork = nil
                if unityBanner == nil {
                    loadUnityBanner(container: container, width: width)
                }
                return
            }
            if unityWaitStartedAt == nil { unityWaitStartedAt = Date() }
            unityInitRetryWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.unityInitRetryWork = nil
                self?.update(container: container, isPremium: isPremium)
            }
            unityInitRetryWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        }

        private func loadUnityBanner(container: UIView, width: CGFloat) {
            let size = CGSize(width: min(320, width), height: 50)
            let banner = UADSBannerView(placementId: AppConfig.unityBannerPlacementID, size: size)
            banner.delegate = self
            banner.translatesAutoresizingMaskIntoConstraints = false
            container.subviews.forEach { $0.removeFromSuperview() }
            container.addSubview(banner)
            NSLayoutConstraint.activate([
                banner.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                banner.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                banner.heightAnchor.constraint(equalToConstant: 50)
            ])
            unityBanner = banner
            banner.load()
        }

        private func loadAdMobBanner(container: UIView, width: CGFloat) {
            if let until = admobRateLimitUntil, Date() < until { return }
            triedAdMobFallback = true
            unityBanner?.removeFromSuperview()
            unityBanner = nil

            let layoutWidth = max(width, 320)
            let adSize = currentOrientationAnchoredAdaptiveBanner(width: layoutWidth)
            let banner = BannerView(adSize: adSize)
            banner.adUnitID = AppConfig.resolvedAdMobBannerUnitID
            // Banners need a real VC from the key window (fullscreen presenter is often wrong here).
            banner.rootViewController = UIApplication.shared.adsKeyWindow?.rootViewController
                ?? UIApplication.shared.adsStablePresenterForFullscreenAd()
            banner.delegate = self
            banner.translatesAutoresizingMaskIntoConstraints = false
            container.subviews.forEach { $0.removeFromSuperview() }
            container.addSubview(banner)
            NSLayoutConstraint.activate([
                banner.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                banner.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                banner.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
            admobBanner = banner
            admobLoadAttempts += 1
            banner.load(Request())
        }

        // MARK: UADSBannerViewDelegate

        func bannerViewDidLoad(_ bannerView: UADSBannerView) {}

        func bannerViewDidError(_ bannerView: UADSBannerView, error: UADSBannerError) {
            guard let container = bannerView.superview else { return }
            let width = container.bounds.width > 0 ? container.bounds.width : UIScreen.main.bounds.width
            if AppConfig.useUnityBanner {
                loadAdMobBanner(container: container, width: width)
                return
            }
            if AppConfig.useUnityBannerFallbackWhenAdMobFails, switchedToUnityBannerFallback {
                unityBanner?.removeFromSuperview()
                unityBanner = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    guard let self, let c = self.lastContainer, !self.lastPremium else { return }
                    self.update(container: c, isPremium: self.lastPremium)
                }
                return
            }
            loadAdMobBanner(container: container, width: width)
        }

        // MARK: BannerViewDelegate

        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            admobPendingRetry?.cancel()
            admobPendingRetry = nil
            admobRematchAdMobWork?.cancel()
            admobRematchAdMobWork = nil
            admobRateLimitUntil = nil
            switchedToUnityBannerFallback = false
            admobLoadAttempts = 0
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            let message = (error as NSError).localizedDescription
            #if DEBUG
            print("[AdMob] Banner failed: \(message)")
            #endif
            bannerView.removeFromSuperview()
            if admobBanner === bannerView {
                admobBanner = nil
            }
            admobPendingRetry?.cancel()
            admobPendingRetry = nil

            // Server-side throttle — backing off avoids making it worse.
            if message.localizedCaseInsensitiveContains("too many recently failed")
                || message.localizedCaseInsensitiveContains("wait a few seconds") {
                admobRateLimitUntil = Date().addingTimeInterval(70)
                #if DEBUG
                print("[AdMob] Banner: rate limited — no new requests for ~70s")
                #endif
                promoteToUnityBannerFallbackIfPossible(scheduleAdMobRematchAfterUnity: false)
                return
            }

            guard lastContainer != nil, !lastPremium else { return }
            // After a failed load, `admobLoadAttempts` already counts this attempt.
            guard admobLoadAttempts < maxAdMobLoadAttempts else {
                promoteToUnityBannerFallbackIfPossible(scheduleAdMobRematchAfterUnity: true)
                return
            }

            let delay: TimeInterval = 12
            let work = DispatchWorkItem { [weak self] in
                guard let self, let c = self.lastContainer, !self.lastPremium else { return }
                if let until = self.admobRateLimitUntil, Date() < until { return }
                self.update(container: c, isPremium: self.lastPremium)
            }
            admobPendingRetry = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }
}
