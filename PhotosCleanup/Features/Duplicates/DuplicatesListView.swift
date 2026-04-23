//
//  DuplicatesListView.swift
//  PhotosCleanup
//
//  Scan for duplicates and list clusters. User can pick keep/remove and run best-photo suggestion.
//

import SwiftUI
import Photos

struct DuplicatesListView: View {
    @ObservedObject var deletionManager: DeletionManager
    @ObservedObject var adManager: AdManager
    @ObservedObject var lastSmartScanResult: LastSmartScanResult
    @StateObject private var library = PhotoLibraryService()
    @StateObject private var duplicateService: DuplicateDetectionService
    @StateObject private var bestPhotoService: BestPhotoService
    @State private var scopeOption: ScanScopeOption = .recent
    @State private var selectedYear: Int?
    @State private var customFrom: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var customTo: Date = Date()
    @State private var yearsWithCounts: [(year: Int, count: Int)] = []
    @State private var photos: [PhotoItem] = []
    @State private var localClusters: [DuplicateCluster] = []
    @State private var isScanning = false
    @State private var scanProgress: (Int, Int) = (0, 0)
    @State private var errorMessage: String?
    @State private var showCleanupComplete = false
    @State private var cleanupItemCount = 0
    @State private var cleanupBytes: Int64 = 0
    @State private var pendingCancelUndo: (() -> Void)?
    @State private var batchItems: [PendingDuplicateBatchItem] = []
    @State private var showBatchDeleteConfirmation = false
    @State private var showQuotaExceededAlert = false

    private var clusters: [DuplicateCluster] {
        if !lastSmartScanResult.duplicateClusters.isEmpty { return lastSmartScanResult.duplicateClusters }
        return localClusters
    }

    private var effectiveScope: ScanScope? {
        if !lastSmartScanResult.duplicateClusters.isEmpty { return lastSmartScanResult.duplicateScope }
        return scope
    }

    /// Resolved scan scope from the Scope menu (matches Junk / Trips / Scan setup).
    private var scope: ScanScope {
        switch scopeOption {
        case .recent: return .recent(days: 30)
        case .thisMonth: return .thisMonth
        case .thisYear: return .thisYear
        case .byYear:
            if let y = selectedYear ?? yearsWithCounts.first?.year { return .year(y) }
            return .thisYear
        case .custom:
            if adManager.isPremium { return .custom(from: customFrom, to: customTo) }
            return .thisYear
        case .all:
            return adManager.isPremium ? .entireLibrary : .thisYear
        }
    }

    init(deletionManager: DeletionManager, adManager: AdManager, lastSmartScanResult: LastSmartScanResult) {
        _deletionManager = ObservedObject(wrappedValue: deletionManager)
        _adManager = ObservedObject(wrappedValue: adManager)
        _lastSmartScanResult = ObservedObject(wrappedValue: lastSmartScanResult)
        let lib = PhotoLibraryService()
        _library = StateObject(wrappedValue: lib)
        _duplicateService = StateObject(wrappedValue: DuplicateDetectionService(photoLibrary: lib))
        _bestPhotoService = StateObject(wrappedValue: BestPhotoService(photoLibrary: lib))
    }

