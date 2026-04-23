//
//  SimilarGroupDetailView.swift
//  PhotosCleanup
//
//  Detail for one same-day similar group: thumbnails, best pick, keep/remove, delete.
//

import SwiftUI
import Photos

struct SimilarGroupDetailView: View {
    let group: SimilarGroup
    @ObservedObject var library: PhotoLibraryService
    @ObservedObject var bestPhotoService: BestPhotoService
    @ObservedObject var deletionManager: DeletionManager
    let isPremium: Bool
    var onDelete: (Set<Int>) -> Void
    var onDeleteWithUndo: (Int, Int64, @escaping () -> Void) -> Void
    var onAddToBatch: ((String, [PHAsset]) -> Void)?
    var onMarkReviewed: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var selectedToRemove: Set<Int> = []
    @State private var defaultedGroupId: String?
    @State private var showDeleteConfirmation = false
    @State private var groupPreviewTrigger: SimilarGroupPreviewTrigger?
    @State private var showQuotaExceededAlert = false

    var body: some View {
        List {
            Section {
                Text(group.date.formatted(date: .long, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 12) {
                    ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                        similarCell(index: index, item: item)
                    }
                }
            } header: {
                Text("Best shot keeps a green border; other shots are selected to remove (red) by default. Tap to change. Use the magnifier for full-screen preview.")
            }

            if group.suggestedBestIndex != nil {
                Section {
                    Button("Keep best only (remove others)") {
                        let best = group.suggestedBestIndex!
                        selectedToRemove = Set(group.items.indices).subtracting([best])
                        showDeleteConfirmation = true
                    }
                }
            }

            if !selectedToRemove.isEmpty {
                Section {
                    if let onAddToBatch {
                        Button {
                            let assets = selectedToRemove.map { group.items[$0].asset }
                            onAddToBatch(group.id, assets)
                            dismiss()
                        } label: {
                            Label("Add to batch (\(selectedToRemove.count) photos)", systemImage: "plus.circle")
                        }
                    }
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Text("Delete now (\(selectedToRemove.count) photos)")
                    }
                }
            }
        }
        .navigationTitle("Similar group")
        .confirmationDialog("Remove photos?", isPresented: $showDeleteConfirmation) {
            Button("Remove", role: .destructive) {
                performDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(DeletionCopy.confirmationMessage)
        }
        .onDisappear {
            onMarkReviewed?()
        }
        .alert("Deletion limit reached", isPresented: $showQuotaExceededAlert) {
            Button("Unlock Premium") {
                NotificationCenter.default.post(name: .premiumUnlockRequested, object: nil)
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text("Free users can delete up to 100 photos per run. Unlock PhotoSweep Premium in Settings to delete more.")
        }
        .sheet(item: $groupPreviewTrigger) { trigger in
            GroupPhotoPreviewView(
                items: group.items,
                initialIndex: trigger.initialIndex,
                selectedToRemove: $selectedToRemove,
                library: library
            ) {
                groupPreviewTrigger = nil
            }
        }
        .onAppear {
            if defaultedGroupId != group.id {
                defaultedGroupId = group.id
                selectedToRemove = GroupDefaultRemovalSelection.indicesToRemove(for: group)
            }
        }
    }

    private func similarCell(index: Int, item: PhotoItem) -> some View {
        let isMarkedForRemoval = selectedToRemove.contains(index)
        let borderColor: Color = isMarkedForRemoval ? .red : (selectedToRemove.isEmpty ? .gray.opacity(0.5) : .green)
        return ZStack(alignment: .topTrailing) {
            Button {
                if selectedToRemove.contains(index) {
                    selectedToRemove = selectedToRemove.subtracting([index])
                } else {
                    selectedToRemove = selectedToRemove.union([index])
                }
            } label: {
                ZStack(alignment: .bottomLeading) {
                    AssetThumbnailView(asset: item.asset, library: library, size: CGSize(width: 120, height: 120))
                        .aspectRatio(1, contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(borderColor, lineWidth: 3)
                        )
                    if group.suggestedBestIndex == index {
                        Text("Best")
                            .font(.caption2.weight(.bold))
                            .padding(4)
                            .background(.green.opacity(0.9))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .padding(6)
                    }
                }
            }
            .buttonStyle(.plain)
            Button {
                groupPreviewTrigger = SimilarGroupPreviewTrigger(initialIndex: index)
            } label: {
                Image(systemName: "magnifyingglass.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
            }
            .buttonStyle(.plain)
            .padding(4)
        }
    }

    private func performDelete() {
        let assets = selectedToRemove.map { group.items[$0].asset }
        let count = assets.count
        let bytesEstimate = assets.reduce(0) { $0 + $1.estimatedStorageBytes }

        guard let scheduled = deletionManager.scheduleDeleteWithUndoWindow(
            assets: assets,
            isPremium: isPremium
        ) else {
            showQuotaExceededAlert = true
            return
        }
        let cancelUndo = scheduled.cancelUndo
        onDeleteWithUndo(count, bytesEstimate, cancelUndo)
        onDelete(selectedToRemove)
        dismiss()
    }
}

private struct SimilarGroupPreviewTrigger: Identifiable {
    let initialIndex: Int
    var id: Int { initialIndex }
}
