# Ads setup — Unity (primary) + AdMob (fallback)

The app uses **CocoaPods** with:

- **`UnityAds`** — primary network for **banner** and **interstitial** (your current setup while AdMob is limited).
- **`Google-Mobile-Ads-SDK`** — **fallback** when Unity fails to load/show, or when you want AdMob back after account recovery.

Implementation:

- `InterstitialAdWaterfall.swift` — presents **AdMob** when loaded, else **Unity**; SDKs still preload on bootstrap.
- `BannerAdWaterfallView.swift` — **AdMob** adaptive banner first (configurable); Unity banner as optional fallback.
- `AdManager.prepareAds()` — bootstraps SDKs after onboarding (from `RootView`).
- `PhotosCleanupApp` starts `MobileAds.shared` (Google). Unity is initialized in the waterfall.

Always open **`PhotosCleanup.xcworkspace`** after `pod install`.

### “No ads” while testing

- **Interstitials** have **no app-side daily or cooldown limit** in `AdManager` (AdMob/Unity may still rate-limit or not fill). **Settings → Debug: reset interstitial cooldown** clears the “every N group screenings” counter used for milestone interstitials.
- **Premium** (subscription or **Debug: grant premium**) hides all ads — turn off the debug override or use a non-subscribed StoreKit state.
- **Banners** wait for Unity to initialize; if Unity is slow or fails, the app falls back to **AdMob** after ~6 seconds.

---

## 1. Unity Grow / Ads (primary)

1. Create the iOS app in the [Unity Monetization](https://unity.com/products/unity-ads) / Grow dashboard (bundle ID **`com.whio.photoscleanup.app`**).
2. Copy the **Game ID** into `AppConfig.unityGameID` (replace `REPLACE_WITH_UNITY_GAME_ID`).
3. Create placements (e.g. **Interstitial**, **Banner**) and copy IDs into:
   - `AppConfig.unityInterstitialPlacementID`
   - `AppConfig.unityBannerPlacementID`
4. Use **test mode** in DEBUG builds (wired in code); use dashboard test placements while integrating.

---

## 2. Google AdMob (fallback)

1. **AdMob app** for iOS with the same bundle ID.
2. **App ID** → `Info.plist` key **`GADApplicationIdentifier`** (replace Google’s sample `ca-app-pub-3940256099942544~1458002511` when going live).
3. **Ad units** → `AppConfig.adMobInterstitialUnitID`, `AppConfig.adMobBannerUnitID` (sample IDs work for development).

---

## 3. Privacy & compliance

- **Privacy Policy URL** — replace `example.com` links in Settings.
- **ATT** — `NSUserTrackingUsageDescription` can be added to `Info.plist` if you request tracking; timing is handled in `AttConsentController`.
- **GDPR / CMP** — if you serve ads in the EU/UK, follow Google/Unity guidance (e.g. UMP).
- **SKAdNetwork** — `Info.plist` includes **`SKAdNetworkItems`** using [Google’s AdMob iOS quick-start snippet](https://developers.google.com/admob/ios/quick-start#update_your_infoplist) (third-party buyer IDs for attribution). Refresh periodically from [third-party SKAdNetwork IDs](https://developers.google.com/admob/ios/3p-skadnetworks) if AdMob logs warn about missing identifiers.

---

## 4. What to send / configure

| Item | Where |
|------|--------|
| Unity **Game ID** | `AppConfig.unityGameID` |
| Unity **interstitial** / **banner** placement IDs | `AppConfig` |
| AdMob **App ID** | `Info.plist` → `GADApplicationIdentifier` |
| AdMob **banner** / **interstitial** unit IDs | `AppConfig` |

---

## 5. Regenerating the project

Running **`xcodegen generate`** overwrites `PhotosCleanup.xcodeproj` and **removes** CocoaPods hooks until you run **`pod install`** again. Use:

```bash
make project
```

Then open **`PhotosCleanup.xcworkspace`**.
