//
//  PhotoLibraryService.swift
//  PhotosCleanup
//
//  Fetches assets from the Photos framework. Supports batching for large libraries.
//

import Foundation
@preconcurrency import Photos
import UIKit
import Vision
import AVFoundation
import CoreImage

/// Ensures a continuation is resumed at most once (Photos callbacks can fire multiple times).
/// Resumes on MainActor to satisfy Swift 6 Sendable when T is non-Sendable (e.g. UIImage).
/// Resumes a continuation at most once (Photos may call `requestAVAsset` handlers more than once).
private final class ResumeOnceAVPlayerContinuation: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    private let continuation: CheckedContinuation<AVPlayer?, Never>

    init(_ continuation: CheckedContinuation<AVPlayer?, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: AVPlayer?) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        continuation.resume(returning: value)
    }
}

private final class OneShotContinuation<T>: @unchecked Sendable {
    private var continuation: CheckedContinuation<T, Never>?
    private let lock = NSLock()

    init(_ continuation: CheckedContinuation<T, Never>) {
        self.continuation = continuation
    }

    func resume(returning value: T) {
        lock.lock()
        let c = continuation
        continuation = nil
        lock.unlock()
        Task { @MainActor in
            c?.resume(returning: value)
        }
    }
}

/// Lightweight representation of a photo for use across features.
struct PhotoItem: Identifiable, Sendable {
    let id: String
    let asset: PHAsset
    let creationDate: Date?

    var identifier: String { id }
}

/// Video asset for list rows. Use `asset.estimatedStorageBytes` for size (heuristic for videos).
struct VideoItem: Identifiable, Sendable {
    let id: String
    let asset: PHAsset
    let creationDate: Date?
    let duration: TimeInterval

    var identifier: String { id }
    var estimatedBytes: Int64 { asset.estimatedStorageBytes }
}

@MainActor
final class PhotoLibraryService: ObservableObject {
    private let imageManager = PHCachingImageManager()
    private let queue = DispatchQueue(label: "com.whio.photoscleanup.library", qos: .userInitiated)

    /// Fetch all photo assets (images only, no video) sorted by creation date.
    func fetchAllPhotos() async throws -> [PhotoItem] {
        try await fetchPhotos(scope: .entireLibrary)
    }

    /// Fetch photo assets for the given scope (recent, year, custom range, or entire library).
    func fetchPhotos(scope: ScanScope) async throws -> [PhotoItem] {
        let scopeCopy = scope
        return await withCheckedContinuation { continuation in
            queue.async {
                let predicate = Self.makeImageScopePredicate(scope: scopeCopy)
                let options = PHFetchOptions()
                options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                options.predicate = predicate
                options.fetchLimit = 0
                let fetchResult = PHAsset.fetchAssets(with: .image, options: options)
                let count = fetchResult.count
                var result: [PhotoItem] = []
                result.reserveCapacity(count)
                for i in 0..<count {
                    let asset = fetchResult.object(at: i)
                    result.append(PhotoItem(
                        id: asset.localIdentifier,
                        asset: asset,
                        creationDate: asset.creationDate
                    ))
                }
                DispatchQueue.main.async {
                    continuation.resume(returning: result)
                }
            }
        }
    }

    /// Fetch photo items by local identifiers. Preserves input order; skips IDs not found (e.g. deleted).
    func fetchPhotoItems(identifiers: [String]) async -> [PhotoItem] {
        guard !identifiers.isEmpty else { return [] }
        return await withCheckedContinuation { continuation in
            queue.async {
                let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
                var idToItem: [String: PhotoItem] = [:]
                let count = fetchResult.count
                for i in 0..<count {
                    let asset = fetchResult.object(at: i)
                    let item = PhotoItem(
                        id: asset.localIdentifier,
                        asset: asset,
                        creationDate: asset.creationDate
                    )
                    idToItem[asset.localIdentifier] = item
                }
                let result = identifiers.compactMap { idToItem[$0] }
                DispatchQueue.main.async {
                    continuation.resume(returning: result)
                }
            }
        }
    }

    /// Fetch video items by local identifiers. Preserves input order; skips IDs not found (e.g. deleted).
    func fetchVideoItems(identifiers: [String]) async -> [VideoItem] {
        guard !identifiers.isEmpty else { return [] }
        return await withCheckedContinuation { continuation in
            queue.async {
                let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
                var idToItem: [String: VideoItem] = [:]
                let count = fetchResult.count
                for i in 0..<count {
                    let asset = fetchResult.object(at: i)
                    guard asset.mediaType == .video else { continue }
                    idToItem[asset.localIdentifier] = VideoItem(
                        id: asset.localIdentifier,
                        asset: asset,
                        creationDate: asset.creationDate,
                        duration: asset.duration
                    )
                }
                let result = identifiers.compactMap { idToItem[$0] }
                DispatchQueue.main.async {
                    continuation.resume(returning: result)
                }
            }
        }
    }

