//
//  ManualSwipeEntryView.swift
//  PhotosCleanup
//
//  Loads recent photos then presents ManualSwipeView.
//

import SwiftUI

struct ManualSwipeEntryView: View {
    @ObservedObject var deletionManager: DeletionManager
    @ObservedObject var adManager: AdManager
    @StateObject private var library = PhotoLibraryService()
    @StateObject private var resultStore = ManualSwipeResultStore()
    @State private var items: [PhotoItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading photos…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                ContentUnavailableView("Couldn't load", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if items.isEmpty {
                ContentUnavailableView("No photos", systemImage: "photo", description: Text("No photos in the selected range."))
            } else {
                ManualSwipeView(
                    items: items,
                    library: library,
                    deletionManager: deletionManager,
                    adManager: adManager,
                    onComplete: { dismiss() }
                )
            }
        }
        .navigationTitle("Manual swipe")
        .task {
            await loadPhotos()
        }
    }

    private func loadPhotos() async {
        deletionManager.startNewDeletionRun()
        isLoading = true
        errorMessage = nil
        do {
            if adManager.isPremium, let persisted = resultStore.load() {
                items = await library.fetchPhotoItems(identifiers: persisted.assetIds)
                isLoading = false
                return
            }

            items = try await library.fetchPhotos(scope: .recent(days: 30))
            if items.count > 500 {
                items = Array(items.prefix(500))
            }

            if adManager.isPremium {
                resultStore.save(scope: .recent(days: 30), assetIds: items.map(\.id))
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
