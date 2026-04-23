# PhotoSweep — Roadmap

## Done ✅

- **Core flows:** Onboarding, scan setup (scope + modes), scanning with progress, results
- **Duplicate detection:** Perceptual similarity (Vision), cluster review, best-photo suggestion
- **Similar shots:** Same-day grouping, best-photo suggestion
- **Screenshots, Large videos, Low-quality older, Blurry & accidental, Junk & clutter, Manual swipe**
- **Safe delete:** Recently Deleted, 15s undo, iCloud note on confirmation
- **Scope options:** Recent (7/30d), This month, This year, By year, Specific dates, All
- **Interrupted-scan prompt:** "Start new scan?" when previous scan didn't finish
- **Scale:** Progress saves every 50 items, thermal/battery throttle, resumable state saved
- **ATT:** App Tracking Transparency before loading ads
- **Analytics:** Event queue, flush on background, `trackSessionStart`, `trackCleanupCompleted`, `trackAdShown`, `trackOnboardingComplete`
- **Interstitial:** Full-screen (AdMob-first waterfall); no app-side daily/cooldown cap in `AdManager`
- **Photo preview:** Tap magnifying glass on any list row to see full-size image before deleting
- **Junk refinements:** Exclude people; tightened document keywords (no "text"/"sign" false positives)
- **Blurry & accidental:** New low-quality category (any age, no 2-year minimum)
- **Scan result persistence (premium):** Duplicate clusters and similar groups saved to disk; restored on app launch so Duplicates/Similar tabs show last scan without re-scanning. **Free users** keep results in memory for the current app process (lost on force-quit or OS terminating the app; not persisted to disk).
- **Free tier session reset:** If the app stays in the background at least **`AppConfig.freeTierBackgroundSessionResetSeconds`** (24h), in-memory duplicate/similar results are cleared when returning (premium unchanged).
- **“Seen before” (premium):** Photo asset IDs (`localIdentifier`) are remembered when a duplicate/similar group is opened in detail; new scans can show **Seen before** on rows that overlap with earlier visits. **Settings → Clear “Seen before” history** resets this memory.
- **Scan debug logging:** Start/finish and phase timing in Debug builds; filter Console by "Scan". See `docs/SCAN_PERFORMANCE_NOTES.md`.
- **Best-photo perf:** Skip full-size load on iOS < 26 (lens smudge unavailable).
- **Trips category:** Vacation, city day, landmark photos (beach, cityscape, monument, mountain, etc.).

---

## Next (short term)

- **Real ad SDK:** Replace placeholder with AdMob or similar; respect ATT status
- **Premium:** Paywall or IAP for ad-free; `isPremium` flag already wired
- **True resume:** Resume scan from saved `processedCount` (persist partial clusters, merge on resume)
- **VoiceOver:** Audit and fix labels for all screens
- **Localization:** `LocalizedStringKey` for English; add `Localizable.strings`
- **Face ID:** Optional for large deletes (PRD §4)

---

## Later

- **Background continuation:** BGTask or limited background time for long scans
- **Paged streaming:** For 100k+ assets, stream assets in batches instead of loading full scope
- **Incremental scan:** "Fetch modified since lastFullScanDate" for faster re-scans
- **Retention:** "New duplicates" badge, weekly summary
- **Optional cloud:** NIMA/QUASAR for "smarter" best-photo (premium tier)

---

## Reference

- **PRD:** `PRD.md`
- **Product brief:** `PRODUCT_BRIEF.md`
- **Scale plan:** `docs/SCALE_AND_RESUMABLE.md`