    /// Available calendar years that have photos, with counts (for "By year" scope UI).
    func fetchYearsWithCounts() async -> [(year: Int, count: Int)] {
        await withCheckedContinuation { continuation in
            queue.async {
                let options = PHFetchOptions()
                options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
                options.fetchLimit = 0
                let fetchResult = PHAsset.fetchAssets(with: .image, options: options)
                var yearCounts: [Int: Int] = [:]
                let cal = Calendar.current
                let count = fetchResult.count
                for i in 0..<count {
                    let asset = fetchResult.object(at: i)
                    guard let date = asset.creationDate else { continue }
                    let y = cal.component(.year, from: date)
                    yearCounts[y, default: 0] += 1
                }
                let sorted = yearCounts.sorted(by: { $0.key > $1.key }).map { (year: $0.key, count: $0.value) }
                DispatchQueue.main.async {
                    continuation.resume(returning: sorted)
                }
            }
        }
    }

    /// Fetch screenshot assets (from Screenshots smart album) for the given scope.
    func fetchScreenshots(scope: ScanScope) async throws -> [PhotoItem] {
        return await withCheckedContinuation { continuation in
            let scopeCopy = scope
            queue.async {
                let scopePredicate = Self.makeImageScopePredicate(scope: scopeCopy)
                let collections = PHAssetCollection.fetchAssetCollections(
                    with: .smartAlbum,
                    subtype: .smartAlbumScreenshots,
                    options: nil
                )
                var result: [PhotoItem] = []
                let collectionCount = collections.count
                for ci in 0..<collectionCount {
                    let collection = collections.object(at: ci)
                    let options = PHFetchOptions()
                    options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                    options.predicate = scopePredicate
                    let assets = PHAsset.fetchAssets(in: collection, options: options)
                    let assetCount = assets.count
                    for ai in 0..<assetCount {
                        let asset = assets.object(at: ai)
                        result.append(PhotoItem(
                            id: asset.localIdentifier,
                            asset: asset,
                            creationDate: asset.creationDate
                        ))
                    }
                }
                DispatchQueue.main.async {
                    continuation.resume(returning: result)
                }
            }
        }
    }

    /// Fetch video assets for the given scope, sorted by duration descending (longest first).
    func fetchVideos(scope: ScanScope) async throws -> [VideoItem] {
        let scopeCopy = scope
        return await withCheckedContinuation { continuation in
            queue.async {
                let predicate = Self.makeVideoScopePredicate(scope: scopeCopy)
                let options = PHFetchOptions()
                options.sortDescriptors = [
                    NSSortDescriptor(key: "duration", ascending: false),
                    NSSortDescriptor(key: "creationDate", ascending: false)
                ]
                options.predicate = predicate
                options.fetchLimit = 0
                let fetchResult = PHAsset.fetchAssets(with: .video, options: options)
                let count = fetchResult.count
                var result: [VideoItem] = []
                result.reserveCapacity(count)
                for i in 0..<count {
                    let asset = fetchResult.object(at: i)
                    result.append(VideoItem(
                        id: asset.localIdentifier,
                        asset: asset,
                        creationDate: asset.creationDate,
                        duration: asset.duration
                    ))
                }
                DispatchQueue.main.async {
                    continuation.resume(returning: result)
                }
            }
        }
    }

    /// Videos whose **estimated** size is at least `minEstimatedBytes`, largest first.
    /// Size uses `PHAsset.estimatedStorageBytes` (bitrate heuristic for video — good for ranking, not exact on-disk bytes).
    func fetchLargeVideos(scope: ScanScope, minEstimatedBytes: Int64 = 2 * 1024 * 1024) async throws -> [VideoItem] {
        let all = try await fetchVideos(scope: scope)
        return all
            .filter { $0.asset.estimatedStorageBytes >= minEstimatedBytes }
            .sorted { $0.asset.estimatedStorageBytes > $1.asset.estimatedStorageBytes }
    }