    var body: some View {
        NavigationStack {
            Group {
                if isScanning {
                    VStack(spacing: 16) {
                        ProgressView(value: Double(scanProgress.0), total: max(1, Double(scanProgress.1)))
                            .padding(.horizontal, 40)
                        Text("Scanning \(scanProgress.0) of \(scanProgress.1)…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage {
                    ContentUnavailableView("Scan failed", systemImage: "exclamationmark.triangle", description: Text(error))
                } else if clusters.isEmpty && !photos.isEmpty {
                    emptyResultsView
                } else if clusters.isEmpty {
                    emptyStateView
                } else {
                    clusterList
                }
            }
            .navigationTitle("Duplicates")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if !isScanning {
                        Button(clusters.isEmpty ? "Scan" : "Rescan") { Task { await startScan() } }
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                scopeSection
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    if !adManager.isPremium {
                        BannerAdWaterfallView(isPremium: adManager.isPremium)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 50, idealHeight: 66, maxHeight: 90)
                            .background(Color(.systemBackground))
                    }
                    batchBar
                }
            }
            .task { await loadYears() }
            .onChange(of: adManager.isPremium) { _, isPremium in
                guard !isPremium else { return }
                if scopeOption == .custom || scopeOption == .all {
                    scopeOption = .thisYear
                    selectedYear = nil
                }
            }
            .confirmationDialog("Delete batch?", isPresented: $showBatchDeleteConfirmation) {
                Button("Delete \(batchItems.reduce(0) { $0 + $1.assets.count }) photos", role: .destructive) {
                    performBatchDelete()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will move \(batchItems.reduce(0) { $0 + $1.assets.count }) photos to Recently Deleted. You can undo within 15 seconds.")
            }
            .sheet(isPresented: $showCleanupComplete) {
                CleanupCompleteView(
                    itemCount: cleanupItemCount,
                    bytesFreed: cleanupBytes,
                    adManager: adManager,
                    onUndo: {
                        pendingCancelUndo?()
                        pendingCancelUndo = nil
                        showCleanupComplete = false
                    },
                    onCleanAnother: {
                        showCleanupComplete = false
                    },
                    onDone: {
                        showCleanupComplete = false
                    }
                )
            }
            .alert("Deletion limit reached", isPresented: $showQuotaExceededAlert) {
                Button("Unlock Premium") {
                    NotificationCenter.default.post(name: .premiumUnlockRequested, object: nil)
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text("Free users can delete up to 100 photos per run. Unlock PhotoSweep Premium in Settings to delete more.")
            }
        }
    }

    private var batchBar: some View {
        Group {
            if !batchItems.isEmpty {
                VStack(spacing: 8) {
                    HStack {
                        Text("\(batchItems.count) groups, \(batchItems.reduce(0) { $0 + $1.assets.count }) photos")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Button("Clear") {
                            batchItems = []
                        }
                        .foregroundStyle(.secondary)
                        Button("Delete batch") {
                            showBatchDeleteConfirmation = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                }
                .background(Color(.secondarySystemBackground))
            }
        }
    }

    private var scopeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scope")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            ScanScopePicker(scopeOption: $scopeOption, adManager: adManager)
            if scopeOption == .byYear {
                scopeYearPicker
            }
            if adManager.isPremium, scopeOption == .custom {
                scopeCustomRangePicker
            }
            if let scopeTitle = effectiveScope?.title, !clusters.isEmpty {
                Text("Results for \(scopeTitle)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            if !clusters.isEmpty, let eff = effectiveScope, scope != eff {
                Text("Tap Rescan to scan \(scope.title)")
                    .font(.caption)
                    .foregroundStyle(AppTheme.accent)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
    }

    private var scopeYearPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(yearsWithCounts, id: \.year) { y in
                    Button {
                        selectedYear = y.year
                    } label: {
                        Text("\(y.year) (\(y.count.formatted()))")
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(selectedYear == y.year ? AppTheme.accent : Color.secondary.opacity(0.2))
                            .foregroundStyle(selectedYear == y.year ? .white : .primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var scopeCustomRangePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            DatePicker("From", selection: $customFrom, displayedComponents: .date)
            DatePicker("To", selection: $customTo, displayedComponents: .date)
        }
    }

    private func loadYears() async {
        let years = await library.fetchYearsWithCounts()
        yearsWithCounts = years
        if selectedYear == nil, let first = years.first {
            selectedYear = first.year
        }
    }

    private var emptyStateView: some View {
        ContentUnavailableView(
            "Find duplicate photos",
            systemImage: "doc.on.doc",
            description: Text("Choose a scope above and tap Scan, or run Smart cleanup from Home to see results here.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyResultsView: some View {
        ContentUnavailableView(
            "No duplicates found",
            systemImage: "checkmark.circle",
            description: Text("Your library doesn’t have duplicate photos in the sample we checked.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var duplicateTabReclaimableBytes: Int64 {
        ReclaimableSpaceEstimator.estimateBytes(duplicateClusters: clusters, similarGroups: [])
    }

    private var clusterList: some View {
        List {
            if duplicateTabReclaimableBytes > 0 {
                Section {
                    Text("Up to \(formatReclaimableBytes(duplicateTabReclaimableBytes)) reclaimable if you delete all suggested duplicate extras (estimate).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(clusters) { cluster in
                NavigationLink {
                    DuplicateClusterDetailView(
                        cluster: cluster,
                        library: library,
                        bestPhotoService: bestPhotoService,
                        deletionManager: deletionManager,
                            isPremium: adManager.isPremium,
                        onDelete: { indices in
                            deleteFromCluster(cluster: cluster, indicesToRemove: indices)
                        },
                        onDeleteWithUndo: { itemCount, bytesEstimate, cancelUndo in
                            cleanupItemCount = itemCount
                            cleanupBytes = bytesEstimate
                            pendingCancelUndo = cancelUndo
                            showCleanupComplete = true
                        },
                        onAddToBatch: batchItems.contains { $0.clusterId == cluster.id } ? nil : { clusterId, assets in
                            batchItems.append(PendingDuplicateBatchItem(clusterId: clusterId, assets: assets))
                        },
                        onMarkReviewed: { lastSmartScanResult.markDuplicateClusterReviewed(cluster) }
                    )
                } label: {
                    HStack {
                        ClusterThumbnailStack(items: Array(cluster.items.prefix(3)), library: library)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(cluster.items.count) similar photos")
                                .font(.headline)
                            if let keep = cluster.suggestedKeepIndex, cluster.items.indices.contains(keep) {
                                Text("Best pick: photo \(keep + 1)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if lastSmartScanResult.reviewedDuplicateClusterIds.contains(cluster.id) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(AppTheme.accent)
                        } else if lastSmartScanResult.anyPhotoPreviouslyScreened(in: cluster) {
                            Label("Seen before", systemImage: "eye.circle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func startScan() async {
        ScanDebugLogger.start("Duplicates scan", scope: scope.title)
        let t0 = Date()
        deletionManager.startNewDeletionRun()
        isScanning = true
        errorMessage = nil
        lastSmartScanResult.clearDuplicates()
        localClusters = []
        do {
            photos = try await library.fetchPhotos(scope: scope)
            guard !photos.isEmpty else {
                ScanDebugLogger.finish("Duplicates scan", duration: Date().timeIntervalSince(t0), summary: "no photos in scope")
                isScanning = false
                return
            }
            var resultClusters = try await duplicateService.findDuplicates(in: photos) { done, total in
                Task { @MainActor in scanProgress = (done, total) }
            }
            for i in resultClusters.indices {
                let suggested = await bestPhotoService.suggestBestIndex(in: resultClusters[i].items)
                var updated = resultClusters[i]
                updated.suggestedKeepIndex = suggested
                resultClusters[i] = updated
            }
            lastSmartScanResult.setDuplicates(scope: scope, clusters: resultClusters)
            ScanDebugLogger.finish("Duplicates scan", duration: Date().timeIntervalSince(t0), summary: "\(resultClusters.count) clusters")
        } catch {
            ScanDebugLogger.finish("Duplicates scan", duration: Date().timeIntervalSince(t0), summary: "ERROR: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
        isScanning = false
    }

    private func formatReclaimableBytes(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }

    private func deleteFromCluster(cluster: DuplicateCluster, indicesToRemove: Set<Int>) {
        lastSmartScanResult.duplicateClusters.removeAll { $0.id == cluster.id }
        localClusters.removeAll { $0.id == cluster.id }
    }

    private func performBatchDelete() {
        var totalCount = 0
        var totalBytes: Int64 = 0
        var allAssets: [PHAsset] = []
        for item in batchItems {
            totalCount += item.assets.count
            for a in item.assets {
                totalBytes += a.estimatedStorageBytes
            }
            allAssets.append(contentsOf: item.assets)
        }

        guard let scheduled = deletionManager.scheduleDeleteWithUndoWindow(
            assets: allAssets,
            isPremium: adManager.isPremium
        ) else {
            showQuotaExceededAlert = true
            return
        }
        let cancelUndo = scheduled.cancelUndo
        cleanupItemCount = totalCount
        cleanupBytes = totalBytes
        pendingCancelUndo = cancelUndo
        showCleanupComplete = true
        for item in batchItems {
            lastSmartScanResult.duplicateClusters.removeAll { $0.id == item.clusterId }
            localClusters.removeAll { $0.id == item.clusterId }
        }
        batchItems = []
        showBatchDeleteConfirmation = false
    }
}

struct PendingDuplicateBatchItem: Identifiable {
    let clusterId: String
    let assets: [PHAsset]
    var id: String { clusterId }
}

// MARK: - Thumbnail stack for cluster preview

struct ClusterThumbnailStack: View {
    let items: [PhotoItem]
    @ObservedObject var library: PhotoLibraryService
    private let size: CGFloat = 56

    var body: some View {
        HStack(spacing: -12) {
            ForEach(Array(items.enumerated()), id: \.element.id) { _, item in
                AssetThumbnailView(asset: item.asset, library: library, size: CGSize(width: size, height: size))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.background, lineWidth: 2))
            }
        }
    }
}

#Preview {
    let sub = SubscriptionManager()
    let ad = AdManager(subscriptionManager: sub)
    DuplicatesListView(
        deletionManager: DeletionManager(),
        adManager: ad,
        lastSmartScanResult: LastSmartScanResult(adManager: ad)
    )
}
