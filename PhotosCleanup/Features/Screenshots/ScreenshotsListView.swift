//
//  ScreenshotsListView.swift
//  PhotosCleanup
//
//  Lists screenshot assets for the scope. Filter by age, select and delete.
//

import SwiftUI
import Photos

struct ScreenshotsListView: View {
    @ObservedObject var deletionManager: DeletionManager
    @ObservedObject var adManager: AdManager
    @StateObject private var library = PhotoLibraryService()
    @StateObject private var resultStore = ScreenshotsResultStore()
    @State private var items: [PhotoItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var scope: ScanScope = .recent(days: 30)
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
                ProgressView("Loading screenshots…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                ContentUnavailableView("Couldn't load", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if items.isEmpty {
                ContentUnavailableView(
                    "No screenshots",
                    systemImage: "camera.viewfinder",
                    description: Text("No screenshots in the selected range.")
                )
            } else {
                listContent
            }
        }
        .navigationTitle("Screenshots")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Load") { Task { await load() } }
            }
        }
        .task { await load() }
        .sheet(item: $previewItem) { previewable in
            FullPhotoPreviewView(asset: previewable.asset, library: library) {
                previewItem = nil
            }
        }
        .confirmationDialog("Delete \(selectedToDelete.count) screenshots?", isPresented: $showDeleteConfirmation) {
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
            Text("Free users can delete up to 100 photos per run. Unlock PhotoSweep Premium in Settings to delete more.")
        }
    }

    private func selectablePhotoRow(item: PhotoItem) -> some View {
        let isSelected = selectedToDelete.contains(item.id)
        return HStack {
            AssetThumbnailView(asset: item.asset, library: library, size: CGSize(width: 60, height: 60))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading) {
                Text(item.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? "—")
                    .font(.subheadline)
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
                    selectablePhotoRow(item: item)
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

    private func load() async {
        deletionManager.startNewDeletionRun()
        isLoading = true
        errorMessage = nil

        if adManager.isPremium, let persisted = resultStore.load() {
            scope = persisted.scope
            items = await library.fetchPhotoItems(identifiers: persisted.assetIds)
            isLoading = false
            return
        }

        do {
            items = try await library.fetchScreenshots(scope: scope)
        } catch {
            errorMessage = error.localizedDescription
        }
        if adManager.isPremium && errorMessage == nil {
            resultStore.save(scope: scope, assetIds: items.map(\.id))
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