    /// Builds video scope predicate. Static so it can be used from nonisolated queue.
    private static func makeVideoScopePredicate(scope: ScanScope) -> NSPredicate {
        let mediaPredicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
        let cal = Calendar.current
        let now = Date()
        switch scope {
        case .recent(let days):
            guard let from = cal.date(byAdding: .day, value: -days, to: now) else { return mediaPredicate }
            let datePredicate = NSPredicate(format: "creationDate >= %@", from as NSDate)
            return NSCompoundPredicate(andPredicateWithSubpredicates: [mediaPredicate, datePredicate])
        case .thisMonth:
            guard let start = cal.date(from: cal.dateComponents([.year, .month], from: now)),
                  let end = cal.date(byAdding: .month, value: 1, to: start) else { return mediaPredicate }
            let datePredicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@", start as NSDate, end as NSDate)
            return NSCompoundPredicate(andPredicateWithSubpredicates: [mediaPredicate, datePredicate])
        case .thisYear:
            guard let start = cal.date(from: cal.dateComponents([.year], from: now)),
                  let end = cal.date(byAdding: .year, value: 1, to: start) else { return mediaPredicate }
            let datePredicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@", start as NSDate, end as NSDate)
            return NSCompoundPredicate(andPredicateWithSubpredicates: [mediaPredicate, datePredicate])
        case .year(let y):
            guard let start = cal.date(from: DateComponents(year: y, month: 1, day: 1)),
                  let end = cal.date(byAdding: .year, value: 1, to: start) else { return mediaPredicate }
            let datePredicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@", start as NSDate, end as NSDate)
            return NSCompoundPredicate(andPredicateWithSubpredicates: [mediaPredicate, datePredicate])
        case .custom(let from, let to):
            let datePredicate = NSPredicate(format: "creationDate >= %@ AND creationDate <= %@", from as NSDate, to as NSDate)
            return NSCompoundPredicate(andPredicateWithSubpredicates: [mediaPredicate, datePredicate])
        case .entireLibrary:
            return mediaPredicate
        }
    }

