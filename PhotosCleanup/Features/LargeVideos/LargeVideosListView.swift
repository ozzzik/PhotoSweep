//
//  LargeVideosListView.swift
//  PhotosCleanup
//
//  Lists heavy videos (estimated size), largest first; select and delete.
//

import SwiftUI
import Photos

/// Minimum estimated size for the list (matches `fetchLargeVideos`). Three tiers: 2 MB+, 10 MB+, 50 MB+.
private enum LargeVideoSizeThreshold: Int64, CaseIterable, Identifiable {
    case mb2 = 2_097_152 // 2 × 1024²
    case mb10 = 10_485_760 // 10 × 1024²
    case mb50 = 52_428_800 // 50 × 1024²

    var id: Int64 { rawValue }

    /// Short labels for the segmented control.
    var label: String {
        switch self {
        case .mb2: return "2 MB+"
        case .mb10: return "10 MB+"
        case .mb50: return "50 MB+"
        }
    }

    static func matchingStoredBytes(_ bytes: Int64?) -> LargeVideoSizeThreshold {
        guard let bytes else { return .mb10 }
        if let exact = Self.allCases.first(where: { $0.rawValue == bytes }) {
            return exact
        }
        // Legacy 25 / 50 / 100 MB tiers → closest new tier
        if bytes >= 104_857_600 { return .mb50 }
        if bytes >= 52_428_800 { return .mb50 }
        if bytes >= 26_214_400 { return .mb10 }
        if bytes >= 10_485_760 { return .mb10 }
        if bytes >= 2_097_152 { return .mb2 }
        return .mb10
    }
}

struct LargeVideosListView: View {
    @ObservedObject var deletionManager: DeletionManager
    @ObservedObject var adManager: AdManager
    @StateObject private var library = PhotoLibraryService()
    @StateObject private var resultStore = LargeVideosResultStore()
    @State private var items: [VideoItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var scope: ScanScope = .recent(days: 30)
    @State private var sizeThreshold: LargeVideoSizeThreshold = .mb2
    /// Avoids `onChange` refetch while applying persisted threshold from disk.
    @State private var suppressThresholdChangeReload = true
    @State private var showDeleteConfirmation = false
    @State private var selectedToDelete: Set<String> = []
    @State private var showCleanupComplete = false
    @State private var cleanupItemCount = 0
    @State private var cleanupBytes: Int64 = 0
    @State private var pendingCancelUndo: (() -> Void)?
    @State private var previewItem: PreviewableAsset?
    @State private var showQuotaExceededAlert = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading videos…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                ContentUnavailableView("Couldn't load", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if items.isEmpty {
                ContentUnavailableView(
                    "No large videos",
                    systemImage: "video.fill",
                    description: Text(
                        "No videos estimated over \(byteCountString(sizeThreshold.rawValue)) in the selected range."
                    )
                )
            } else {
                listContent
            }
        }
        .navigationTitle("Large videos")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Load") { Task { await load(forceRefresh: true) } }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            thresholdSection
        }
        .task {
            suppressThresholdChangeReload = true
            await load(forceRefresh: false)
            suppressThresholdChangeReload = false
        }
        .onChange(of: sizeThreshold) { _, _ in
            guard !suppressThresholdChangeReload else { return }
            Task { await load(forceRefresh: true) }
        }
        .sheet(item: $previewItem) { previewable in
            FullPhotoPreviewView(asset: previewable.asset, library: library) {
                previewItem = nil
            }
        }
        .confirmationDialog("Delete \(selectedToDelete.count) videos?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) { performDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(DeletionCopy.confirmationMessage)
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
            Text("Free users can delete up to 100 photos/videos per run. Unlock PhotoSweep Premium in Settings to delete more.")
        }
    }

    private var thresholdSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Minimum size (estimated)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Picker("Minimum size", selection: $sizeThreshold) {
                ForEach(LargeVideoSizeThreshold.allCases) { t in
                    Text(t.label).tag(t)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
    }

    private func selectableVideoRow(item: VideoItem) -> some View {
        let isSelected = selectedToDelete.contains(item.id)
        return HStack {
            AssetThumbnailView(asset: item.asset, library: library, size: CGSize(width: 60, height: 60))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(byteCountString(item.estimatedBytes))
                    .font(.headline)
                Text(item.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? "—")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                previewItem = PreviewableAsset(asset: item.asset)
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

    private var listContent: some View {
        List {
            Section {
                ForEach(items) { item in
                    selectableVideoRow(item: item)
                }
            } footer: {
                Text("Sizes are estimates from length and resolution — close enough to pick what to delete or review.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
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

    private func byteCountString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func load(forceRefresh: Bool) async {
        deletionManager.startNewDeletionRun()
        isLoading = true
        errorMessage = nil

        if !forceRefresh, adManager.isPremium, let persisted = resultStore.load() {
            scope = persisted.scope
            sizeThreshold = LargeVideoSizeThreshold.matchingStoredBytes(persisted.minEstimatedBytes)
            var loaded = await library.fetchVideoItems(identifiers: persisted.videoIds)
            loaded.sort { $0.estimatedBytes > $1.estimatedBytes }
            items = loaded
            isLoading = false
            return
        }

        do {
            items = try await library.fetchLargeVideos(scope: scope, minEstimatedBytes: sizeThreshold.rawValue)
        } catch {
            errorMessage = error.localizedDescription
        }
        if adManager.isPremium, errorMessage == nil {
            resultStore.save(scope: scope, videoIds: items.map(\.id), minEstimatedBytes: sizeThreshold.rawValue)
        }
        isLoading = false
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
