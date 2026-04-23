# PhotoSweep — Product Brief

## Vision
A **smart, ad-supported iOS photo cleanup app** that helps users reclaim storage and reduce clutter by finding duplicates, grouping similar shots from the same day, and recommending the “best” photo in each group—with a focus on quality, privacy, and a UI people actually enjoy using.

---

## Core Features (v1)

### 1. Duplicate detection
- **Perceptual similarity**, not just byte-identical files (resized, recompressed, edited copies still detected).
- Use **perceptual hashing** (e.g. pHash/dHash) and/or **Apple Vision** `VNGenerateImageFeaturePrintRequest` for semantic similarity.
- Clear UX: show duplicate clusters, let user pick “keep” vs “remove” (or “merge”), with optional “select all duplicates” / “keep best only”.

### 2. Same-day similar photo grouping
- Group photos **by date** (same day) and **by visual similarity** (same scene/event).
- Use **Vision feature prints** for similarity; combine with date/time from `PHAsset` for grouping.
- UI: timeline or day cards with expandable “similar” stacks; user can review and choose which to keep.

### 3. Best-photo selection
- Within each duplicate or similar group, **suggest the single best photo** using smart factors.
- **Factors:** sharpness, exposure, no lens smudge, faces (eyes open, smiling), composition, aesthetic score where available.
- **Models/APIs to consider:**
  - **Apple Vision (on-device, privacy-first):**
    - `VNGenerateImageFeaturePrintRequest` — similarity.
    - `DetectLensSmudgeRequest` — lens smudge/blur (A14+).
    - Face quality (open eyes, smile) via `VNDetectFaceCaptureQualityRequest` or face landmarks.
    - WWDC24: **image aesthetics** in Vision for quality/aesthetic scoring.
  - **Optional cloud / third-party (if you add a server):**
    - **NIMA** (Google) — quality/aesthetic distribution.
    - **QUASAR** — no-reference quality/aesthetics (embeddings-based).
    - **NVIDIA NeMo Aesthetic Filter** — CLIP-based aesthetic score.
- **Recommendation:** Start with **Vision only** (on-device) for privacy and App Store narrative; add optional cloud “smarter pick” later if needed.

### 4. Monetization
- **Ad-based:** interstitials or rewarded ads at natural breakpoints (e.g. after a cleanup session, or “unlock extra analysis”).
- Consider **optional premium:** one-time or subscription for ad-free + advanced features (e.g. cloud “best photo” model, batch rules).

### 5. UI/UX
- Clean, native-feeling iOS UI (SwiftUI preferred).
- Clear states: scanning → results (duplicates / groups / best picks) → review → confirm delete.
- **Safety:** no auto-delete; user explicitly confirms. Optional “Move to Recently Deleted” first.
- Empty states, onboarding, and progress indicators for large libraries.

---

## Requirements You Might Be Missing (to refine with AI)

- **Privacy & data:** All processing on-device vs any cloud; how you describe this in App Store and in-app.
- **Scale:** Behavior with 20k–100k+ photos (background processing, batching, memory).
- **Media types:** Photos only, or Live Photos, videos, screenshots (separate rules?).
- **iCloud Photos:** Read-only vs delete behavior; sync and “optimize storage” interactions.
- **Undo & safety:** “Recently Deleted” usage, undo period, no permanent delete without confirmation.
- **Onboarding:** First-run permissions (Photos access), value proposition, optional tutorial.
- **Accessibility:** VoiceOver, Dynamic Type, contrast.
- **Localization:** At least English; plan for other languages if you want wider reach.
- **Analytics & ads:** GDPR/ATT (App Tracking Transparency), consent, ad SDK choice.
- **Retention:** What brings users back (e.g. “new duplicates” badge, weekly summary)?

---

## Tech Stack (suggested)

- **Language:** Swift.
- **UI:** SwiftUI.
- **Photos:** `Photos` / `PHPhotoLibrary`, `PHAsset`, `PHImageManager`.
- **Duplicate/similarity:** `VNGenerateImageFeaturePrintRequest` (Vision) and/or Swift perceptual hashing (e.g. `CocoaImageHashing`, `SwiftImageHash`).
- **Quality / best photo:** Vision (`DetectLensSmudgeRequest`, face quality, and any new aesthetics APIs); optional server-side NIMA/QUASAR later.
- **Ads:** Google AdMob or similar; respect ATT and privacy.

---

## Prompt for Gemini / ChatGPT / Perplexity (copy-paste)

Use the following to get more product and UX requirements:

```
I'm defining product requirements for an iOS photo cleanup app. Please act as a product manager and help me make the spec complete and shippable.

**Product in one sentence:**  
Ad-supported iOS app that finds duplicate photos, groups similar same-day photos, and suggests the single best photo in each group, with a focus on privacy (on-device where possible) and a polished UI.

**Core features already in scope:**
1. Duplicate detection using perceptual similarity (not just file hash).
2. Grouping similar photos from the same day (by date + visual similarity).
3. “Best photo” suggestion per group using factors like sharpness, exposure, blur, faces (eyes open, smile), and optional aesthetic scoring.
4. Ad-based monetization with clear, non-intrusive placement.
5. User always confirms before any delete; optional “Recently Deleted” flow.

**Tech context:**  
- Swift/SwiftUI, Photos framework, Apple Vision (VNGenerateImageFeaturePrintRequest, DetectLensSmudgeRequest, face quality, and any image aesthetics APIs).
- Optional: perceptual hashing (pHash/dHash) for duplicates; optional cloud API later for “best photo” (e.g. NIMA/QUASAR).

**I need you to:**
1. List concrete user stories (Who / What / Why) for the first release.
2. Suggest 5–10 non-obvious product or UX requirements (privacy, scale, edge cases, retention, accessibility, compliance).
3. Propose a simple onboarding flow and 3–5 key screens with one-line purpose for each.
4. Call out risks (e.g. performance with 50k+ photos, iCloud sync, App Store review) and one mitigation per risk.
5. Suggest 3–5 success metrics (acquisition, engagement, retention, monetization) and how to measure them without heavy tracking.

Output in clear sections so I can paste into a PRD or spec doc.
```

---

## Summary

- **Duplicates:** Use **perceptual hashing** and/or **Vision feature prints** so edits/resize/format don’t hide duplicates.
- **Similar same-day groups:** **Date + Vision feature print similarity** to cluster by day and scene.
- **Best photo:** Start with **Apple Vision** (blur/smudge, face quality, and any new aesthetics APIs); consider **NIMA**, **QUASAR**, or **NeMo Aesthetic** only if you add a backend and want a “smarter” optional tier.
- **Missing pieces:** Privacy wording, scale (large libraries), media types (Live/video/screenshots), iCloud behavior, undo/safety, onboarding, accessibility, ATT/ads, retention, and metrics—use the prompt above to flesh these out with Gemini/ChatGPT/Perplexity.

Good luck with the app—this is a strong starting set of requirements to iterate on.