    /// Builds image scope predicate. Static so it can be used from nonisolated queue without capturing NSPredicate across isolation.
    private static func makeImageScopePredicate(scope: ScanScope) -> NSPredicate {
        let mediaPredicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        let cal = Calendar.current
        let now = Date()

        switch scope {
        case .recent(let days):
            guard let from = cal.date(byAdding: .day, value: -days, to: now) else {
                return mediaPredicate
            }
            // Include undated assets (Simulator / imports sometimes leave creationDate nil); otherwise “Recent” scans miss them.
            let since = NSPredicate(format: "creationDate >= %@", from as NSDate)
            let undated = NSPredicate(format: "creationDate == nil")
            let datePredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [since, undated])
            return NSCompoundPredicate(andPredicateWithSubpredicates: [mediaPredicate, datePredicate])

        case .thisMonth:
            guard let start = cal.date(from: cal.dateComponents([.year, .month], from: now)),
                  let end = cal.date(byAdding: .month, value: 1, to: start) else {
                return mediaPredicate
            }
            let datePredicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@", start as NSDate, end as NSDate)
            return NSCompoundPredicate(andPredicateWithSubpredicates: [mediaPredicate, datePredicate])

        case .thisYear:
            guard let start = cal.date(from: cal.dateComponents([.year], from: now)),
                  let end = cal.date(byAdding: .year, value: 1, to: start) else {
                return mediaPredicate
            }
            let datePredicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@", start as NSDate, end as NSDate)
            return NSCompoundPredicate(andPredicateWithSubpredicates: [mediaPredicate, datePredicate])

        case .year(let y):
            guard let start = cal.date(from: DateComponents(year: y, month: 1, day: 1)),
                  let end = cal.date(byAdding: .year, value: 1, to: start) else {
                return mediaPredicate
            }
            let datePredicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@", start as NSDate, end as NSDate)
            return NSCompoundPredicate(andPredicateWithSubpredicates: [mediaPredicate, datePredicate])

        case .custom(let from, let to):
            let datePredicate = NSPredicate(format: "creationDate >= %@ AND creationDate <= %@", from as NSDate, to as NSDate)
            return NSCompoundPredicate(andPredicateWithSubpredicates: [mediaPredicate, datePredicate])

        case .entireLibrary:
            return mediaPredicate
        }
    }

    private func buildPredicate(scope: ScanScope) -> NSPredicate {
        Self.makeImageScopePredicate(scope: scope)
    }

    /// Load a single image for display (thumbnail or full).
    /// With `.opportunistic`, Photos often calls the handler more than once (degraded placeholder, then full image after iCloud fetch).
    /// Resuming the continuation on the first callback yields `nil` or tiny previews for cloud-only assets; wait for non‑degraded delivery.
    func loadImage(
        for asset: PHAsset,
        targetSize: CGSize,
        contentMode: PHImageContentMode = .aspectFill
    ) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let oneShot = OneShotContinuation(continuation)
            Task {
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                oneShot.resume(returning: nil)
            }
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            options.resizeMode = .fast
            imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: contentMode,
                options: options
            ) { image, info in
                if (info?[PHImageCancelledKey] as? Bool) == true {
                    oneShot.resume(returning: nil)
                    return
                }
                if info?[PHImageErrorKey] != nil {
                    oneShot.resume(returning: nil)
                    return
                }
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if degraded {
                    return
                }
                oneShot.resume(returning: image)
            }
        }
    }

    /// Builds an `AVPlayer` for reviewing a video before delete. Uses Photos’ AVAsset (supports iCloud download).
    func loadAVPlayerForVideoPreview(asset: PHAsset) async -> AVPlayer? {
        guard asset.mediaType == .video else { return nil }
        return await withCheckedContinuation { continuation in
            let once = ResumeOnceAVPlayerContinuation(continuation)
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .automatic
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                Task { @MainActor in
                    guard let avAsset else {
                        once.resume(nil)
                        return
                    }
                    let player = AVPlayer(playerItem: AVPlayerItem(asset: avAsset))
                    once.resume(player)
                }
            }
        }
    }

    /// Load full-size image for preview (high quality). Use for magnifying-glass full-screen view.
    /// If full-size decode fails (e.g. PHPhotosErrorDomain 3303), tries a large bounded size so user still sees the photo.
    func loadFullSizeImageForPreview(for asset: PHAsset) async -> UIImage? {
        let fullSize = await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            let oneShot = OneShotContinuation(continuation)
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            options.resizeMode = .none
            imageManager.requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                oneShot.resume(returning: image)
            }
        }
        if fullSize != nil { return fullSize }
        // Fallback: request a large but bounded size (e.g. 2048) to avoid decode failures on some assets (3303).
        let fallbackSize = CGSize(width: 2048, height: 2048)
        return await loadImage(for: asset, targetSize: fallbackSize, contentMode: .aspectFit)
    }

    /// Load full-size CGImage for Vision processing (e.g. duplicate/similarity).
    /// Photos may call the completion multiple times; we resume only once.
    func loadFullSizeImage(for asset: PHAsset) async -> CGImage? {
        await withCheckedContinuation { continuation in
            let oneShot = OneShotContinuation(continuation)
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            imageManager.requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                let cg = image?.cgImage
                oneShot.resume(returning: cg)
            }
        }
    }

    /// Load a downscaled CGImage for Vision (feature-print, quality, junk). Never full-size—keeps memory safe.
    /// Uses targetLongEdge (e.g. 1024) on the longer side. When asset dimensions are unknown, uses 1024×1024.
    ///
    /// **Not** the same policy as ``loadImage(for:targetSize:contentMode:)``: UI waits for non‑degraded so iCloud thumbnails resolve;
    /// scans touch thousands of assets, so we accept the **first non‑nil** opportunistic delivery (often “degraded” but good enough at ~1024px)
    /// and still wait through `nil` + degraded while iCloud fetches.
    func loadImageForVision(for asset: PHAsset, targetLongEdge: CGFloat = 1024) async -> CGImage? {
        let pixelWidth = asset.pixelWidth
        let pixelHeight = asset.pixelHeight
        let targetSize: CGSize
        if pixelWidth > 0, pixelHeight > 0 {
            let longEdge = CGFloat(max(pixelWidth, pixelHeight))
            let scale: CGFloat = longEdge > targetLongEdge ? targetLongEdge / longEdge : 1
            targetSize = CGSize(
                width: CGFloat(pixelWidth) * scale,
                height: CGFloat(pixelHeight) * scale
            )
        } else {
            targetSize = CGSize(width: targetLongEdge, height: targetLongEdge)
        }

        return await withCheckedContinuation { continuation in
            let oneShot = OneShotContinuation(continuation)
            Task {
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                oneShot.resume(returning: nil)
            }
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            options.resizeMode = .fast
            imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                if (info?[PHImageCancelledKey] as? Bool) == true {
                    oneShot.resume(returning: nil)
                    return
                }
                if info?[PHImageErrorKey] != nil {
                    oneShot.resume(returning: nil)
                    return
                }
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if let image {
                    if let cg = Self.cgImageForVision(from: image, maxLongEdge: Int(ceil(targetLongEdge))) {
                        oneShot.resume(returning: cg)
                        return
                    }
                    if !degraded {
                        oneShot.resume(returning: nil)
                    }
                    return
                }
                if !degraded {
                    oneShot.resume(returning: nil)
                }
            }
        }
    }

    /// Bitmap for Vision: prefer `UIImage.cgImage`; otherwise CI rasterize (Photos sometimes returns CI-backed images with `cgImage == nil`).
    private static func cgImageForVision(from image: UIImage, maxLongEdge: Int) -> CGImage? {
        if let cg = image.cgImage {
            return cg
        }
        return rasterizeCIForVision(uiImage: image, maxLongEdge: maxLongEdge)
    }

    private static func rasterizeCIForVision(uiImage: UIImage, maxLongEdge: Int) -> CGImage? {
        guard let ci = CIImage(image: uiImage) else { return nil }
        var extent = ci.extent
        guard extent.width.isFinite, extent.height.isFinite, extent.width > 0, extent.height > 0 else { return nil }
        if extent.origin.x != 0 || extent.origin.y != 0 {
            extent = ci.extent.integral
        }
        let long = max(extent.width, extent.height)
        let cap = CGFloat(max(32, maxLongEdge))
        let scale: CGFloat = long > cap ? cap / long : 1
        let scaled = scale == 1 ? ci : ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let outRect = scaled.extent.integral
        guard outRect.width >= 1, outRect.height >= 1 else { return nil }
        let ctx = CIContext(options: [CIContextOption.useSoftwareRenderer: false])
        return ctx.createCGImage(scaled, from: outRect)
    }

    /// Reduces memory pressure by clearing the image manager cache. Call when starting a heavy scan.
    func clearImageCache() {
        imageManager.stopCachingImagesForAllAssets()
    }

    /// Move assets to Recently Deleted (user must confirm in UI).
    func deleteAssets(_ assets: [PHAsset]) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        }
    }

    /// Extract Vision feature prints for similarity/duplicate detection. Shared by DuplicateDetectionService and SimilarGroupingService.
    func extractFeaturePrints(
        for items: [PhotoItem],
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async -> [String: VNFeaturePrintObservation] {
        var result: [String: VNFeaturePrintObservation] = [:]
        let total = items.count
        let throttleInterval = 50
        for (index, item) in items.enumerated() {
            if (index + 1) % throttleInterval == 0 {
                await ScaleThrottle.yieldIfNeeded()
            }
            if let cgImage = await loadImageForVision(for: item.asset),
               let obs = try? await generateFeaturePrint(cgImage: cgImage) {
                result[item.id] = obs
            }
            progress?(index + 1, total)
        }
        return result
    }

    /// Runs Vision off the main actor. `VNImageRequestHandler.perform` is synchronous and heavy; doing it on `@MainActor` services could fail or starve the runloop when mixed with Photos callbacks.
    func generateFeaturePrint(cgImage: CGImage) async throws -> VNFeaturePrintObservation? {
        try await Self.runFeaturePrintRequest(cgImage: cgImage)
    }

    private static func runFeaturePrintRequest(cgImage: CGImage) async throws -> VNFeaturePrintObservation? {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<VNFeaturePrintObservation?, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let request = VNGenerateImageFeaturePrintRequest()
                    request.revision = VNGenerateImageFeaturePrintRequestRevision2
                    // Simulator Metal path can return bogus constant distances (~20) from `computeDistance`; CPU matches device behavior (Apple Dev Forums).
                    #if targetEnvironment(simulator)
                    request.usesCPUOnly = true
                    #endif
                    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                    try handler.perform([request])
                    let obs = request.results?.first as? VNFeaturePrintObservation
                    continuation.resume(returning: obs)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

// MARK: - Storage size estimation

extension PHAsset {
    /// Estimated bytes on disk. Photos: ~0.4 bytes/pixel (realistic for HEIC/JPEG).
    /// Videos: duration × ~2 Mbps. The old formula (pixels × 3) overestimated by ~8×.
    var estimatedStorageBytes: Int64 {
        if mediaType == .video {
            let durationSec = max(1, duration)
            return Int64(durationSec * 2_000_000 / 8)  // ~2 Mbps → bytes
        }
        let pixels = Int64(pixelWidth) * Int64(pixelHeight)
        guard pixels > 0 else { return 0 }
        return Int64(Double(pixels) * 0.4)  // HEIC/JPEG typical compression
    }
}
