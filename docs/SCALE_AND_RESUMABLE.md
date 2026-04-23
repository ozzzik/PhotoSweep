# Scale (100k–150k assets) and resumable scans

## Goals (from PRD §6)

- Support **100k–150k assets** without freezing or OOM.
- **Resumable scans**: progress persisted so an interrupted scan can be continued or at least reported.
- **Throttle** Vision/work on low battery or high thermal state.

---

## Current implementation

### Resumable state (done)

- **IndexStore** persists `ScanJobState`: `jobId`, `scopeDescription`, `modes`, `totalAssetCount`, `processedCount`, `lastUpdated`.
- **CleanupOrchestrator** saves progress every **50 items** during duplicate scanning and at phase boundaries (e.g. before similar-shot grouping).
- On **cancel** or **error**, state is cleared; on **success**, state is cleared and `lastFullScanDate` is set.
- **Interrupted-scan prompt**: When the user taps "Scan now", we call `loadInterruptedJobState()`. If a recent job exists (within 24h), we show: *"Previous scan interrupted at X%. Start new scan?"* with **Start new** (clears state and starts from the beginning) or **Cancel**.

### What “resumable” does **not** do yet

- **True resume** (continue from `processedCount`) is not implemented. Today we only offer **Start new**, which re-runs the full scan. To implement real resume we would:
  1. Persist **partial results** (e.g. duplicate clusters found so far) in IndexStore or a separate store.
  2. When resuming, re-fetch the same scope, skip assets already in `processedCount`, run duplicate/similar only on the remainder, then **merge** with the persisted partial results.
  3. UI: "Resume" button next to "Start new" in the interrupted-scan alert.

### Throttle (done)

- **CleanupOrchestrator** (and optionally services) call `ScaleThrottle.shouldThrottle()`:
  - **Thermal**: `ProcessInfo.processInfo.thermalState == .critical` or `.serious` → throttle.
  - **Battery**: Low level and **unplugged** → throttle.
- When throttling, we **yield** (e.g. 1–2 seconds) every N items so the device can cool down or preserve battery. Progress continues; we do not pause the whole scan.

### Scale tactics (current and planned)

| Tactic | Status |
|--------|--------|
| Batch progress saves (every 50) | ✅ Done |
| Interrupted-scan prompt + “Start new” | ✅ Done |
| Thermal/battery throttle (yield) | ✅ Done |
| True resume from saved `processedCount` | 📋 Planned (persist partial clusters + merge) |
| Background continuation | 📋 Planned (e.g. BGTask or continue in background with limited time) |
| Memory: stream / page assets instead of loading full scope at once | 📋 Optional for very large scopes |

---

## Plan summary

1. **Resumable (current)**  
   Progress is saved every 50 items; user sees an interrupted-scan alert and can **Start new**. No computational resume yet.

2. **Resumable (next)**  
   Add persistence of partial duplicate/similar results and a **Resume** path that continues from `processedCount` and merges with saved results.

3. **Scale**  
   Throttle on thermal and low battery; keep batching and progress saves; consider background continuation and, for very large libraries, paged/streaming asset loading.
