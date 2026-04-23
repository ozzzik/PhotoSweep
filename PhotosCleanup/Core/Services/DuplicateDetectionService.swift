//
//  DuplicateDetectionService.swift
//  PhotosCleanup
//
//  Finds duplicate/similar images using Vision VNGenerateImageFeaturePrintRequest.
//  Can be extended with perceptual hashing (pHash/dHash) for extra speed on first pass.
//

import Foundation
import Vision
import Photos

/// A cluster of photos that are duplicates or near-duplicates of each other.
struct DuplicateCluster: Identifiable, Sendable {
    let id: String
    let items: [PhotoItem]
    var suggestedKeepIndex: Int? // index in items for "best" photo

    static func clusterId(from items: [PhotoItem]) -> String {
        items.map(\.id).sorted().joined(separator: "-")
    }
}

@MainActor
final class DuplicateDetectionService: ObservableObject {
    private let photoLibrary: PhotoLibraryService

    init(photoLibrary: PhotoLibraryService) {
        self.photoLibrary = photoLibrary
    }

    /// Run duplicate detection on the given photos. Returns clusters of duplicates.
    /// Pass `precomputedFeaturePrints` to reuse pre-computed prints (avoids re-running Vision).
    func findDuplicates(
        in photos: [PhotoItem],
        precomputedFeaturePrints: [String: VNFeaturePrintObservation]? = nil,
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> [DuplicateCluster] {
        ScanDebugLogger.start("findDuplicates", scope: "\(photos.count) photos")
        let t0 = Date()
        var featurePrints: [String: VNFeaturePrintObservation]
        if let precomputed = precomputedFeaturePrints {
            featurePrints = precomputed
            progress?(photos.count, photos.count)
            ScanDebugLogger.logPhase("  featurePrints", duration: 0, extra: "\(featurePrints.count)/\(photos.count) reused")
        } else {
            featurePrints = [:]
            let total = photos.count
            let throttleInterval = 50
            for (index, item) in photos.enumerated() {
                if (index + 1) % throttleInterval == 0 {
                    await ScaleThrottle.yieldIfNeeded()
                }
                if let cgImage = await photoLibrary.loadImageForVision(for: item.asset),
                   let observation = try? await photoLibrary.generateFeaturePrint(cgImage: cgImage) {
                    featurePrints[item.id] = observation
                }
                progress?(index + 1, total)
            }
            ScanDebugLogger.logPhase("  featurePrints", duration: Date().timeIntervalSince(t0), extra: "\(featurePrints.count)/\(photos.count) extracted")
        }

        // Cluster by similarity: union-find so A≈B and B≈C merge even when A≈C is above threshold (star-shaped seeding misses chains).
        let t1 = Date()
        let total = photos.count
        let n = photos.count
        let uf = IndexUnionFind(count: n)
        for i in 0..<n {
            guard let fpA = featurePrints[photos[i].id] else { continue }
            for j in (i + 1)..<n {
                guard let fpB = featurePrints[photos[j].id] else { continue }
                var distance: Float = 0
                try? fpA.computeDistance(&distance, to: fpB)
                if distance <= AppConfig.duplicateVisionMaxDistance {
                    uf.union(i, j)
                }
            }
        }
        var rootBuckets: [Int: [(Int, PhotoItem)]] = [:]
        for i in 0..<n {
            guard featurePrints[photos[i].id] != nil else { continue }
            let r = uf.find(i)
            rootBuckets[r, default: []].append((i, photos[i]))
        }
        var clusters: [DuplicateCluster] = []
        for (_, members) in rootBuckets where members.count >= 2 {
            let sorted = members.sorted { $0.0 < $1.0 }.map(\.1)
            clusters.append(DuplicateCluster(
                id: DuplicateCluster.clusterId(from: sorted),
                items: sorted,
                suggestedKeepIndex: nil
            ))
        }
        ScanDebugLogger.logPhase("  clustering", duration: Date().timeIntervalSince(t1), extra: "\(clusters.count) clusters")
        ScanDebugLogger.finish("findDuplicates", duration: Date().timeIntervalSince(t0), summary: "\(clusters.count) clusters from \(total) photos")
        return clusters
    }
}
