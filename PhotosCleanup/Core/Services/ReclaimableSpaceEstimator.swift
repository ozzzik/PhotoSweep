//
//  ReclaimableSpaceEstimator.swift
//  PhotosCleanup
//
//  Sums estimated bytes for “extra” photos if you keep only the suggested best per group.
//

import Foundation

enum ReclaimableSpaceEstimator {
    /// Upper bound on reclaimable space: sum of non–keep assets in each duplicate cluster and similar group.
    /// Uses `PHAsset.estimatedStorageBytes` (heuristic). Nothing is deleted automatically.
    static func estimateBytes(duplicateClusters: [DuplicateCluster], similarGroups: [SimilarGroup]) -> Int64 {
        var total: Int64 = 0
        for c in duplicateClusters {
            total += estimateBytesForDuplicateCluster(c)
        }
        for g in similarGroups {
            total += estimateBytesForSimilarGroup(g)
        }
        return total
    }

    private static func estimateBytesForDuplicateCluster(_ c: DuplicateCluster) -> Int64 {
        guard c.items.count >= 2 else { return 0 }
        let keep = keepIndexDuplicate(c)
        return sumBytesExcludingKeep(c.items, keepIndex: keep)
    }

    private static func estimateBytesForSimilarGroup(_ g: SimilarGroup) -> Int64 {
        guard g.items.count >= 2 else { return 0 }
        let keep = keepIndexSimilar(g)
        return sumBytesExcludingKeep(g.items, keepIndex: keep)
    }

    private static func sumBytesExcludingKeep(_ items: [PhotoItem], keepIndex: Int) -> Int64 {
        var sum: Int64 = 0
        for i in items.indices where i != keepIndex {
            sum += items[i].asset.estimatedStorageBytes
        }
        return sum
    }

    private static func keepIndexDuplicate(_ c: DuplicateCluster) -> Int {
        if let k = c.suggestedKeepIndex, c.items.indices.contains(k) { return k }
        return 0
    }

    private static func keepIndexSimilar(_ g: SimilarGroup) -> Int {
        if let k = g.suggestedBestIndex, g.items.indices.contains(k) { return k }
        return 0
    }
}

// MARK: - Default selection in detail (best = keep / green, others = remove / red)

enum GroupDefaultRemovalSelection {
    /// Indices to mark for removal: every photo except the suggested keeper.
    static func indicesToRemove(for cluster: DuplicateCluster) -> Set<Int> {
        guard cluster.items.count >= 2 else { return [] }
        let keep: Int
        if let k = cluster.suggestedKeepIndex, cluster.items.indices.contains(k) {
            keep = k
        } else {
            keep = 0
        }
        return Set(cluster.items.indices.filter { $0 != keep })
    }

    static func indicesToRemove(for group: SimilarGroup) -> Set<Int> {
        guard group.items.count >= 2 else { return [] }
        let keep: Int
        if let k = group.suggestedBestIndex, group.items.indices.contains(k) {
            keep = k
        } else {
            keep = 0
        }
        return Set(group.items.indices.filter { $0 != keep })
    }
}
