//
//  CleanupOrchestrator.swift
//  PhotosCleanup
//
//  Coordinates scan scope + modes: fetch assets, run analysis, produce session for UI.
//

import Foundation
import Vision
@preconcurrency import Photos

/// High-level state of a cleanup session for the UI.
enum CleanupSessionPhase: Sendable {
    case idle
    case scanning(progress: ScanProgress)
    case results(CleanupSessionResult)
    case error(String)
}

/// Progress during scanning (for Scanning screen).
struct ScanProgress: Equatable, Sendable {
    var current: Int
    var total: Int
    var message: String
}

/// Result of a scan: duplicate clusters, similar groups, etc. (per enabled modes).
struct CleanupSessionResult: Sendable {
    var duplicateClusters: [DuplicateCluster] = []
    var similarDayGroups: [SimilarGroup] = []
    var config: ScanConfig
    var photosScanned: [PhotoItem] = []
}

@MainActor
final class CleanupOrchestrator: ObservableObject {
    @Published private(set) var phase: CleanupSessionPhase = .idle
    @Published private(set) var isPaused = false
    /// Last time a full scan completed (for retention / "Last scan" on Home).
    @Published private(set) var lastFullScanDate: Date?

    private let photoLibrary: PhotoLibraryService
    private let duplicateService: DuplicateDetectionService
    private let bestPhotoService: BestPhotoService
    private let similarGroupingService: SimilarGroupingService
    private let deletionManager: DeletionManager
    private let indexStore: IndexStore

    private var currentTask: Task<Void, Never>?
    private let progressSaveInterval = 50
    /// Progress is delivered via `Task { @MainActor }` per tick; without this, thousands of queued tasks can overwrite `.results` back to `.scanning` after the scan finishes.
    private var scanProgressDeliveryToken: UUID?

    init(
        photoLibrary: PhotoLibraryService,
        duplicateService: DuplicateDetectionService,
        bestPhotoService: BestPhotoService,
        similarGroupingService: SimilarGroupingService,
        deletionManager: DeletionManager,
        indexStore: IndexStore? = nil
    ) {
        self.photoLibrary = photoLibrary
        self.duplicateService = duplicateService
        self.bestPhotoService = bestPhotoService
        self.similarGroupingService = similarGroupingService
        self.deletionManager = deletionManager
        let store = indexStore ?? IndexStore()
        self.indexStore = store
        self.lastFullScanDate = store.lastFullScanDate
    }

    /// If a previous scan was interrupted, returns its state so UI can offer "Resume?" (resume not yet implemented).
    func loadInterruptedJobState() -> ScanJobState? {
        indexStore.loadScanJobState()
    }

    /// Start a new scan with the given config. Updates phase to .scanning then .results or .error.
    func startSession(config: ScanConfig) {
        currentTask?.cancel()
        currentTask = Task {
            await runSession(config: config)
        }
    }

    func pauseScan() {
        isPaused = true
    }

    func resumeScan() {
        isPaused = false
    }

    func cancelScan() {
        currentTask?.cancel()
        currentTask = nil
        indexStore.clearScanJobState()
        scanProgressDeliveryToken = nil
        phase = .idle
    }

    /// Execute delete for the given assets (e.g. from duplicate cluster detail). Uses undo window.
    func requestDelete(assets: [PHAsset], undoWindow: Bool = true) async throws {
        if undoWindow {
            _ = deletionManager.scheduleDeleteWithUndoWindow(assets: assets, isPremium: false)
            // UI shows "Cleanup complete" with Undo; we don't commit immediately.
            return
        }
        try await deletionManager.performDelete(assets: assets)
    }

    /// Commit the pending delete (after undo window) or cancel for Undo.
    func commitPendingDelete() async throws {
        // DeletionManager's scheduled work will run; nothing to do unless we expose commitNow.
    }

    func cancelPendingDelete() {
        deletionManager.cancelPendingDelete()
    }

    var lastSession: DeletionSession? {
        deletionManager.lastSession
    }

