//
//  ScanResultStore.swift
//  PhotosCleanup
//
//  Persists duplicate clusters and similar groups so users can view last scan
//  after app restart without re-scanning.
//

import Foundation

/// Codable snapshot of scan results for persistence. Stores asset IDs only;
/// PHAssets are re-fetched when loading.
struct PersistedScanResult: Codable, Sendable {
    var scannedAt: Date
    var scope: PersistedScanScope?
    var duplicateScope: PersistedScanScope?
    var similarScope: PersistedScanScope?
    var config: PersistedScanConfig?
    var duplicateClusters: [PersistedDuplicateCluster]
    var similarGroups: [PersistedSimilarGroup]
}

struct PersistedDuplicateCluster: Codable, Sendable {
    var id: String
    var assetIds: [String]
    var suggestedKeepIndex: Int?
}

struct PersistedSimilarGroup: Codable, Sendable {
    var id: String
    var date: Date
    var assetIds: [String]
    var suggestedBestIndex: Int?
}

struct PersistedScanConfig: Codable, Sendable {
    var scope: PersistedScanScope
    var enabledModes: [String]
    var protectFavorites: Bool
    var excludeSharedAlbums: Bool
}

/// Codable representation of ScanScope.
enum PersistedScanScope: Codable, Sendable {
    case recent(days: Int)
    case thisMonth
    case thisYear
    case year(Int)
    case custom(from: Date, to: Date)
    case entireLibrary

    init(from scope: ScanScope) {
        switch scope {
        case .recent(let days): self = .recent(days: days)
        case .thisMonth: self = .thisMonth
        case .thisYear: self = .thisYear
        case .year(let y): self = .year(y)
        case .custom(let from, let to): self = .custom(from: from, to: to)
        case .entireLibrary: self = .entireLibrary
        }
    }

    func toScanScope() -> ScanScope {
        switch self {
        case .recent(let days): return .recent(days: days)
        case .thisMonth: return .thisMonth
        case .thisYear: return .thisYear
        case .year(let y): return .year(y)
        case .custom(let from, let to): return .custom(from: from, to: to)
        case .entireLibrary: return .entireLibrary
        }
    }
}

@MainActor
final class ScanResultStore: ObservableObject {
    private let defaults = UserDefaults.standard

    private enum Key {
        static let lastScanResult = "scanResultStore.lastScanResult"
    }

    /// Save scan result for later restoration.
    func save(_ result: PersistedScanResult) {
        guard let data = try? JSONEncoder().encode(result) else { return }
        defaults.set(data, forKey: Key.lastScanResult)
    }

    /// Load persisted scan result, if any.
    func load() -> PersistedScanResult? {
        guard let data = defaults.data(forKey: Key.lastScanResult),
              let result = try? JSONDecoder().decode(PersistedScanResult.self, from: data) else { return nil }
        return result
    }

    /// Clear persisted results (e.g. when user explicitly clears).
    func clear() {
        defaults.removeObject(forKey: Key.lastScanResult)
    }
}

// MARK: - Reviewed groups (user has visited / made a decision)

private enum ReviewedKey {
    static let duplicateClusterIds = "scanResultStore.reviewedDuplicateClusterIds"
    static let similarGroupIds = "scanResultStore.reviewedSimilarGroupIds"
}

extension ScanResultStore {
    func loadReviewedDuplicateClusterIds() -> Set<String> {
        guard let arr = defaults.array(forKey: ReviewedKey.duplicateClusterIds) as? [String] else { return [] }
        return Set(arr)
    }

    func loadReviewedSimilarGroupIds() -> Set<String> {
        guard let arr = defaults.array(forKey: ReviewedKey.similarGroupIds) as? [String] else { return [] }
        return Set(arr)
    }

    func markDuplicateClusterReviewed(_ id: String) {
        var ids = loadReviewedDuplicateClusterIds()
        ids.insert(id)
        defaults.set(Array(ids), forKey: ReviewedKey.duplicateClusterIds)
    }

    func markSimilarGroupReviewed(_ id: String) {
        var ids = loadReviewedSimilarGroupIds()
        ids.insert(id)
        defaults.set(Array(ids), forKey: ReviewedKey.similarGroupIds)
    }
}

// MARK: - Screened photos (premium: persists across scans)

private enum ScreenedAssetKey {
    static let assetIds = "scanResultStore.premiumScreenedAssetIds"
}

extension ScanResultStore {
    /// Asset `localIdentifier`s the user has opened in duplicate/similar detail (premium — survives new scans).
    func loadScreenedAssetIds() -> Set<String> {
        guard let arr = defaults.array(forKey: ScreenedAssetKey.assetIds) as? [String] else { return [] }
        return Set(arr)
    }

    func unionScreenedAssetIds(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        var existing = loadScreenedAssetIds()
        let before = existing.count
        existing.formUnion(ids)
        guard existing.count != before else { return }
        defaults.set(Array(existing), forKey: ScreenedAssetKey.assetIds)
    }

    func clearScreenedAssetIds() {
        defaults.removeObject(forKey: ScreenedAssetKey.assetIds)
    }
}
