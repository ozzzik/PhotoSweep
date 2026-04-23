//
//  AssetThumbnailView.swift
//  PhotosCleanup
//
//  Async thumbnail for a PHAsset. Used in lists and grids.
//

import SwiftUI
import Photos

struct AssetThumbnailView: View {
    let asset: PHAsset
    @ObservedObject var library: PhotoLibraryService
    var size: CGSize = CGSize(width: 120, height: 120)

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .overlay(ProgressView())
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .task(id: asset.localIdentifier) {
            image = await library.loadImage(for: asset, targetSize: size, contentMode: .aspectFill)
        }
    }
}
