//
//  LastSmartScanResult.swift
//  PhotosCleanup
//
//  Shared result from the last smart scan so Duplicates and Similar tabs can show it.
//  Persists to disk so results survive app restart (premium only).
//

import Foundation

@MainActor
final class LastSmartScanResult: ObservableObject {
    @Published var scope: ScanScope?
    @Published var duplicateScope: ScanScope?
    @Published var similarScope: ScanScope?
    @Published var duplicateClusters: [DuplicateCluster] = [] {
        didSet {
            savePersisted()
            recomputeReclaimableEstimate()
        }
    }
    @Published var similarDayGroups: [SimilarGroup] = [] {
        didSet {
            savePersisted()
            recomputeReclaimableEstimate()
        }
    }
    @Published var config: ScanConfig?
    @Published var isLoadingPersisted = false

    /// Sum of estimated bytes for non–“best” photos across current duplicate + similar results (heuristic).
    @Published private(set) var reclaimableEstimateBytes: Int64 = 0

    private let scanResultStore = ScanResultStore()
    private var hasLoadedPersistedOnce = false
    private weak var adManager: AdManager?

    private var isPremium: Bool { adManager?.isPremium == true }

    // Free tier keeps review markers session-only.
    private var reviewedDuplicateClusterIdsSession: Set<String> = []
    private var reviewedSimilarGroupIdsSession: Set<String> = []
    /// Free tier: asset IDs seen in duplicate/similar detail this session only (cleared on new scan).
    private var screenedAssetIdsSession: Set<String> = []

    init(adManager: AdManager? = nil) {
        self.adManager = adManager
    }

    var hasDuplicates: Bool { !duplicateClusters.isEmpty }
    var hasSimilar: Bool { !similarDayGroups.isEmpty }

