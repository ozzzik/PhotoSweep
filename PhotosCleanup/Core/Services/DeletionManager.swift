//
//  DeletionManager.swift
//  PhotosCleanup
//
//  Safe delete to Recently Deleted; optional short-term undo by delaying actual delete.
//

import Foundation
@preconcurrency import Photos

/// Logged cleanup session for history and undo.
struct DeletionSession: Sendable {
    let id: UUID
    let date: Date
    let assetCount: Int
    let bytesFreed: Int64
    let assetIds: [String]
}

@MainActor
final class DeletionManager: ObservableObject {
    /// Last completed session (for "Last cleanup: X days ago · Y GB freed").
    @Published private(set) var lastSession: DeletionSession?

    /// Free-tier limit: maximum assets deletable per cleanup run.
    private let freeDeletionQuotaPerRun: Int = 100
    @Published private(set) var remainingDeletionQuotaForRun: Int = 100

    /// Pending delete: assets and scheduled work item so we can cancel for "Undo".
    private var pendingAssets: [PHAsset] = []
    private var pendingWork: DispatchWorkItem?
    /// Quota reserved for the current pending delete so Undo can refund it.
    private var pendingReservedQuotaCount: Int = 0
    private let undoWindowSeconds: Int = 15
    private weak var analyticsService: AnalyticsService?

    init(analyticsService: AnalyticsService? = nil) {
        self.analyticsService = analyticsService
    }

    /// Starts a fresh cleanup run (scan/load/review session) and resets the free quota counter.
    /// Cancels any pending delete and refunds reserved quota.
    func startNewDeletionRun() {
        cancelPendingDelete()
        remainingDeletionQuotaForRun = freeDeletionQuotaPerRun
    }

    /// Convenience accessor for UI.
    func quotaRemaining() -> Int { remainingDeletionQuotaForRun }

    /// Perform delete immediately (e.g. when user has no undo).
    func performDelete(assets: [PHAsset]) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        }
        let bytes = await estimateSize(assets)
        let session = DeletionSession(
            id: UUID(),
            date: Date(),
            assetCount: assets.count,
            bytesFreed: bytes,
            assetIds: assets.map(\.localIdentifier)
        )
        lastSession = session
        analyticsService?.trackCleanupCompleted(itemsDeleted: assets.count, bytesFreed: bytes, modes: [])
    }

    /// Schedule delete after a short delay; returns a task the caller can cancel for "Undo".
    /// If not cancelled, performs delete and updates lastSession.
    func scheduleDeleteWithUndoWindow(
        assets: [PHAsset],
        isPremium: Bool
    ) -> (cancelUndo: () -> Void, commitNow: () async throws -> Void)? {
        guard !assets.isEmpty else { return nil }

        // Rescheduling a new delete cancels any previous pending delete, refunding reserved quota.
        if pendingWork != nil || !pendingAssets.isEmpty || pendingReservedQuotaCount > 0 {
            cancelPendingDelete()
        }

        if !isPremium {
            let count = assets.count
            guard count <= remainingDeletionQuotaForRun else { return nil }
            remainingDeletionQuotaForRun -= count
            pendingReservedQuotaCount = count
        } else {
            pendingReservedQuotaCount = 0
        }

        pendingAssets = assets
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, !self.pendingAssets.isEmpty else { return }
            let toDelete = self.pendingAssets
            self.pendingAssets = []
            self.pendingWork = nil
            self.pendingReservedQuotaCount = 0
            Task { @MainActor in
                try? await self.performDelete(assets: toDelete)
            }
        }
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(undoWindowSeconds), execute: work)

        func cancelUndo() {
            pendingWork?.cancel()
            pendingWork = nil
            pendingAssets = []
            if pendingReservedQuotaCount > 0 {
                remainingDeletionQuotaForRun += pendingReservedQuotaCount
                pendingReservedQuotaCount = 0
            }
        }
        func commitNow() async throws {
            cancelUndo()
            guard !assets.isEmpty else { return }
            try await performDelete(assets: assets)
        }
        return (cancelUndo, commitNow)
    }

    /// Cancel the pending delete (user tapped "Undo").
    func cancelPendingDelete() {
        pendingWork?.cancel()
        pendingWork = nil
        pendingAssets = []
        if pendingReservedQuotaCount > 0 {
            remainingDeletionQuotaForRun += pendingReservedQuotaCount
            pendingReservedQuotaCount = 0
        }
    }

    /// Whether there is a pending delete that can be undone.
    var hasPendingDelete: Bool {
        !pendingAssets.isEmpty
    }

    private func estimateSize(_ assets: [PHAsset]) async -> Int64 {
        assets.reduce(0) { $0 + $1.estimatedStorageBytes }
    }
}
