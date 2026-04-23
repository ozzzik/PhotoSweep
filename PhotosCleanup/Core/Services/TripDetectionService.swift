//
//  TripDetectionService.swift
//  PhotosCleanup
//
//  Detects trip/vacation photos: beach, city, landmark, mountain, etc.
//  Groups trip photos by date proximity (gap > N days = new trip).
//

import Foundation
import Vision
import Photos
import UIKit

/// A trip = photos taken within a contiguous date range (e.g. vacation, city day).
struct TripGroup: Identifiable, Sendable {
    let id: String
    let photos: [PhotoItem]
    let startDate: Date
    let endDate: Date

    var title: String {
        let cal = Calendar.current
        if cal.isDate(startDate, inSameDayAs: endDate) {
            return startDate.formatted(date: .abbreviated, time: .omitted)
        }
        return "\(startDate.formatted(date: .abbreviated, time: .omitted)) – \(endDate.formatted(date: .abbreviated, time: .omitted))"
    }
}

/// Vision labels that suggest trip/vacation photos.
private let tripKeywords = [
    "beach", "cityscape", "castle", "monument", "mountain", "waterfall",
    "cruise_ship", "amusement_park", "museum", "bridge", "cliff", "canyon",
    "coral_reef", "palm_tree", "pier", "arch", "belltower", "obelisk",
    "tower", "outdoor", "ocean"
]
private let tripConfidenceThreshold: Float = 0.35

@MainActor
final class TripDetectionService: ObservableObject {
    private let photoLibrary: PhotoLibraryService

    init(photoLibrary: PhotoLibraryService) {
        self.photoLibrary = photoLibrary
    }

    /// Groups trip photos by date proximity. Gap > gapDays = new trip.
    /// Photos sorted by date; each trip is a contiguous block.
    func groupIntoTrips(
        photos: [PhotoItem],
        gapDays: Int = 7
    ) -> [TripGroup] {
        let sorted = photos.sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
        guard !sorted.isEmpty else { return [] }
        let cal = Calendar.current
        var trips: [[PhotoItem]] = []
        var current: [PhotoItem] = []
        var lastDate: Date?
        for item in sorted {
            let d = item.creationDate ?? .distantPast
            if let last = lastDate {
                let days = cal.dateComponents([.day], from: last, to: d).day ?? 0
                if days > gapDays {
                    if !current.isEmpty { trips.append(current) }
                    current = [item]
                } else {
                    current.append(item)
                }
            } else {
                current = [item]
            }
            lastDate = d
        }
        if !current.isEmpty { trips.append(current) }
        return trips.enumerated().map { i, group in
            let dates = group.compactMap(\.creationDate)
            let start = dates.min() ?? .distantPast
            let end = dates.max() ?? .distantPast
            return TripGroup(
                id: "trip-\(i)-\(start.timeIntervalSince1970)",
                photos: group,
                startDate: start,
                endDate: end
            )
        }
    }

    /// Returns photos likely to be from trips (vacation, city day, travel).
    func filterTripPhotos(
        from items: [PhotoItem],
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async -> [PhotoItem] {
        var result: [PhotoItem] = []
        let total = items.count
        let throttleInterval = 25
        for (i, item) in items.enumerated() {
            if (i + 1) % throttleInterval == 0 {
                await ScaleThrottle.yieldIfNeeded()
            }
            let isTrip = await isTripPhoto(item)
            if isTrip { result.append(item) }
            progress?(i + 1, total)
        }
        return result
    }

    private func isTripPhoto(_ item: PhotoItem) async -> Bool {
        guard let cgImage = await photoLibrary.loadImageForVision(for: item.asset) else { return false }
        return await classifyAsTrip(cgImage: cgImage)
    }

    private func classifyAsTrip(cgImage: CGImage) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            let request = VNClassifyImageRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
            do {
                try handler.perform([request])
                guard let observations = request.results else { return false }
                for obs in observations {
                    guard obs.confidence >= tripConfidenceThreshold else { continue }
                    let id = obs.identifier.lowercased()
                    if tripKeywords.contains(where: { id.contains($0) }) {
                        return true
                    }
                }
                return false
            } catch {
                return false
            }
        }.value
    }
}
