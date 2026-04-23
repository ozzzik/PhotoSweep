//
//  SimilarGroupingService.swift
//  PhotosCleanup
//
//  Groups photos by calendar week (same “time bucket”) then visual similarity (Vision feature prints).
//

import Foundation
import Vision
import Photos

/// A group of photos from the same calendar week that are visually similar (same scene/event).
struct SimilarGroup: Identifiable, Sendable {
    let id: String
    let date: Date
    let items: [PhotoItem]
    var suggestedBestIndex: Int?

    static func groupId(date: Date, itemIds: [String]) -> String {
        let day = Calendar.current.startOfDay(for: date)
        return "\(day.timeIntervalSince1970)-\(itemIds.sorted().joined(separator: "-"))"
    }
}

@MainActor
final class SimilarGroupingService: ObservableObject {
    private let photoLibrary: PhotoLibraryService

    init(photoLibrary: PhotoLibraryService) {
        self.photoLibrary = photoLibrary
    }

    /// Group photos by **calendar week** (not strict same day), then within each week cluster by visual similarity.
    /// Week bucketing catches multi-day events and simulator seeds with different `creationDate` days.
    /// Pass `precomputedFeaturePrints` to reuse pre-computed prints (avoids re-running Vision).
    func groupSimilarSameDay(
        photos: [PhotoItem],
        precomputedFeaturePrints: [String: VNFeaturePrintObservation]? = nil,
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> [SimilarGroup] {
        ScanDebugLogger.start("groupSimilarByWeek", scope: "\(photos.count) photos")
        let t0 = Date()
        let cal = Calendar.current
        let byWeek = Dictionary(grouping: photos) { item -> Date in
            let d = item.creationDate ?? .distantPast
            if let interval = cal.dateInterval(of: .weekOfYear, for: d) {
                return interval.start
            }
            return cal.startOfDay(for: d)
        }
        var allGroups: [SimilarGroup] = []
        var processedBeforeBucket = 0
        let total = photos.count
        for (_, weekPhotos) in byWeek where weekPhotos.count >= 2 {
            let groups = await clusterBySimilarity(weekPhotos, featurePrints: precomputedFeaturePrints) { doneInBucket in
                progress?(processedBeforeBucket + doneInBucket, total)
            }
            processedBeforeBucket += weekPhotos.count
            progress?(min(processedBeforeBucket, total), total)
            for group in groups {
                let date = group.items.compactMap(\.creationDate).first ?? .distantPast
                allGroups.append(SimilarGroup(
                    id: SimilarGroup.groupId(date: date, itemIds: group.items.map(\.id)),
                    date: date,
                    items: group.items,
                    suggestedBestIndex: nil
                ))
            }
        }
        let result = allGroups.sorted { ($0.date, $0.items.count) > ($1.date, $1.items.count) }
        ScanDebugLogger.finish("groupSimilarByWeek", duration: Date().timeIntervalSince(t0), summary: "\(result.count) groups from \(byWeek.count) weeks")
        return result
    }

    private func clusterBySimilarity(
        _ items: [PhotoItem],
        featurePrints: [String: VNFeaturePrintObservation]? = nil,
        progress: (@Sendable (Int) -> Void)?
    ) async -> [SimilarGroup] {
        var prints: [String: VNFeaturePrintObservation]
        if let precomputed = featurePrints {
            prints = precomputed
            progress?(items.count)
        } else {
            prints = [:]
            let throttleInterval = 25
            for (i, item) in items.enumerated() {
                if (i + 1) % throttleInterval == 0 {
                    await ScaleThrottle.yieldIfNeeded()
                }
                if let cgImage = await photoLibrary.loadImageForVision(for: item.asset),
                   let obs = try? await photoLibrary.generateFeaturePrint(cgImage: cgImage) {
                    prints[item.id] = obs
                }
                progress?(i + 1)
            }
        }
        let n = items.count
        let uf = IndexUnionFind(count: n)
        for i in 0..<n {
            guard let fpA = prints[items[i].id] else { continue }
            for j in (i + 1)..<n {
                guard let fpB = prints[items[j].id] else { continue }
                var distance: Float = 0
                try? fpA.computeDistance(&distance, to: fpB)
                if distance <= AppConfig.similarSameDayVisionMaxDistance {
                    uf.union(i, j)
                }
            }
        }
        var rootBuckets: [Int: [(Int, PhotoItem)]] = [:]
        for i in 0..<n {
            guard prints[items[i].id] != nil else { continue }
            let r = uf.find(i)
            rootBuckets[r, default: []].append((i, items[i]))
        }
        var clusters: [[PhotoItem]] = []
        for (_, members) in rootBuckets where members.count >= 2 {
            clusters.append(members.sorted { $0.0 < $1.0 }.map(\.1))
        }
        return clusters.map { items in
            SimilarGroup(
                id: SimilarGroup.groupId(date: items.compactMap(\.creationDate).first ?? .distantPast, itemIds: items.map(\.id)),
                date: items.compactMap(\.creationDate).first ?? .distantPast,
                items: items,
                suggestedBestIndex: nil
            )
        }
    }
}
