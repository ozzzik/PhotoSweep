//
//  AppConfig.swift
//  PhotosCleanup
//
//  Central config for app name and branding. Change here to update everywhere.
//

import Foundation

enum AppConfig {
    /// Display name shown in the app (onboarding, nav title, etc.)
    static let appName = "PhotoSweep"

    /// App Store Connect: Primary name (30 chars max). e.g. "PhotoSweep - Photo Cleanup"
    /// Set INFOPLIST_KEY_CFBundleDisplayName in project for the home screen name.
    static let appStoreName = "PhotoSweep"

    /// App Store Connect: Subtitle (30 chars max). e.g. "Find duplicates & reclaim space"
    static let appStoreSubtitle = "Find duplicates & reclaim space"

    // MARK: - In-App Purchase (must match App Store Connect + local Products.storekit)

    /// Auto-renewing subscription — monthly tier (same subscription group as yearly).
    static let subscriptionMonthlyProductID = "com.whio.photoscleanup.app.premium.monthly"

    /// Auto-renewing subscription — yearly tier.
    static let subscriptionYearlyProductID = "com.whio.photoscleanup.app.premium.yearly"

    // MARK: - Free tier session (in-memory scan results)

    /// If the app stays in the background at least this long, free users’ in-memory duplicate/similar results are cleared when returning (premium unchanged).
    static let freeTierBackgroundSessionResetSeconds: TimeInterval = 24 * 60 * 60

    // MARK: - Vision (VNGenerateImageFeaturePrintRequest revision 2)

    /// Duplicate clustering: `computeDistance` must be **at or below** this (lower = stricter). Previously hard-coded `0.1`; Photos recompression and simulator test PNGs often land slightly above that even for true duplicates.
    static let duplicateVisionMaxDistance: Float = 0.32

    /// Same-calendar-day “similar scene” grouping: distance must be **<=** this (higher = larger groups). Procedural / synthetic images with the same layout but small pixel shifts often sit **above** `1.0` even though they look alike to humans.
    static let similarSameDayVisionMaxDistance: Float = 3.5

    // MARK: - Ads (interstitial: AdMob first; banner: see `useUnityBanner`)

    /// Unity Monetization dashboard — Apple (iOS) Game ID.
    static let unityGameID = "6071792"

    /// `true` when a real Unity Game ID is set (not a placeholder).
    static var isUnityAdsConfigured: Bool {
        !unityGameID.isEmpty && !unityGameID.hasPrefix("REPLACE")
    }

    /// If `false`, try **AdMob first** for the banner; Unity can still be used as fallback (see `useUnityBannerFallbackWhenAdMobFails`).
    /// If `true`, try **Unity first**, then AdMob when Unity fails.
    static let useUnityBanner = false

    /// When `useUnityBanner` is `false`, load Unity’s banner only after AdMob gives up (no fill / rate limit / max retries).
    /// Requires `isUnityAdsConfigured` and a valid `unityBannerPlacementID` in the Unity dashboard.
    static let useUnityBannerFallbackWhenAdMobFails = true

    /// When `false`, interstitials are **AdMob only**: if there is no fill or load fails, nothing is shown (no Unity interstitial). Set `true` only if you want Unity as backup for interstitials.
    static let useUnityInterstitialFallbackWhenAdMobUnavailable = false

    /// After this many duplicate/similar **group detail** sessions (user leaves the group screen), try an interstitial (non‑premium only; no app-side interstitial frequency cap in `AdManager`).
    static let groupScreeningsPerInterstitial = 3

    /// Interstitial Ad Unit ID (Unity dashboard — e.g. Interstitial_iOS).
    static let unityInterstitialPlacementID = "Interstitial_iOS"

    /// Banner Ad Unit ID (Unity dashboard — e.g. Banner_iOS).
    static let unityBannerPlacementID = "Banner_iOS"

    /// Rewarded Ad Unit ID (Unity dashboard — use when wiring rewarded ads).
    static let unityRewardedPlacementID = "Rewarded_iOS"

    /// AdMob app ID (PhotoSweep in AdMob console).
    static let adMobApplicationID = "ca-app-pub-4048960606079471~6159396073"

    /// AdMob interstitial (PhotoSweep 2.0).
    static let adMobInterstitialUnitID = "ca-app-pub-4048960606079471/3160134540"

    /// AdMob banner (PhotoSweep 2.0).
    static let adMobBannerUnitID = "ca-app-pub-4048960606079471/2936773269"

    #if DEBUG
    /// When `true`, `resolvedAdMobBannerUnitID` uses Google’s official test unit so the banner slot always fills while you verify layout. Set `false` to exercise your real banner ID in DEBUG.
    static let useGoogleTestBannerUnitInDebug = true

    /// When `true`, `resolvedAdMobInterstitialUnitID` uses Google’s official test interstitial so fills work in DEBUG/simulator (production IDs often have no fill during development).
    static let useGoogleTestInterstitialUnitInDebug = true
    #endif

    /// Unit ID passed to `BannerView` (test unit in DEBUG when `useGoogleTestBannerUnitInDebug` is enabled).
    static var resolvedAdMobBannerUnitID: String {
        #if DEBUG
        if useGoogleTestBannerUnitInDebug {
            return "ca-app-pub-3940256099942544/2934735716"
        }
        #endif
        return adMobBannerUnitID
    }

    /// Interstitial unit passed to `InterstitialAd.load` (Google test unit in DEBUG when enabled — matches banner test-ID pattern).
    static var resolvedAdMobInterstitialUnitID: String {
        #if DEBUG
        if useGoogleTestInterstitialUnitInDebug {
            return "ca-app-pub-3940256099942544/4411468910"
        }
        #endif
        return adMobInterstitialUnitID
    }
}