    private func runSession(config: ScanConfig) async {
        scanProgressDeliveryToken = nil
        let sessionStart = Date()
        ScanDebugLogger.start("Smart scan", scope: config.scope.title)
        phase = .scanning(progress: ScanProgress(current: 0, total: 0, message: "Preparing…"))
        indexStore.clearScanJobState()
        photoLibrary.clearImageCache()
        do {
            let fetchStart = Date()
            let photos = try await photoLibrary.fetchPhotos(scope: config.scope)
            ScanDebugLogger.logPhase("fetchPhotos", duration: Date().timeIntervalSince(fetchStart), extra: "\(photos.count) photos")
            guard !Task.isCancelled else { phase = .idle; return }

            let progressDeliveryToken = UUID()
            scanProgressDeliveryToken = progressDeliveryToken

            var result = CleanupSessionResult(config: config, photosScanned: photos)
            let total = photos.count
            let modes = config.enabledModes.map(\.rawValue)
            var jobState = ScanJobState(
                jobId: UUID().uuidString,
                scopeDescription: config.scope.title,
                modes: modes,
                totalAssetCount: total,
                processedCount: 0,
                lastUpdated: Date()
            )
            indexStore.saveScanJobState(jobState)

            let runDup = config.enabledModes.contains(.duplicates)
            let runSim = config.enabledModes.contains(.similarShots)
            var sharedFeaturePrints: [String: VNFeaturePrintObservation]?
            if runDup && runSim {
                await ScaleThrottle.yieldIfNeeded()
                phase = .scanning(progress: ScanProgress(current: 0, total: total, message: "Analyzing photos…"))
                let extractStart = Date()
                sharedFeaturePrints = await photoLibrary.extractFeaturePrints(for: photos) { [weak self] done, t in
                    guard !Task.isCancelled else { return }
                    let tok = progressDeliveryToken
                    Task { @MainActor in
                        guard let self, self.scanProgressDeliveryToken == tok else { return }
                        self.phase = .scanning(progress: ScanProgress(current: done, total: t, message: "Analyzing photos (\(done) / \(t))…"))
                    }
                }
                ScanDebugLogger.logPhase("extractFeaturePrints (dup+sim)", duration: Date().timeIntervalSince(extractStart), extra: "\(sharedFeaturePrints?.count ?? 0)/\(total) prints")
            }

            if runDup {
                await ScaleThrottle.yieldIfNeeded()
                let dupStart = Date()
                phase = .scanning(progress: ScanProgress(current: 0, total: total, message: "Scanning duplicates…"))
                let clusters = try await duplicateService.findDuplicates(in: photos, precomputedFeaturePrints: sharedFeaturePrints) { [weak self] done, t in
                    guard !Task.isCancelled else { return }
                    let tok = progressDeliveryToken
                    Task { @MainActor in
                        guard let self, self.scanProgressDeliveryToken == tok else { return }
                        self.phase = .scanning(progress: ScanProgress(current: done, total: t, message: "Scanning duplicates (\(done) / \(t))"))
                        if done % self.progressSaveInterval == 0 {
                            let state = ScanJobState(
                                jobId: jobState.jobId,
                                scopeDescription: jobState.scopeDescription,
                                modes: jobState.modes,
                                totalAssetCount: jobState.totalAssetCount,
                                processedCount: done,
                                lastUpdated: Date()
                            )
                            self.indexStore.saveScanJobState(state)
                        }
                    }
                }
                ScanDebugLogger.logPhase("findDuplicates", duration: Date().timeIntervalSince(dupStart), extra: "\(clusters.count) clusters")
                let bestStart = Date()
                let clusterCount = clusters.count
                for i in clusters.indices {
                    guard !Task.isCancelled else { indexStore.clearScanJobState(); scanProgressDeliveryToken = nil; phase = .idle; return }
                    if clusterCount > 5 && ((i + 1) % 10 == 0 || i == clusterCount - 1) {
                        phase = .scanning(progress: ScanProgress(current: i + 1, total: clusterCount, message: "Picking best duplicate (\(i + 1) / \(clusterCount))"))
                    }
                    await ScaleThrottle.yieldIfNeeded()
                    let suggested = await bestPhotoService.suggestBestIndex(in: clusters[i].items)
                    var c = clusters[i]
                    c.suggestedKeepIndex = suggested
                    result.duplicateClusters.append(c)
                }
                ScanDebugLogger.logPhase("bestPhoto (duplicates)", duration: Date().timeIntervalSince(bestStart), extra: "\(clusters.count) clusters")
            }
            if Task.isCancelled { indexStore.clearScanJobState(); scanProgressDeliveryToken = nil; phase = .idle; return }

            if runSim {
                await ScaleThrottle.yieldIfNeeded()
                jobState.processedCount = total
                jobState.lastUpdated = Date()
                indexStore.saveScanJobState(jobState)
                let simStart = Date()
                phase = .scanning(progress: ScanProgress(current: total, total: total, message: "Grouping similar shots…"))
                let groups = try await similarGroupingService.groupSimilarSameDay(photos: photos, precomputedFeaturePrints: sharedFeaturePrints) { [weak self] done, t in
                    guard !Task.isCancelled else { return }
                    let tok = progressDeliveryToken
                    Task { @MainActor in
                        guard let self, self.scanProgressDeliveryToken == tok else { return }
                        self.phase = .scanning(progress: ScanProgress(current: done, total: t, message: "Grouping similar shots (\(done) / \(t))"))
                        if done % self.progressSaveInterval == 0 {
                            var state = jobState
                            state.processedCount = done
                            state.lastUpdated = Date()
                            self.indexStore.saveScanJobState(state)
                        }
                    }
                }
                ScanDebugLogger.logPhase("groupSimilarByWeek", duration: Date().timeIntervalSince(simStart), extra: "\(groups.count) groups")
                let bestSimStart = Date()
                let groupCount = groups.count
                // Skip best-photo for 100+ groups (very slow: full-size load per photo on iOS 26). Compute lazily when user opens a group.
                let skipBestPhoto = groupCount > 100
                for i in groups.indices {
                    guard !Task.isCancelled else { indexStore.clearScanJobState(); scanProgressDeliveryToken = nil; phase = .idle; return }
                    if !skipBestPhoto {
                        if (i + 1) % 10 == 0 || i == groupCount - 1 {
                            phase = .scanning(progress: ScanProgress(current: i + 1, total: groupCount, message: "Picking best photo (\(i + 1) / \(groupCount))"))
                        }
                        await ScaleThrottle.yieldIfNeeded()
                    }
                    let suggested = skipBestPhoto ? nil : await bestPhotoService.suggestBestIndex(in: groups[i].items)
                    var g = groups[i]
                    g.suggestedBestIndex = suggested
                    result.similarDayGroups.append(g)
                }
                ScanDebugLogger.logPhase("bestPhoto (similar)", duration: Date().timeIntervalSince(bestSimStart), extra: skipBestPhoto ? "skipped (\(groupCount) groups)" : "\(groups.count) groups")
            }

            if Task.isCancelled { indexStore.clearScanJobState(); scanProgressDeliveryToken = nil; phase = .idle; return }
            indexStore.clearScanJobState()
            let scanDate = Date()
            indexStore.lastFullScanDate = scanDate
            lastFullScanDate = scanDate
            let summary = "\(result.duplicateClusters.count) dup clusters, \(result.similarDayGroups.count) similar groups"
            ScanDebugLogger.finish("Smart scan", duration: scanDate.timeIntervalSince(sessionStart), summary: summary)
            scanProgressDeliveryToken = nil
            phase = .results(result)
        } catch {
            indexStore.clearScanJobState()
            scanProgressDeliveryToken = nil
            ScanDebugLogger.finish("Smart scan", duration: Date().timeIntervalSince(sessionStart), summary: "ERROR: \(error.localizedDescription)")
            phase = .error(error.localizedDescription)
        }
    }
}
