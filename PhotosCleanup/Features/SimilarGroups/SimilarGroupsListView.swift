//
//  SimilarGroupsListView.swift
//  PhotosCleanup
//
//  Group similar photos by calendar week + Vision. Scan and list groups.
//

import SwiftUI
import Photos

struct SimilarGroupsListView: View {
    @ObservedObject var deletionManager: DeletionManager
    @ObservedObject var adManager: AdManager
    @ObservedObject var lastSmartScanResult: LastSmartScanResult
    @StateObject private var library = PhotoLibraryService()
    @StateObject private var groupingService: SimilarGroupingService
    @StateObject private var bestPhotoService: BestPhotoService
    @State private var scopeOption: ScanScopeOption = .recent
    @State private var selectedYear: Int?
    @State private var customFrom: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var customTo: Date = Date()
    @State private var yearsWithCounts: [(year: Int, count: Int)] = []
    @State private var photos: [PhotoItem] = []
    @State private var localGroups: [SimilarGroup] = []
    @State private var isScanning = false
    @State private var scanProgress: (Int, Int) = (0, 0)
    @State private var errorMessage: String?
    @State private var showCleanupComplete = false
    @State private var cleanupItemCount = 0
    @State private var cleanupBytes: Int64 = 0
    @State private var pendingCancelUndo: (() -> Void)?
    @State private var batchItems: [PendingSimilarBatchItem] = []
    @State private var showBatchDeleteConfirmation = false
    @State private var showQuotaExceededAlert = false

    private var groups: [SimilarGroup] {
        if !lastSmartScanResult.similarDayGroups.isEmpty { return lastSmartScanResult.similarDayGroups }
        return localGroups
    }

    private var effectiveScope: ScanScope? {
        if !lastSmartScanResult.similarDayGroups.isEmpty { return lastSmartScanResult.similarScope }
        return scope
    }

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
        _groupingService = StateObject(wrappedValue: SimilarGroupingService(photoLibrary: lib))
        _bestPhotoService = StateObject(wrappedValue: BestPhotoService(photoLibrary: lib))
    }

    var body: some View {
        NavigationStack {
            Group {
                if isScanning {
                    VStack(spacing: 16) {
                        ProgressView(value: Double(scanProgress.0), total: max(1, Double(scanProgress.1)))
                            .padding(.horizontal, 40)
                        Text("Grouping \(scanProgress.0) of \(scanProgress.1)…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage {
                    ContentUnavailableView("Scan failed", systemImage: "exclamationmark.triangle", description: Text(error))
                } else if groups.isEmpty && !photos.isEmpty {
                    ContentUnavailableView(
                        "No similar groups",
                        systemImage: "checkmark.circle",
                        description: Text("We didn't find groups of similar photos from the same week.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if groups.isEmpty {
                    emptyStateView
                } else {
                    groupList
                }
            }
            .navigationTitle("Similar photos")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if !isScanning {
                        Button(groups.isEmpty ? "Scan" : "Rescan") { Task { await startScan() } }
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
                    onCleanAnother: { showCleanupComplete = false },
                    onDone: { showCleanupComplete = false }
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
            if let scopeTitle = effectiveScope?.title, !groups.isEmpty {
                Text("Results for \(scopeTitle)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            if !groups.isEmpty, let eff = effectiveScope, scope != eff {
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
            "Group similar photos",
            systemImage: "square.stack.3d.up",
            description: Text("Choose a scope above and tap Scan, or run Smart cleanup from Home to see results here.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var similarTabReclaimableBytes: Int64 {
        ReclaimableSpaceEstimator.estimateBytes(duplicateClusters: [], similarGroups: groups)
    }

    private var groupList: some View {
        List {
            if similarTabReclaimableBytes > 0 {
                Section {
                    Text("Up to \(formatReclaimableBytes(similarTabReclaimableBytes)) reclaimable if you delete all suggested similar extras (estimate).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(groups) { group in
                NavigationLink {
                    SimilarGroupDetailView(
                        group: group,
                        library: library,
                        bestPhotoService: bestPhotoService,
                        deletionManager: deletionManager,
                        isPremium: adManager.isPremium,
                        onDelete: { indices in
                            deleteFromGroup(group: group, indicesToRemove: indices)
                        },
                        onDeleteWithUndo: { itemCount, bytesEstimate, cancelUndo in
                            cleanupItemCount = itemCount
                            cleanupBytes = bytesEstimate
                            pendingCancelUndo = cancelUndo
                            showCleanupComplete = true
                        },
                        onAddToBatch: batchItems.contains { $0.groupId == group.id } ? nil : { groupId, assets in
                            batchItems.append(PendingSimilarBatchItem(groupId: groupId, assets: assets))
                        },
                        onMarkReviewed: { lastSmartScanResult.markSimilarGroupReviewed(group) }
                    )
                } label: {
                    HStack {
                        ClusterThumbnailStack(items: Array(group.items.prefix(3)), library: library)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.headline)
                            Text("\(group.items.count) similar photos")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if group.suggestedBestIndex != nil {
                                Text("Best pick available")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if lastSmartScanResult.reviewedSimilarGroupIds.contains(group.id) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(AppTheme.accent)
                        } else if lastSmartScanResult.anyPhotoPreviouslyScreened(in: group) {
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

    private func formatReclaimableBytes(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }

    private func startScan() async {
        ScanDebugLogger.start("Similar scan", scope: scope.title)
        let t0 = Date()
        deletionManager.startNewDeletionRun()
        isScanning = true
        errorMessage = nil
        lastSmartScanResult.clearSimilar()
        localGroups = []
        do {
            photos = try await library.fetchPhotos(scope: scope)
            guard !photos.isEmpty else {
                ScanDebugLogger.finish("Similar scan", duration: Date().timeIntervalSince(t0), summary: "no photos in scope")
                isScanning = false
                return
            }
            var resultGroups = try await groupingService.groupSimilarSameDay(photos: photos) { done, total in
                Task { @MainActor in scanProgress = (done, total) }
            }
            for i in resultGroups.indices {
                let suggested = await bestPhotoService.suggestBestIndex(in: resultGroups[i].items)
                var updated = resultGroups[i]
                updated.suggestedBestIndex = suggested
                resultGroups[i] = updated
            }
            lastSmartScanResult.setSimilar(scope: scope, groups: resultGroups)
            ScanDebugLogger.finish("Similar scan", duration: Date().timeIntervalSince(t0), summary: "\(resultGroups.count) groups")
        } catch {
            ScanDebugLogger.finish("Similar scan", duration: Date().timeIntervalSince(t0), summary: "ERROR: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
        isScanning = false
    }

    private func deleteFromGroup(group: SimilarGroup, indicesToRemove: Set<Int>) {
        lastSmartScanResult.similarDayGroups.removeAll { $0.id == group.id }
        localGroups.removeAll { $0.id == group.id }
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
            lastSmartScanResult.similarDayGroups.removeAll { $0.id == item.groupId }
            localGroups.removeAll { $0.id == item.groupId }
        }
        batchItems = []
        showBatchDeleteConfirmation = false
    }
}

struct PendingSimilarBatchItem: Identifiable {
    let groupId: String
    let assets: [PHAsset]
    var id: String { groupId }
}
