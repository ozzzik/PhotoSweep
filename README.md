# PhotoSweep (iOS)

Ad-supported iOS app to find duplicate photos, group similar same-day photos, and suggest the best shot in each group. All analysis runs on-device (Photos + Vision).

## Requirements

- Xcode 15+
- iOS 17.0+ (device or simulator)
- For “best photo” lens-smudge scoring: iOS 26+ (optional; on earlier versions all photos get equal score)

## Setup and run

### Option A: XcodeGen + CocoaPods (recommended)

Ads use **Unity Ads** (primary) and **Google Mobile Ads / AdMob** (fallback). Dependencies are managed with **CocoaPods**.

1. Install tools: `brew install xcodegen` and [CocoaPods](https://cocoapods.org/) (`gem install cocoapods` or Homebrew).
2. From the repo root:
   ```bash
   make project
   # or: xcodegen generate && pod install
   ```
3. Open **`PhotosCleanup.xcworkspace`** (not `.xcodeproj`), select a simulator or device, and run (⌘R).

Whenever you change `project.yml`, run `make project` again so the Xcode project and Pods stay in sync.

**If Xcode or the editor says it can’t find `GoogleMobileAds` or `UnityAds`:** the app target lost CocoaPods settings. Run `pod install` (or `make project`) from the repo root, then open **`PhotosCleanup.xcworkspace`** — not the `.xcodeproj` alone. `project.yml` runs `pod install` automatically after `xcodegen generate`.

Configure Unity Game ID and placements in `PhotosCleanup/Core/AppConfig.swift`. AdMob App ID is in `Info.plist` as `GADApplicationIdentifier` (Google’s sample ID is used for development).

### Option B: New Xcode project

1. In Xcode: **File → New → Project → App** (iOS, SwiftUI, Swift).
2. Product name: `PhotosCleanup`, Bundle ID: `com.whio.photoscleanup.app`, minimum deployment iOS 17.
3. Add the `PhotosCleanup` folder (with `App`, `Core`, `Features`, `UI`, `Info.plist`) to the target.
4. In **Signing & Capabilities**, set your team.
5. In the target’s **Info** tab (or `Info.plist`), add:
   - **Privacy - Photo Library Usage Description**: "PhotoSweep needs access to your photo library to find duplicates, group similar photos, and suggest the best shot. All processing is done on your device."
6. Build and run.

## Project structure

```
PhotosCleanup/
├── App/
│   ├── PhotosCleanupApp.swift    # @main
│   └── RootView.swift            # Tabs + photo permission
├── Core/Services/
│   ├── PhotoLibraryService.swift # PHPhotoLibrary fetch, load image, delete
│   ├── DuplicateDetectionService.swift  # Vision feature-print duplicate clustering
│   ├── SimilarGroupingService.swift     # Same-day + Vision similarity grouping
│   └── BestPhotoService.swift    # Lens smudge (iOS 18) for “best” pick
├── Features/
│   ├── Home/HomeView.swift
│   ├── Duplicates/
│   │   ├── DuplicatesListView.swift
│   │   └── DuplicateClusterDetailView.swift
│   └── SimilarGroups/
│       ├── SimilarGroupsListView.swift
│       └── SimilarGroupDetailView.swift
├── UI/Components/
│   └── AssetThumbnailView.swift
└── Info.plist
```

## Features

- **Duplicates**: Scan library → clusters of duplicate/near-duplicate photos → pick “keep” / “remove” or “keep best only” → delete to Recently Deleted.
- **Similar (same day)**: Group by date + Vision similarity → expand groups → choose best or remove selected → delete to Recently Deleted.
- **Best photo**: Uses Vision (e.g. lens smudge on iOS 18) to suggest one “best” photo per cluster/group; extensible for face quality and aesthetics later.
- **Privacy**: All processing on-device; no cloud. Photo library access is read/write only for delete-after-confirm.

## Next steps

- Replace **Unity** / **AdMob** test IDs in `AppConfig` and `Info.plist` for production; add full **SKAdNetwork** entries from AdMob’s checklist when using mediation-sized demand.
- Add **perceptual hashing** (e.g. SwiftImageHash) for a fast first-pass duplicate filter before Vision.
- Tune **similarity thresholds** in `DuplicateDetectionService` and `SimilarGroupingService` for your UX.
- Add **onboarding** and **empty states** (see `PRODUCT_BRIEF.md`).
- Consider **background / batched** scanning for very large libraries (20k+ photos).

## Product spec

See [PRODUCT_BRIEF.md](PRODUCT_BRIEF.md) for vision, requirements, and the prompt to use with Gemini/ChatGPT/Perplexity for more product requirements.
