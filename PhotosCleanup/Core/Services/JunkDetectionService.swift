//
//  JunkDetectionService.swift
//  PhotosCleanup
//
//  Detects junk/clutter: receipts, documents, supermarket photos, badly taken (blur, accidental).
//

import Foundation
import Vision
import Photos
import UIKit

/// Document-like keywords (tightened: avoid "text"/"sign" which catch people with signs).
private let junkDocumentKeywords = ["document", "receipt", "form", "paper", "invoice", "menu", "bill", "statement"]
/// Keywords that indicate people – if present with high confidence, we exclude from junk.
private let peopleKeywords = ["person", "people", "face", "portrait", "selfie", "child", "adult"]
private let junkQualityThreshold: Float = 0.40

@MainActor
final class JunkDetectionService: ObservableObject {
    private let photoLibrary: PhotoLibraryService
    private let bestPhotoService: BestPhotoService

    init(photoLibrary: PhotoLibraryService, bestPhotoService: BestPhotoService) {
        self.photoLibrary = photoLibrary
        self.bestPhotoService = bestPhotoService
    }

    /// Returns photos likely to be junk: document/receipt-like or low quality (badly taken).
    func filterJunk(
        from items: [PhotoItem],
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async -> [PhotoItem] {
        var result: [PhotoItem] = []
        let total = items.count
        for (i, item) in items.enumerated() {
            let isJunk = await isJunkPhoto(item)
            if isJunk { result.append(item) }
            progress?(i + 1, total)
        }
        return result
    }

    private func isJunkPhoto(_ item: PhotoItem) async -> Bool {
        guard let cgImage = await photoLibrary.loadImageForVision(for: item.asset, targetLongEdge: 1024) else { return false }
        let (hasPeople, looksLikeDoc) = await classifyImage(cgImage: cgImage)
        if hasPeople { return false }
        let quality = await bestPhotoService.qualityScore(cgImage: cgImage)
        if quality < junkQualityThreshold && !hasPeople { return true }
        if looksLikeDoc { return true }
        return false
    }

    /// Returns (hasPeople, looksLikeDocument). Excludes people photos from junk.
    private func classifyImage(cgImage: CGImage) async -> (hasPeople: Bool, looksLikeDocument: Bool) {
        await Task.detached(priority: .userInitiated) {
            let request = VNClassifyImageRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
            do {
                try handler.perform([request])
                guard let observations = request.results else { return (false, false) }
                var hasPeople = false
                var looksLikeDoc = false
                for obs in observations {
                    guard obs.confidence > 0.3 else { continue }
                    let id = obs.identifier.lowercased()
                    if peopleKeywords.contains(where: { id.contains($0) }) {
                        hasPeople = true
                    }
                    if junkDocumentKeywords.contains(where: { id.contains($0) }) {
                        looksLikeDoc = true
                    }
                }
                return (hasPeople, looksLikeDoc)
            } catch {
                return (false, false)
            }
        }.value
    }
}