# Known Console Errors

These errors may appear in the Xcode console. Most are system-level and not actionable from app code.

## Apple / System Errors

| Error | Cause | Action |
|-------|-------|--------|
| `Error Domain=com.apple.accounts Code=7` | iCloud/Accounts framework internal | Harmless; often when device isn't signed into iCloud or during simulator runs |
| `Gesture: System gesture gate timed out` | iOS gesture recognizer timeout | Benign; system timing |
| `numANECores: Unknown aneSubType` | Apple Neural Engine device info | Simulator/device metadata; ignore |
| `UIContextMenuInteraction updateVisibleMenuWithBlock while no context menu is visible` | System context menu API called when menu not shown | Can occur with List/NavigationLink long-press; usually timing. No app fix needed |
| `Connection to assetsd was interrupted - assetsd exited, died, or closed the photo library` | Photos daemon (assetsd) restarted or closed | Can happen when Photos app is open, device under memory pressure, or app backgrounded. Retry photo operations |
| `CoreData: error: XPC: ... Photos.sqlite ... connection invalidated` | Photos database connection lost (follows assetsd) | Same as above; retry after a moment |

## Fixed

- **Trip re-scanning on back**: Trips view no longer re-runs the full scan when navigating back from a similar/duplicate group detail. Scan runs only on first load (empty state) or when scope changes.
- **Duplicate scan logs**: Removed redundant `os.log` output so each scan message appears once.

## Mitigation

- **assetsd / CoreData**: If photo fetches fail, show a retry option. The app already surfaces fetch errors via `errorMessage` in list views.
- **Context menu**: Avoid calling context menu update APIs; SwiftUI manages this. If reproducible, check for rapid view updates during dismissal.
