//
//  BestPhotoService.swift
//  PhotosCleanup
//
//  Suggests the best photo in a group using Vision: lens smudge, face quality (when available).
//  Extensible for aesthetic scoring (WWDC24 Vision APIs) and optional cloud models later.
//

import Foundation
import Vision
import Photos
import UIKit

@MainActor
final class BestPhotoService: ObservableObject {
    private let photoLibrary: PhotoLibraryService

    init(photoLibrary: PhotoLibraryService) {
        self.photoLibrary = photoLibrary
    }

    /// Pick the best index from a group of photos. Higher score = better.
    func suggestBestIndex(in items: [PhotoItem]) async -> Int? {
        guard !items.isEmpty else { return nil }
        var scores: [Int: Float] = [:]
        for (index, item) in items.enumerated() {
            let score = await scorePhoto(item)
            scores[index] = score
        }
        return scores.max(by: { $0.value < $1.value }).map(\.key)
    }

    /// Returns photos with quality score below threshold (for low-quality cleanup). Progress: (current, total).
    func filterLowQuality(from items: [PhotoItem], threshold: Float = 0.4, progress: (@Sendable (Int, Int) -> Void)? = nil) async -> [PhotoItem] {
        var result: [PhotoItem] = []
        let total = items.count
        for (i, item) in items.enumerated() {
            let score = await scorePhoto(item)
            if score < threshold {
                result.append(item)
            }
            progress?(i + 1, total)
        }
        return result
    }

    /// Quality score (0...1) for a single photo. Used by JunkDetectionService and filterLowQuality.
    func qualityScore(for item: PhotoItem) async -> Float {
        await scorePhoto(item)
    }

    /// Quality score from an already-loaded CGImage (avoids loading the same asset twice). Use when caller has loadImageForVision result.
    func qualityScore(cgImage: CGImage) async -> Float {
        if #available(iOS 26.0, *) {
            var total: Float = 1.0
            if let smudgeScore = await detectLensSmudge(cgImage: cgImage) {
                total -= smudgeScore
            }
            return max(0, min(1, total))
        }
        return 1.0
    }

    /// Single-photo quality score (0...1). Uses downscaled image (1024) to avoid memory pressure—never full-size.
    /// On iOS < 26, lens smudge unavailable; returns 1.0 without loading.
    private func scorePhoto(_ item: PhotoItem) async -> Float {
        if #available(iOS 26.0, *) {
            guard let cgImage = await photoLibrary.loadImageForVision(for: item.asset, targetLongEdge: 1024) else { return 0 }
            var total: Float = 1.0
            if let smudgeScore = await detectLensSmudge(cgImage: cgImage) {
                total -= smudgeScore
            }
            return max(0, min(1, total))
        }
        return 1.0
    }

    @available(iOS 26.0, *)
    private func detectLensSmudge(cgImage: CGImage) async -> Float? {
        let request = DetectLensSmudgeRequest(.revision1)
        do {
            let observation = try await request.perform(on: cgImage)
            return observation.confidence
        } catch {
            return nil
        }
    }
}
