//
//  ManualSwipeView.swift
//  PhotosCleanup
//
//  One photo at a time: swipe left = mark delete, swipe right = keep. Then review and delete.
//

import SwiftUI
import Photos

struct ManualSwipeView: View {
    let items: [PhotoItem]
    @ObservedObject var library: PhotoLibraryService
    @ObservedObject var deletionManager: DeletionManager
    @ObservedObject var adManager: AdManager
    var onComplete: () -> Void

    @State private var index: Int = 0
    @State private var toDelete: Set<String> = []
    @State private var showDeleteConfirmation = false
    @State private var showCleanupComplete = false
    @State private var pendingCancelUndo: (() -> Void)?
    @State private var showQuotaExceededAlert = false

    private var currentItem: PhotoItem? {
        items.indices.contains(index) ? items[index] : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            if let item = currentItem {
                ZStack {
                    AssetThumbnailView(
                        asset: item.asset,
                        library: library,
                        size: CGSize(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height - 180)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 50)
                            .onEnded { value in
                                if value.translation.width < -80 {
                                    toDelete.insert(item.id)
                                    advance()
                                } else if value.translation.width > 80 {
                                    advance()
                                }
                            }
                    )
                    VStack {
                        Text("Photo \(index + 1) of \(items.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(8)
                        Spacer()
                        HStack(spacing: 40) {
                            Button("Delete") {
                                toDelete.insert(item.id)
                                advance()
                            }
                            .foregroundStyle(.red)
                            Text("or swipe")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Button("Keep") {
                                advance()
                            }
                            .foregroundStyle(.blue)
                        }
                        .padding(.bottom, 24)
                    }
                }
            } else {
                finishView
            }
            if !toDelete.isEmpty && currentItem != nil {
                Text("Marked \(toDelete.count) to delete · \(estimatedBytes)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
        }
        .navigationTitle("Manual swipe")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete \(toDelete.count) photos?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                performDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(DeletionCopy.confirmationMessageWithUndoNext)
        }
        .sheet(isPresented: $showCleanupComplete) {
            if let count = Int(exactly: toDelete.count), count > 0 {
                CleanupCompleteView(
                    itemCount: count,
                    bytesFreed: estimatedBytesValue,
                    adManager: adManager,
                    onUndo: {
                        pendingCancelUndo?()
                        pendingCancelUndo = nil
                        showCleanupComplete = false
                    },
                    onCleanAnother: { showCleanupComplete = false; onComplete() },
                    onDone: { showCleanupComplete = false; onComplete() }
                )
            }
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

    private var finishView: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 50))
                .foregroundStyle(.green)
            Text("You marked \(toDelete.count) photos to delete")
                .font(.headline)
            if !toDelete.isEmpty {
                Text(estimatedBytes)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Delete \(toDelete.count) photos") {
                    showDeleteConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            Button("Done without deleting") {
                onComplete()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var estimatedBytes: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: estimatedBytesValue)
    }

    private var estimatedBytesValue: Int64 {
        let ids = Set(toDelete)
        let assets = items.filter { ids.contains($0.id) }.map(\.asset)
        return assets.reduce(0) { $0 + $1.estimatedStorageBytes }
    }

    private func advance() {
        if index + 1 < items.count {
            index += 1
        } else {
            index = items.count
        }
    }

    private func performDelete() {
        let assets = items.filter { toDelete.contains($0.id) }.map(\.asset)

        guard let scheduled = deletionManager.scheduleDeleteWithUndoWindow(
            assets: assets,
            isPremium: adManager.isPremium
        ) else {
            showQuotaExceededAlert = true
            return
        }

        pendingCancelUndo = scheduled.cancelUndo
        showCleanupComplete = true
    }
}
