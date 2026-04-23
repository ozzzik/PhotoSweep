//
//  TripListView.swift
//  PhotosCleanup
//
//  Trip photos grouped by date (each trip = contiguous days). Per trip: All, Duplicates, Similar.
//

import SwiftUI
import Photos

enum TripSubCategory: String, CaseIterable {
    case all = "All"
    case similar = "Similar"
    case duplicates = "Duplicates"
}

/// Trip with its duplicate clusters and similar groups (computed per trip).
struct TripWithAnalysis: Identifiable {
    let trip: TripGroup
    var clusters: [DuplicateCluster]
    var groups: [SimilarGroup]
    var id: String { trip.id }
}

private struct TripPhotoPreviewSession: Identifiable {
    let id = UUID()
    let items: [PhotoItem]
    let initialIndex: Int
}

struct TripListView: View {
    @ObservedObject var deletionManager: DeletionManager
    @ObservedObject var adManager: AdManager
    @StateObject private var library = PhotoLibraryService()
    @StateObject private var tripService: TripDetectionService
    @StateObject private var duplicateService: DuplicateDetectionService
    @StateObject private var groupingService: SimilarGroupingService
    @StateObject private var bestPhotoService: BestPhotoService
    @StateObject private var resultStore = TripsResultStore()
    @State private var subCategory: TripSubCategory = .all
    @State private var tripGroups: [TripWithAnalysis] = []
    @State private var effectiveScope: ScanScope? = nil  // scope used for current results
    @State private var isLoading = false
    @State private var isAnalyzing = false
    @State private var scanProgress: (Int, Int) = (0, 0)
    @State private var scanMessage = "Finding trip photos"
    @State private var errorMessage: String?
    @State private var scopeOption: ScanScopeOption = .recent
    @State private var selectedYear: Int?
    @State private var customFrom: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var customTo: Date = Date()
    @State private var yearsWithCounts: [(year: Int, count: Int)] = []
    @State private var showDeleteConfirmation = false
    @State private var selectedToDelete: Set<String> = []
    @State private var showCleanupComplete = false
    @State private var cleanupItemCount = 0
    @State private var cleanupBytes: Int64 = 0
    @State private var pendingCancelUndo: (() -> Void)?
    @State private var tripPreviewSession: TripPhotoPreviewSession?
    @State private var batchItems: [PendingDuplicateBatchItem] = []
    @State private var similarBatchItems: [PendingSimilarBatchItem] = []
    @State private var showBatchDeleteConfirmation = false
    @State private var showQuotaExceededAlert = false

