# PhotoSweep — Product Requirements

## 1. Product overview

**One-liner:** Ad-supported iOS app that analyzes your photo library on-device to find duplicates, similar shots, screenshots, and large videos, then recommends the best photos to keep and safely deletes the rest—user chooses scan scope and cleanup mode every time.

**Principles:** User in control (scope + modes per run); on-device intelligence (Vision + perceptual hashing); safe by design (no auto-deletes, Recently Deleted); monetization via ads + optional premium.

---

## 2. Scan scopes (user chooses)

- **Recent:** Last 7 days, Last 30 days (default).
- **By year:** List years with counts (e.g. "2026 (3,420)").
- **Custom range:** Date picker from/to.
- **Entire library:** All photos (slower; recommend when plugged in).

## 3. Cleanup modes (multi-select per run)

- Duplicates & near-duplicates
- Similar same-day photos (event/burst)
- Screenshots & utility images
- Large videos & Live Photos
- Low-quality older photos
- Manual swipe review

## 4. Key flows

- **Onboarding:** Welcome → Permission explainer → Allow Photos. If "Selected Photos", show banner to expand access.
- **Scan setup:** Scope (segmented) + Modes (checklist) + "Scan now".
- **Scanning:** Progress circle, pause/cancel, background continuation, tip to plug in.
- **Results:** Per-mode lists (duplicates clusters, similar day cards, etc.) → cluster detail → keep/delete toggles → "Delete X selected".
- **Deletion:** Confirmation sheet (count, GB, iCloud note); optional Face ID for large deletes; then Recently Deleted; "Cleanup complete" with undo (15–30s) and "Back to home" (interstitial trigger).

## 5. Monetization

- **Banner:** Home and results list bottom; no banners on confirmation modals.
- **Interstitial:** After "Back to home" post-cleanup, after long swipe session; frequency cap (e.g. 1 per 5–8 min, max 3/day).
- **Rewarded:** e.g. "Watch ad to lift 200-item limit this run" or "Watch ad to run low-quality analysis on full library."
- **Premium:** No ads, higher batch limit, extra modes, scan result persistence (Duplicates/Similar survive app restart).

## 6. Non-functional

- Support 100k–150k assets; resumable scans; throttle Vision on low battery/thermal.
- No photo pixels/vectors leave device in v1; analytics: session, mode usage, items deleted, bytes freed, ad events only.
- Full VoiceOver, Dynamic Type, LocalizedStringKey for English v1.

---

See repo/wiki for full PRD with wireframe descriptions, data model, and architecture.
