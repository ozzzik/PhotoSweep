# Scan Performance Notes

Debug logging is enabled in Debug builds. Filter Console by `Scan` to see timing.

## Log Format

- `▶ START <label> [scope]` — scan phase begins
- `■ FINISH <label>: X.XXs — summary` — phase complete with duration
- `<phase>: X.XXs (extra)` — sub-phase timing

## Typical Bottlenecks (from metrics)

1. **Feature print extraction** — Vision `VNGenerateImageFeaturePrintRequest` per photo. Dominant cost. Uses downscaled (1024px) images via `loadImageForVision`.
2. **Clustering** — O(n²) similarity comparisons. Fast for small sets; can dominate for 1000+ photos.
3. **Best-photo scoring** — `loadFullSizeImage` per photo in each cluster/group. Expensive. Optimized: on iOS < 26 we skip the load (lens smudge unavailable).
4. **Fetch photos** — PHAsset enumeration. Usually fast; can be slow for large scopes or iCloud-heavy libraries.

## Optimizations Applied

- **BestPhotoService**: Skip full-size load on iOS < 26 (lens smudge API unavailable).
- **loadImageForVision**: Downscale to 1024px for feature prints instead of full size.
- **ScaleThrottle**: Yield on thermal/battery stress to avoid throttling.
- **Shared feature prints (Trips)**: TripListView extracts feature prints once per trip and passes to both `findDuplicates` and `groupSimilarSameDay`, cutting Vision work by ~33% for trip analysis.
- **Skip best-photo for 100+ similar groups**: When Smart scan finds 100+ similar groups, best-photo suggestion is skipped (avoids 5+ min of full-size loads on iOS 26). User can still pick manually.
- **Progress during best-photo**: Shows "Picking best photo (X / N)" instead of stale "Grouping similar" message.

## Potential Future Optimizations

- **Best-photo on iOS 26+**: Use `loadImageForVision` (downscaled) for lens smudge if API accepts it; avoid full-size.
- **Duplicate clustering**: Spatial hashing or LSH for approximate nearest neighbors to reduce O(n²) to O(n log n).
- **Parallel feature prints**: Process photos in batches with `TaskGroup`; Vision is thread-safe.
- **Incremental scan**: Cache feature prints; only process new/changed photos.
- **Reduce targetLongEdge**: Try 512px for feature prints; may be sufficient for similarity.