    init(deletionManager: DeletionManager, adManager: AdManager) {
        _deletionManager = ObservedObject(wrappedValue: deletionManager)
        _adManager = ObservedObject(wrappedValue: adManager)
        let lib = PhotoLibraryService()
        _library = StateObject(wrappedValue: lib)
        _tripService = StateObject(wrappedValue: TripDetectionService(photoLibrary: lib))
        _duplicateService = StateObject(wrappedValue: DuplicateDetectionService(photoLibrary: lib))
        _groupingService = StateObject(wrappedValue: SimilarGroupingService(photoLibrary: lib))
        _bestPhotoService = StateObject(wrappedValue: BestPhotoService(photoLibrary: lib))
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading photos…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isAnalyzing {
                VStack(spacing: 16) {
                    ProgressView(value: Double(scanProgress.0), total: max(1, Double(scanProgress.1)))
                        .padding(.horizontal, 40)
                    Text("\(scanMessage) \(scanProgress.0) / \(scanProgress.1)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if hasNoResults {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: "airplane",
                    description: Text(emptyDescription)
                )
            } else {
                listContent
            }
        }
        .navigationTitle("Trips")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if !isScanning {
                    Button(tripGroups.isEmpty ? "Scan" : "Reload") { Task { await runScan() } }
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            scopeSection
        }
        .task { await loadYears() }
        .task { await loadPersistedIfPremium() }
        .onChange(of: adManager.isPremium) { _, isPremium in
            guard !isPremium else { return }
            if scopeOption == .custom || scopeOption == .all {
                scopeOption = .thisYear
                selectedYear = nil
            }
        }
        .confirmationDialog("Delete \(selectedToDelete.count) photos?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) { performDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(DeletionCopy.confirmationMessageModeSpecific(prefix: "These are trip or vacation photos."))
        }
        .sheet(item: $tripPreviewSession) { session in
            GroupPhotoPreviewView(
                items: session.items,
                initialIndex: session.initialIndex,
                selectedToRemove: tripPreviewBinding(for: session),
                library: library
            ) {
                tripPreviewSession = nil
            }
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
        .confirmationDialog("Delete batch?", isPresented: $showBatchDeleteConfirmation) {
            Button("Delete \(batchItemCount) photos", role: .destructive) {
                performBatchDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will move \(batchItemCount) photos to Recently Deleted. You can undo within 15 seconds.")
        }
    }

    private var isScanning: Bool { isLoading || isAnalyzing }

    private var hasNoResults: Bool {
        tripGroups.isEmpty
    }

    private var emptyTitle: String {
        "No trip photos"
    }

    private var emptyDescription: String {
        if let eff = effectiveScope {
            return "No vacation, city, or landmark photos found in \(eff.title)."
        }
        return "Choose scope above and tap Scan to find trip photos."
    }

    private var batchItemCount: Int {
        batchItems.reduce(0) { $0 + $1.assets.count } + similarBatchItems.reduce(0) { $0 + $1.assets.count }
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
            if let scopeTitle = effectiveScope?.title, !tripGroups.isEmpty {
                Text("Results for \(scopeTitle)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            if let eff = effectiveScope, scope != eff {
                Text("Tap \(tripGroups.isEmpty ? "Scan" : "Reload") to scan \(scope.title)")
                    .font(.caption)
                    .foregroundStyle(AppTheme.accent)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
    }

    private var listContent: some View {
        List {
            Section {
                subCategoryPicker
                Text(descriptionText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(tripGroups) { twa in
                Section(twa.trip.title) {
                    switch subCategory {
                    case .all:
                        ForEach(Array(twa.trip.photos.enumerated()), id: \.element.id) { index, item in
                            selectablePhotoRow(item: item, tripPhotos: twa.trip.photos, photoIndex: index)
                        }
                    case .duplicates:
                        ForEach(twa.clusters) { cluster in
                            NavigationLink {
                                DuplicateClusterDetailView(
                                    cluster: cluster,
                                    library: library,
                                    bestPhotoService: bestPhotoService,
                                    deletionManager: deletionManager,
                                    isPremium: adManager.isPremium,
                                    onDelete: { _ in removeCluster(clusterId: cluster.id, fromTripId: twa.id) },
                                    onDeleteWithUndo: { c, b, cancel in
                                        cleanupItemCount = c
                                        cleanupBytes = b
                                        pendingCancelUndo = cancel
                                        showCleanupComplete = true
                                    },
                                    onAddToBatch: batchItems.contains { $0.clusterId == cluster.id } ? nil : { id, assets in
                                        batchItems.append(PendingDuplicateBatchItem(clusterId: id, assets: assets))
                                    }
                                )
                            } label: {
                                HStack {
                                    ClusterThumbnailStack(items: Array(cluster.items.prefix(3)), library: library)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(cluster.items.count) similar photos")
                                            .font(.headline)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    case .similar:
                        ForEach(twa.groups) { group in
                            NavigationLink {
                                SimilarGroupDetailView(
                                    group: group,
                                    library: library,
                                    bestPhotoService: bestPhotoService,
                                    deletionManager: deletionManager,
                                    isPremium: adManager.isPremium,
                                    onDelete: { _ in removeGroup(groupId: group.id, fromTripId: twa.id) },
                                    onDeleteWithUndo: { c, b, cancel in
                                        cleanupItemCount = c
                                        cleanupBytes = b
                                        pendingCancelUndo = cancel
                                        showCleanupComplete = true
                                    },
                                    onAddToBatch: similarBatchItems.contains { $0.groupId == group.id } ? nil : { id, assets in
                                        similarBatchItems.append(PendingSimilarBatchItem(groupId: id, assets: assets))
                                    }
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
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
            if !selectedToDelete.isEmpty && subCategory == .all {
                Section {
                    Button("Delete \(selectedToDelete.count) selected", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                }
            }
            if !batchItems.isEmpty || !similarBatchItems.isEmpty {
                Section {
                    HStack {
                        Text("\(batchItems.count + similarBatchItems.count) groups, \(batchItemCount) photos")
                        Spacer()
                        Button("Clear") {
                            batchItems = []
                            similarBatchItems = []
                        }
                        .foregroundStyle(.secondary)
                        Button("Delete batch") {
                            showBatchDeleteConfirmation = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }

    private var descriptionText: String {
        switch subCategory {
        case .all:
            return "Photos grouped by trip (date gaps > 7 days). Each trip shows All, Duplicates, Similar. Tap the magnifier to swipe through every photo in this trip."
        case .similar:
            return "Similar photos from the same calendar week within each trip. Tap a group to review — swipe left/right in full screen to compare."
        case .duplicates:
            return "Duplicate photos within each trip. Tap a cluster to review — swipe left/right in full screen to compare."
        }
    }

    private func removeCluster(clusterId: String, fromTripId tripId: String) {
        tripGroups = tripGroups.map { twa in
            guard twa.id == tripId else { return twa }
            return TripWithAnalysis(trip: twa.trip, clusters: twa.clusters.filter { $0.id != clusterId }, groups: twa.groups)
        }
    }

    private func removeGroup(groupId: String, fromTripId tripId: String) {
        tripGroups = tripGroups.map { twa in
            guard twa.id == tripId else { return twa }
            return TripWithAnalysis(trip: twa.trip, clusters: twa.clusters, groups: twa.groups.filter { $0.id != groupId })
        }
    }

    private var subCategoryPicker: some View {
        Picker("View", selection: $subCategory) {
            Text("All").tag(TripSubCategory.all)
            Text("Similar").tag(TripSubCategory.similar)
            Text("Duplicates").tag(TripSubCategory.duplicates)
        }
        .pickerStyle(.segmented)
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

    private func selectablePhotoRow(item: PhotoItem, tripPhotos: [PhotoItem], photoIndex: Int) -> some View {
        let isSelected = selectedToDelete.contains(item.id)
        return HStack {
            AssetThumbnailView(asset: item.asset, library: library, size: CGSize(width: 60, height: 60))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Text(item.creationDate?.formatted(date: .abbreviated, time: .omitted) ?? "—")
                .font(.subheadline)
            Spacer()
            Button {
                tripPreviewSession = TripPhotoPreviewSession(items: tripPhotos, initialIndex: photoIndex)
            } label: {
                Image(systemName: "magnifyingglass.circle")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelected {
                selectedToDelete.remove(item.id)
            } else {
                selectedToDelete.insert(item.id)
            }
        }
    }

    private func tripPreviewBinding(for session: TripPhotoPreviewSession) -> Binding<Set<Int>> {
        Binding(
            get: {
                Set(session.items.indices.filter { selectedToDelete.contains(session.items[$0].id) })
            },
            set: { newIndices in
                let idsInSession = Set(session.items.map(\.id))
                var next = selectedToDelete
                for id in idsInSession { next.remove(id) }
                for idx in newIndices {
                    next.insert(session.items[idx].id)
                }
                selectedToDelete = next
            }
        )
    }

    private func loadYears() async {
        let years = await library.fetchYearsWithCounts()
        yearsWithCounts = years
        if selectedYear == nil, let first = years.first {
            selectedYear = first.year
        }
    }

    private func runScan() async {
        let scanScope = scope
        deletionManager.startNewDeletionRun()
        isLoading = true
        isAnalyzing = false
        errorMessage = nil
        tripGroups = []
        do {
            let photos = try await library.fetchPhotos(scope: scanScope)
            isLoading = false
            if photos.isEmpty {
                effectiveScope = scanScope
                if adManager.isPremium {
                    resultStore.save(scope: scanScope, trips: [])
                }
                return
            }
            isAnalyzing = true
            scanMessage = "Finding trip photos"
            let tripPhotos = await tripService.filterTripPhotos(from: photos) { done, total in
                Task { @MainActor in scanProgress = (done, total) }
            }
            guard !tripPhotos.isEmpty else {
                effectiveScope = scanScope
                isAnalyzing = false
                return
            }
            let trips = tripService.groupIntoTrips(photos: tripPhotos, gapDays: 7)
            var result: [TripWithAnalysis] = []
            let totalTrips = trips.count
            for (idx, trip) in trips.enumerated() {
                await ScaleThrottle.yieldIfNeeded()
                scanMessage = "Analyzing trip \(idx + 1) of \(totalTrips)"
                scanProgress = (idx, totalTrips)
                var clusters: [DuplicateCluster] = []
                var groups: [SimilarGroup] = []
                if trip.photos.count >= 2 {
                    let prints = await library.extractFeaturePrints(for: trip.photos) { done, total in
                        Task { @MainActor in scanProgress = (done, total) }
                    }
                    clusters = (try? await duplicateService.findDuplicates(in: trip.photos, precomputedFeaturePrints: prints) { done, total in
                        Task { @MainActor in scanProgress = (done, total) }
                    }) ?? []
                    for i in clusters.indices {
                        let suggested = await bestPhotoService.suggestBestIndex(in: clusters[i].items)
                        var c = clusters[i]
                        c.suggestedKeepIndex = suggested
                        clusters[i] = c
                    }
                    groups = (try? await groupingService.groupSimilarSameDay(photos: trip.photos, precomputedFeaturePrints: prints) { done, total in
                        Task { @MainActor in scanProgress = (done, total) }
                    }) ?? []
                    for i in groups.indices {
                        let suggested = await bestPhotoService.suggestBestIndex(in: groups[i].items)
                        var g = groups[i]
                        g.suggestedBestIndex = suggested
                        groups[i] = g
                    }
                }
                result.append(TripWithAnalysis(trip: trip, clusters: clusters, groups: groups))
            }
            tripGroups = result
            effectiveScope = scanScope
            isAnalyzing = false

            if adManager.isPremium {
                resultStore.save(scope: scanScope, trips: tripGroups)
            }
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            isAnalyzing = false
        }
    }

    private func loadPersistedIfPremium() async {
        guard adManager.isPremium else { return }
        guard tripGroups.isEmpty else { return }
        guard let loaded = resultStore.load() else { return }

        // Apply scope so the UI aligns with persisted results.
        applyScope(loaded.scope)
        effectiveScope = loaded.scope

        let uniqueIds: Set<String> = Set(loaded.snapshots.flatMap { snap in
            var ids = snap.photoIds
            for c in snap.clusters { ids.append(contentsOf: c.assetIds) }
            for g in snap.groups { ids.append(contentsOf: g.assetIds) }
            return ids
        })

        let idList = Array(uniqueIds)
        let photoItems = await library.fetchPhotoItems(identifiers: idList)
        let idToItem = Dictionary(uniqueKeysWithValues: photoItems.map { ($0.id, $0) })

        tripGroups = loaded.snapshots.compactMap { snap in
            let tripPhotos = snap.photoIds.compactMap { idToItem[$0] }
            guard !tripPhotos.isEmpty else { return nil }

            let trip = TripGroup(id: snap.tripId, photos: tripPhotos, startDate: snap.startDate, endDate: snap.endDate)

            let clusters: [DuplicateCluster] = snap.clusters.compactMap { c in
                let items = c.assetIds.compactMap { idToItem[$0] }
                guard items.count >= 2 else { return nil }
                return DuplicateCluster(id: c.id, items: items, suggestedKeepIndex: c.suggestedKeepIndex)
            }

            let groups: [SimilarGroup] = snap.groups.compactMap { g in
                let items = g.assetIds.compactMap { idToItem[$0] }
                guard items.count >= 2 else { return nil }
                return SimilarGroup(id: g.id, date: g.date, items: items, suggestedBestIndex: g.suggestedBestIndex)
            }

            return TripWithAnalysis(trip: trip, clusters: clusters, groups: groups)
        }

        isLoading = false
        isAnalyzing = false
        errorMessage = nil
        selectedToDelete.removeAll()
        batchItems = []
        similarBatchItems = []
    }

    private func applyScope(_ newScope: ScanScope) {
        switch newScope {
        case .recent:
            scopeOption = .recent
        case .thisMonth:
            scopeOption = .thisMonth
        case .thisYear:
            scopeOption = .thisYear
        case .year(let y):
            scopeOption = .byYear
            selectedYear = y
        case .custom(let from, let to):
            scopeOption = .custom
            customFrom = from
            customTo = to
        case .entireLibrary:
            scopeOption = .all
        }
    }

    private func performDelete() {
        var allPhotos: [PhotoItem] = []
        for twa in tripGroups {
            allPhotos.append(contentsOf: twa.trip.photos)
        }
        let assets = allPhotos.filter { selectedToDelete.contains($0.id) }.map(\.asset)
        let count = assets.count
        let bytes = assets.reduce(0) { $0 + $1.estimatedStorageBytes }
        guard let scheduled = deletionManager.scheduleDeleteWithUndoWindow(
            assets: assets,
            isPremium: adManager.isPremium
        ) else {
            showQuotaExceededAlert = true
            return
        }
        let cancelUndo = scheduled.cancelUndo
        cleanupItemCount = count
        cleanupBytes = bytes
        pendingCancelUndo = cancelUndo
        showCleanupComplete = true
        let toRemove = selectedToDelete
        tripGroups = tripGroups.compactMap { twa in
            let remaining = twa.trip.photos.filter { !toRemove.contains($0.id) }
            guard !remaining.isEmpty else { return nil }
            let dates = remaining.compactMap(\.creationDate)
            let start = dates.min() ?? twa.trip.startDate
            let end = dates.max() ?? twa.trip.endDate
            return TripWithAnalysis(
                trip: TripGroup(id: twa.trip.id, photos: remaining, startDate: start, endDate: end),
                clusters: twa.clusters,
                groups: twa.groups
            )
        }
        selectedToDelete.removeAll()
    }

    private func performBatchDelete() {
        var allAssets: [PHAsset] = []
        for item in batchItems { allAssets.append(contentsOf: item.assets) }
        for item in similarBatchItems { allAssets.append(contentsOf: item.assets) }
        let totalCount = allAssets.count
        let totalBytes = allAssets.reduce(0) { $0 + $1.estimatedStorageBytes }

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
        let toRemoveClusterIds = Set(batchItems.map(\.clusterId))
        let toRemoveGroupIds = Set(similarBatchItems.map(\.groupId))
        tripGroups = tripGroups.map { twa in
            TripWithAnalysis(
                trip: twa.trip,
                clusters: twa.clusters.filter { !toRemoveClusterIds.contains($0.id) },
                groups: twa.groups.filter { !toRemoveGroupIds.contains($0.id) }
            )
        }
        batchItems = []
        similarBatchItems = []
        showBatchDeleteConfirmation = false
    }
}
