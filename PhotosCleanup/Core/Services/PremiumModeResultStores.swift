//
//  PremiumModeResultStores.swift
//  PhotosCleanup
//
//  Persistence for premium-only "last results" in non-smart cleanup modes.
//  These stores are intentionally lightweight: they persist asset local identifiers
//  (and mode-specific parameters) so the UI can rehydrate on app restart.
//

import Foundation

final class UserDefaultsCodableStore<Value: Codable & Sendable> {
    private let defaults = UserDefaults.standard
    private let key: String

    init(key: String) {
        self.key = key
    }

    func save(_ value: Value) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    func load() -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}

struct PersistedAssetListSnapshot: Codable, Sendable {
    var scope: PersistedScanScope
    var assetIds: [String]
}

struct PersistedVideoListSnapshot: Codable, Sendable {
    var scope: PersistedScanScope
    var videoIds: [String]
    /// Added for size-threshold picker; `nil` = older saves (treat as 50 MB).
    var minEstimatedBytes: Int64?
}

struct PersistedLowQualitySnapshot: Codable, Sendable {
    var scope: PersistedScanScope
    var minAgeYears: Int
    var assetIds: [String]
}

struct PersistedTripWithAnalysisSnapshot: Codable, Sendable {
    var tripId: String
    var photoIds: [String]
    var startDate: Date
    var endDate: Date
    var clusters: [PersistedDuplicateCluster]
    var groups: [PersistedSimilarGroup]
}

struct PersistedTripsSnapshot: Codable, Sendable {
    var scope: PersistedScanScope
    var trips: [PersistedTripWithAnalysisSnapshot]
}

// MARK: - Screenshots

final class ScreenshotsResultStore: ObservableObject {
    private let store = UserDefaultsCodableStore<PersistedAssetListSnapshot>(key: "premiumModeStore.screenshots")

    func save(scope: ScanScope, assetIds: [String]) {
        store.save(PersistedAssetListSnapshot(scope: PersistedScanScope(from: scope), assetIds: assetIds))
    }

    func load() -> (scope: ScanScope, assetIds: [String])? {
        guard let snap = store.load() else { return nil }
        return (scope: snap.scope.toScanScope(), assetIds: snap.assetIds)
    }
}

// MARK: - Large videos

final class LargeVideosResultStore: ObservableObject {
    private let store = UserDefaultsCodableStore<PersistedVideoListSnapshot>(key: "premiumModeStore.largeVideos")

    func save(scope: ScanScope, videoIds: [String], minEstimatedBytes: Int64) {
        store.save(
            PersistedVideoListSnapshot(
                scope: PersistedScanScope(from: scope),
                videoIds: videoIds,
                minEstimatedBytes: minEstimatedBytes
            )
        )
    }

    func load() -> (scope: ScanScope, videoIds: [String], minEstimatedBytes: Int64?)? {
        guard let snap = store.load() else { return nil }
        return (scope: snap.scope.toScanScope(), videoIds: snap.videoIds, minEstimatedBytes: snap.minEstimatedBytes)
    }
}

// MARK: - Junk

final class JunkResultStore: ObservableObject {
    private let store = UserDefaultsCodableStore<PersistedAssetListSnapshot>(key: "premiumModeStore.junk")

    func save(scope: ScanScope, assetIds: [String]) {
        store.save(PersistedAssetListSnapshot(scope: PersistedScanScope(from: scope), assetIds: assetIds))
    }

    func load() -> (scope: ScanScope, assetIds: [String])? {
        guard let snap = store.load() else { return nil }
        return (scope: snap.scope.toScanScope(), assetIds: snap.assetIds)
    }
}

// MARK: - Blurry & accidental

final class BlurryAccidentalResultStore: ObservableObject {
    private let store = UserDefaultsCodableStore<PersistedAssetListSnapshot>(key: "premiumModeStore.blurryAccidental")

    func save(scope: ScanScope, assetIds: [String]) {
        store.save(PersistedAssetListSnapshot(scope: PersistedScanScope(from: scope), assetIds: assetIds))
    }

    func load() -> (scope: ScanScope, assetIds: [String])? {
        guard let snap = store.load() else { return nil }
        return (scope: snap.scope.toScanScope(), assetIds: snap.assetIds)
    }
}

// MARK: - Low quality

final class LowQualityResultStore: ObservableObject {
    private let store = UserDefaultsCodableStore<PersistedLowQualitySnapshot>(key: "premiumModeStore.lowQuality")

    func save(scope: ScanScope, minAgeYears: Int, assetIds: [String]) {
        store.save(PersistedLowQualitySnapshot(scope: PersistedScanScope(from: scope), minAgeYears: minAgeYears, assetIds: assetIds))
    }

    func load() -> (scope: ScanScope, minAgeYears: Int, assetIds: [String])? {
        guard let snap = store.load() else { return nil }
        return (scope: snap.scope.toScanScope(), minAgeYears: snap.minAgeYears, assetIds: snap.assetIds)
    }
}

// MARK: - Trips

final class TripsResultStore: ObservableObject {
    private let store = UserDefaultsCodableStore<PersistedTripsSnapshot>(key: "premiumModeStore.trips")

    func save(scope: ScanScope, trips: [TripWithAnalysis]) {
        let snapshots: [PersistedTripWithAnalysisSnapshot] = trips.map { twa in
            PersistedTripWithAnalysisSnapshot(
                tripId: twa.trip.id,
                photoIds: twa.trip.photos.map(\.id),
                startDate: twa.trip.startDate,
                endDate: twa.trip.endDate,
                clusters: twa.clusters.map { c in
                    PersistedDuplicateCluster(id: c.id, assetIds: c.items.map(\.id), suggestedKeepIndex: c.suggestedKeepIndex)
                },
                groups: twa.groups.map { g in
                    PersistedSimilarGroup(id: g.id, date: g.date, assetIds: g.items.map(\.id), suggestedBestIndex: g.suggestedBestIndex)
                }
            )
        }

        store.save(PersistedTripsSnapshot(scope: PersistedScanScope(from: scope), trips: snapshots))
    }

    func load() -> (scope: ScanScope, snapshots: [PersistedTripWithAnalysisSnapshot])? {
        guard let snap = store.load() else { return nil }
        return (scope: snap.scope.toScanScope(), snapshots: snap.trips)
    }
}

// MARK: - Manual swipe

final class ManualSwipeResultStore: ObservableObject {
    private let store = UserDefaultsCodableStore<PersistedAssetListSnapshot>(key: "premiumModeStore.manualSwipe")

    func save(scope: ScanScope, assetIds: [String]) {
        store.save(PersistedAssetListSnapshot(scope: PersistedScanScope(from: scope), assetIds: assetIds))
    }

    func load() -> (scope: ScanScope, assetIds: [String])? {
        guard let snap = store.load() else { return nil }
        return (scope: snap.scope.toScanScope(), assetIds: snap.assetIds)
    }
}

