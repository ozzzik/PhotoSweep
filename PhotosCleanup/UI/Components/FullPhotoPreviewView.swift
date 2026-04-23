//
//  FullPhotoPreviewView.swift
//  PhotosCleanup
//
//  Full-screen photo preview. Single photo or swipeable group with keep/remove.
//

import SwiftUI
import AVKit
@preconcurrency import Photos

/// Wrapper so we can use .sheet(item:) with PHAsset.
struct PreviewableAsset: Identifiable {
    let asset: PHAsset
    var id: String { asset.localIdentifier }
}

struct FullPhotoPreviewView: View {
    let asset: PHAsset
    @ObservedObject var library: PhotoLibraryService
    var onDismiss: () -> Void

    @State private var image: UIImage?
    @State private var player: AVPlayer?
    @State private var loadFailed = false

    private var isVideo: Bool { asset.mediaType == .video }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if isVideo {
                if let player {
                    VideoPlayer(player: player)
                        .ignoresSafeArea()
                } else if loadFailed {
                    unableToLoadView(message: "Unable to load video", systemImage: "video.slash")
                } else {
                    ProgressView("Loading video…")
                        .tint(.white)
                        .foregroundStyle(.white)
                }
            } else if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if loadFailed {
                unableToLoadView(message: "Unable to load photo", systemImage: "photo.badge.exclamationmark")
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button("Close") {
                stopPlayback()
                onDismiss()
            }
            .font(.headline)
            .foregroundStyle(.white)
            .padding()
        }
        .onDisappear {
            stopPlayback()
        }
        .task(id: asset.localIdentifier) {
            await loadContent()
        }
    }

    private func unableToLoadView(message: String, systemImage: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(.white.opacity(0.8))
            Text(message)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.9))
            if isVideo {
                Text("If this clip is in iCloud only, wait on Wi‑Fi or open it in Photos once to download.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 24)
            }
        }
    }

    private func stopPlayback() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
    }

    private func loadContent() async {
        loadFailed = false
        image = nil
        stopPlayback()
        if isVideo {
            player = await library.loadAVPlayerForVideoPreview(asset: asset)
            if player == nil { loadFailed = true }
        } else {
            image = await library.loadFullSizeImageForPreview(for: asset)
            if image == nil { loadFailed = true }
        }
    }
}

// MARK: - Group preview with navigation and keep/remove

/// Full-screen swipeable preview for a group. Swipe between photos, mark Keep or Remove.
struct GroupPhotoPreviewView: View {
    let items: [PhotoItem]
    let initialIndex: Int
    @Binding var selectedToRemove: Set<Int>
    @ObservedObject var library: PhotoLibraryService
    var onDismiss: () -> Void

    @State private var currentIndex: Int

    init(items: [PhotoItem], initialIndex: Int, selectedToRemove: Binding<Set<Int>>, library: PhotoLibraryService, onDismiss: @escaping () -> Void) {
        self.items = items
        self.initialIndex = initialIndex
        _selectedToRemove = selectedToRemove
        self.library = library
        self.onDismiss = onDismiss
        _currentIndex = State(initialValue: initialIndex)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $currentIndex) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    GroupPhotoPageView(asset: item.asset, library: library)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .id(initialIndex)
            .onAppear {
                currentIndex = initialIndex
            }
            // Use safe area insets instead of a full-screen overlay so horizontal swipes reach the TabView.
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack {
                    Text("\(currentIndex + 1) of \(items.count)")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(8)
                        .background(.black.opacity(0.5))
                        .clipShape(Capsule())
                    Spacer()
                    Button("Close") {
                        onDismiss()
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                }
                .padding(.horizontal)
                .padding(.top, 4)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity)
                .background(Color.black.opacity(0.35))
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack(spacing: 24) {
                    Button {
                        selectedToRemove = selectedToRemove.subtracting([currentIndex])
                    } label: {
                        let isKeeping = !selectedToRemove.contains(currentIndex)
                        Label("Keep", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(isKeeping ? Color.green : Color.gray.opacity(0.5))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        selectedToRemove = selectedToRemove.union([currentIndex])
                    } label: {
                        let isDeleting = selectedToRemove.contains(currentIndex)
                        Label("Delete", systemImage: "trash.fill")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(isDeleting ? Color.red : Color.gray.opacity(0.5))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity)
                .background(Color.black.opacity(0.35))
            }
        }
    }
}

private struct GroupPhotoPageView: View {
    let asset: PHAsset
    @ObservedObject var library: PhotoLibraryService
    @State private var image: UIImage?
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if loadFailed {
                VStack(spacing: 12) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.title)
                        .foregroundStyle(.white.opacity(0.8))
                    Text("Unable to load")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.9))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: asset.localIdentifier) {
            loadFailed = false
            image = await library.loadFullSizeImageForPreview(for: asset)
            if image == nil { loadFailed = true }
        }
    }
}
