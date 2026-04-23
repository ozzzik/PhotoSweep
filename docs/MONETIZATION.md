# PhotoSweep — Monetization & Premium

## Free forever

- **All cleanup modes** — Duplicates, Similar, Screenshots, Large videos, Low-quality, Blurry, Junk, Trips, Manual swipe.
- **Full scope** — Recent, This month, This year, By year, Custom range, All photos.
- **Scan & delete** — No limit on how many items you can delete per run.
- **Scan result persistence** — Duplicates and Similar results survive app restart (same for free and premium in current implementation).
- **Best-photo suggestion** — "Keep best" and suggested best per cluster/group.

Free users see ads. Premium removes them and unlocks any future premium-only features.

---

## Ads (free users only)

### Banner

- **Where:** Bottom of **Home** tab; bottom of **Duplicates** and **Similar** results list when scrolling.
- **Count:** One banner per screen (e.g. one on Home, one on each of Duplicates/Similar when viewing results).
- **Not shown:** On confirmation/modals (e.g. delete confirmation, cleanup complete sheet), or when the user has premium.

### Interstitial (full-screen)

- **When:** After **Done** / **Clean another** on **Cleanup complete**, and on a cadence after leaving duplicate/similar **group detail** screens (see `AppConfig.groupScreeningsPerInterstitial` and `AdManager.recordGroupScreening()`).
- **Frequency:** No app-enforced daily or minimum-interval cap in `AdManager` (network/SDK behavior still applies).
- **Not shown:** On confirmation dialogs, during scanning, or when the user has premium.

### Rewarded (optional, future)

- **When:** e.g. "Watch an ad to unlock X" (e.g. one-time lift of a limit, or extra analysis).
- **Count:** User-initiated only; no automatic frequency cap beyond one ad per tap.

---

## Premium

- **What:** No banner, no interstitials (and no rewarded ads if we add them), plus scope / persistence features as documented in Settings.
- **Unlock:** **Auto-renewing subscription** via StoreKit 2 (`SubscriptionManager`). Product IDs are in `AppConfig` and must match **App Store Connect** and `PhotosCleanup/Configuration/Products.storekit` (local testing).
- **Restore:** **Settings → Restore purchases** (uses `AppStore.sync()`).
- **Debug:** In DEBUG builds, Settings can grant/clear a **local** premium override for testing without the App Store.

---

## App Store rating

- **When:** After a **positive moment** (e.g. user finished a cleanup and tapped **Done** or **Clean another**), with a short delay. Also **Settings → Rate PhotoSweep** (manual).
- **Rules:** **First prompt:** at least **3 launches** and **1 completed cleanup**. **Later prompts:** at least **6 usage events** (each launch + each cleanup completion counts) since the last prompt, and at least **30 days** since the last request. The system may still choose not to show the dialog; Apple limits how often users see it.
- **How:** `StoreKit` `requestReview` (system may or may not show the dialog). Implemented in `AppReviewManager` + `CleanupCompleteView` (after Done with 1.5s delay).
