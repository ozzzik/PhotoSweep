//
//  BlurryAndAccidentalListView.swift
//  PhotosCleanup
//
//  Blurry or accidental photos at any age (no minimum age). Scope picker + review + delete.
//

import SwiftUI
import Photos

struct BlurryAndAccidentalListView: View {
    @ObservedObject var deletionManager: DeletionManager
    @ObservedObject var adManager: AdManager
    @StateObject private var library = PhotoLibraryService()
    @StateObject private var resultStore = BlurryAccidentalResultStore()
    @StateObject private var bestPhotoService: BestPhotoService
    @State private var items: [PhotoItem] = []
    @State private var effectiveScope: ScanScope? = nil
    @State private var isLoading = false
    @State private var isAnalyzing = false
    @State private var scanProgress: (Int, Int) = (0, 0)
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
    @State private var groupPreviewTrigger: BlurryGroupPreviewTrigger?
    @State private var showQuotaExceededAlert = false

    init(deletionManager: DeletionManager, adManager: AdManager) {
        _deletionManager = ObservedObject(wrappedValue: deletionManager)
        _adManager = ObservedObject(wrappedValue: adManager)
        let lib = PhotoLibraryService()
        _library = StateObject(wrappedValue: lib)
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
                    Text("Checking quality \(scanProgress.0) / \(scanProgress.1)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if items.isEmpty {
                ContentUnavailableView(
                    "No blurry photos",
                    systemImage: "camera.metering.unknown",
                    description: Text(emptyDescription)
                )
            } else {
                listContent
            }
        }
        .navigationTitle("Blurry & accidental")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if !isScanning {
                    Button(items.isEmpty ? "Scan" : "Reload") { Task { await runScan() } }
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
            Text(DeletionCopy.confirmationMessageModeSpecific(prefix: "These are blurry or accidental shots."))
        }
        .sheet(item: $groupPreviewTrigger) { trigger in
            GroupPhotoPreviewView(
                items: items,
                initialIndex: trigger.initialIndex,
                selectedToRemove: Binding(
                    get: { Set(items.indices.filter { selectedToDelete.contains(items[$0].id) }) },
                    set: { selectedToDelete = Set($0.map { items[$0].id }) }
                ),
                library: library
            ) {
                groupPreviewTrigger = nil
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
    }

    private var isScanning: Bool { isLoading || isAnalyzing }

    private var emptyDescription: String {
        if let eff = effectiveScope {
            return "No blurry or accidental photos found in \(eff.title)."
        }
        return "Choose scope above and tap Scan to find blurry photos."
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
            if let scopeTitle = effectiveScope?.title, !items.isEmpty {
                Text("Results for \(scopeTitle)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            if let eff = effectiveScope, scope != eff {
                Text("Tap \(items.isEmpty ? "Scan" : "Reload") to scan \(scope.title)")
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

    private var listContent: some View {
        List {
            Section {
                Text("Blurry, out-of-focus, or accidental photos. Tap preview to see full size.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    selectablePhotoRow(index: index, item: item)
                }
            }
            if !selectedToDelete.isEmpty {
                Section {
                    Button("Delete \(selectedToDelete.count) selected", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                }
            }
        }
    }

    private func selectablePhotoRow(index: Int, item: PhotoItem) -> some View {
        let isSelected = selectedToDelete.contains(item.id)
        return HStack {
            AssetThumbnailView(asset: item.asset, library: library, size: CGSize(width: 60, height: 60))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Text(item.creationDate?.formatted(date: .abbreviated, time: .omitted) ?? "—")
                .font(.subheadline)
            Spacer()
            Button {
                groupPreviewTrigger = BlurryGroupPreviewTrigger(initialIndex: index)
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

    private func runScan() async {
        let scanScope = scope
        deletionManager.startNewDeletionRun()
        isLoading = true
        isAnalyzing = false
        errorMessage = nil
        items = []
        library.clearImageCache()
        do {
            let photos = try await library.fetchPhotos(scope: scanScope)
            isLoading = false
            if photos.isEmpty {
                effectiveScope = scanScope
                if adManager.isPremium {
                    resultStore.save(scope: scanScope, assetIds: [])
                }
                return
            }
            isAnalyzing = true
            items = await bestPhotoService.filterLowQuality(from: photos, threshold: 0.4) { done, total in
                Task { @MainActor in scanProgress = (done, total) }
            }
            effectiveScope = scanScope
            isAnalyzing = false

            if adManager.isPremium {
                resultStore.save(scope: scanScope, assetIds: items.map(\.id))
            }
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            isAnalyzing = false
        }
    }

    private func loadPersistedIfPremium() async {
        guard adManager.isPremium else { return }
        guard items.isEmpty else { return }
        guard let persisted = resultStore.load() else { return }

        applyScope(persisted.scope)
        effectiveScope = persisted.scope
        items = await library.fetchPhotoItems(identifiers: persisted.assetIds)
    }

    private func applyScope(_ newScope: ScanScope) {
        switch newScope {
        case .recent(let days):
            scopeOption = .recent
            if days != 30 {
                selectedYear = nil
            }
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
        let assets = items.filter { selectedToDelete.contains($0.id) }.map(\.asset)
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
        items.removeAll { selectedToDelete.contains($0.id) }
        selectedToDelete.removeAll()
    }
}

private struct BlurryGroupPreviewTrigger: Identifiable {
    let initialIndex: Int
    var id: Int { initialIndex }
}