    var reclaimableEstimateFormatted: String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: reclaimableEstimateBytes)
    }

    private func recomputeReclaimableEstimate() {
        reclaimableEstimateBytes = ReclaimableSpaceEstimator.estimateBytes(
            duplicateClusters: duplicateClusters,
            similarGroups: similarDayGroups
        )
    }

    /// IDs of duplicate clusters / similar groups the user has reviewed (visited detail view).
    var reviewedDuplicateClusterIds: Set<String> {
        if isPremium { return scanResultStore.loadReviewedDuplicateClusterIds() }
        return reviewedDuplicateClusterIdsSession
    }
    var reviewedSimilarGroupIds: Set<String> {
        if isPremium { return scanResultStore.loadReviewedSimilarGroupIds() }
        return reviewedSimilarGroupIdsSession
    }

    private var screenedAssetIds: Set<String> {
        if isPremium { return scanResultStore.loadScreenedAssetIds() }
        return screenedAssetIdsSession
    }

    /// True if any photo in the cluster was opened in detail on a **previous** scan (premium persists; free = same session).
    func anyPhotoPreviouslyScreened(in cluster: DuplicateCluster) -> Bool {
        let s = screenedAssetIds
        return cluster.items.contains { s.contains($0.id) }
    }

    /// Same as `anyPhotoPreviouslyScreened(in:)` for similar groups.
    func anyPhotoPreviouslyScreened(in group: SimilarGroup) -> Bool {
        let s = screenedAssetIds
        return group.items.contains { s.contains($0.id) }
    }

    func markDuplicateClusterReviewed(_ cluster: DuplicateCluster) {
        if isPremium {
            scanResultStore.markDuplicateClusterReviewed(cluster.id)
            scanResultStore.unionScreenedAssetIds(Set(cluster.items.map(\.id)))
        } else {
            reviewedDuplicateClusterIdsSession.insert(cluster.id)
            screenedAssetIdsSession.formUnion(cluster.items.map(\.id))
        }
        objectWillChange.send()
        adManager?.recordGroupScreening()
    }

    func markSimilarGroupReviewed(_ group: SimilarGroup) {
        if isPremium {
            scanResultStore.markSimilarGroupReviewed(group.id)
            scanResultStore.unionScreenedAssetIds(Set(group.items.map(\.id)))
        } else {
            reviewedSimilarGroupIdsSession.insert(group.id)
            screenedAssetIdsSession.formUnion(group.items.map(\.id))
        }
        objectWillChange.send()
        adManager?.recordGroupScreening()
    }

    /// Clears premium “seen before” asset memory (duplicate/similar detail visits). Does not remove saved scan results.
    func clearPremiumScreeningHistory() {
        guard isPremium else { return }
        scanResultStore.clearScreenedAssetIds()
        objectWillChange.send()
    }

    func set(from result: CleanupSessionResult) {
        reviewedDuplicateClusterIdsSession.removeAll()
        reviewedSimilarGroupIdsSession.removeAll()
        if !isPremium { screenedAssetIdsSession.removeAll() }
        scope = result.config.scope
        duplicateScope = result.config.scope
        similarScope = result.config.scope
        config = result.config
        duplicateClusters = result.duplicateClusters
        similarDayGroups = result.similarDayGroups
    }

    func setDuplicates(scope: ScanScope, clusters: [DuplicateCluster]) {
        reviewedDuplicateClusterIdsSession.removeAll()
        if !isPremium { screenedAssetIdsSession.removeAll() }
        self.scope = scope
        self.duplicateScope = scope
        self.duplicateClusters = clusters
    }

    func setSimilar(scope: ScanScope, groups: [SimilarGroup]) {
        reviewedSimilarGroupIdsSession.removeAll()
        if !isPremium { screenedAssetIdsSession.removeAll() }
        self.scope = scope
        self.similarScope = scope
        self.similarDayGroups = groups
    }

    func clearDuplicates() {
        reviewedDuplicateClusterIdsSession.removeAll()
        if !isPremium { screenedAssetIdsSession.removeAll() }
        duplicateClusters = []
    }

    func clearSimilar() {
        reviewedSimilarGroupIdsSession.removeAll()
        if !isPremium { screenedAssetIdsSession.removeAll() }
        similarDayGroups = []
    }

    /// Clear smart scan results for the current session (free tier after long background — see `AppConfig.freeTierBackgroundSessionResetSeconds`).
    func clearSessionSmartResults() {
        scope = nil
        duplicateScope = nil
        similarScope = nil
        config = nil
        duplicateClusters = []
        similarDayGroups = []
        reviewedDuplicateClusterIdsSession.removeAll()
        reviewedSimilarGroupIdsSession.removeAll()
        screenedAssetIdsSession.removeAll()
    }

    /// Load persisted scan result from disk and re-hydrate clusters from photo library.
    /// Only runs once per app launch.
    func loadPersisted(photoLibrary: PhotoLibraryService) async {
        guard !hasLoadedPersistedOnce else { return }
        guard isPremium else { return }
        hasLoadedPersistedOnce = true
        guard let persisted = scanResultStore.load() else { return }
        isLoadingPersisted = true
        defer { isLoadingPersisted = false }

        if let s = persisted.scope { scope = s.toScanScope() }
        if let s = persisted.duplicateScope { duplicateScope = s.toScanScope() }
        if let s = persisted.similarScope { similarScope = s.toScanScope() }

        if let c = persisted.config {
            config = ScanConfig(
                scope: c.scope.toScanScope(),
                enabledModes: Set(c.enabledModes.compactMap { CleanupMode(rawValue: $0) }),
                protectFavorites: c.protectFavorites,
                excludeSharedAlbums: c.excludeSharedAlbums
            )
        }

        var clusters: [DuplicateCluster] = []
        for p in persisted.duplicateClusters {
            let items = await photoLibrary.fetchPhotoItems(identifiers: p.assetIds)
            guard items.count >= 2 else { continue }
            let keepIdx: Int? = {
                guard let idx = p.suggestedKeepIndex, idx >= 0, idx < items.count else { return nil }
                return idx
            }()
            clusters.append(DuplicateCluster(id: p.id, items: items, suggestedKeepIndex: keepIdx))
        }
        duplicateClusters = clusters

        var groups: [SimilarGroup] = []
        for p in persisted.similarGroups {
            let items = await photoLibrary.fetchPhotoItems(identifiers: p.assetIds)
            guard items.count >= 2 else { continue }
            let bestIdx: Int? = {
                guard let idx = p.suggestedBestIndex, idx >= 0, idx < items.count else { return nil }
                return idx
            }()
            groups.append(SimilarGroup(id: p.id, date: p.date, items: items, suggestedBestIndex: bestIdx))
        }
        similarDayGroups = groups
    }

    private func savePersisted() {
        guard isPremium else { return }
        let persisted = PersistedScanResult(
            scannedAt: Date(),
            scope: scope.map { PersistedScanScope(from: $0) },
            duplicateScope: duplicateScope.map { PersistedScanScope(from: $0) },
            similarScope: similarScope.map { PersistedScanScope(from: $0) },
            config: config.map { c in
                PersistedScanConfig(
                    scope: PersistedScanScope(from: c.scope),
                    enabledModes: c.enabledModes.map(\.rawValue),
                    protectFavorites: c.protectFavorites,
                    excludeSharedAlbums: c.excludeSharedAlbums
                )
            },
            duplicateClusters: duplicateClusters.map { c in
                PersistedDuplicateCluster(
                    id: c.id,
                    assetIds: c.items.map(\.id),
                    suggestedKeepIndex: c.suggestedKeepIndex
                )
            },
            similarGroups: similarDayGroups.map { g in
                PersistedSimilarGroup(
                    id: g.id,
                    date: g.date,
                    assetIds: g.items.map(\.id),
                    suggestedBestIndex: g.suggestedBestIndex
                )
            }
        )
        scanResultStore.save(persisted)
    }
}
