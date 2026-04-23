//
//  CleanupMode.swift
//  PhotosCleanup
//
//  Cleanup modes user can enable per run: duplicates, similar, screenshots, etc.
//

import Foundation

/// A single cleanup mode that can be toggled in scan setup.
enum CleanupMode: String, CaseIterable, Identifiable, Sendable {
    case duplicates = "Duplicates"
    case similarShots = "Similar shots"
    case screenshotsAndUtility = "Screenshots & utility"
    case largeVideos = "Large videos"
    case lowQuality = "Low-quality older photos"
    case blurryAndAccidental = "Blurry & accidental"
    case junkAndClutter = "Junk & clutter"
    case trips = "Trips"
    case manualSwipe = "Manual swipe"

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .duplicates: return "Duplicates"
        case .similarShots: return "Similar shots"
        case .screenshotsAndUtility: return "Screenshots & utility"
        case .largeVideos: return "Large videos"
        case .lowQuality: return "Low-quality older photos"
        case .blurryAndAccidental: return "Blurry & accidental"
        case .junkAndClutter: return "Junk & clutter"
        case .trips: return "Trips"
        case .manualSwipe: return "Manual swipe"
        }
    }

    var systemImage: String {
        switch self {
        case .duplicates: return "doc.on.doc"
        case .similarShots: return "square.stack.3d.up"
        case .screenshotsAndUtility: return "camera.viewfinder"
        case .largeVideos: return "video.fill"
        case .lowQuality: return "photo.badge.exclamationmark"
        case .blurryAndAccidental: return "camera.metering.unknown"
        case .junkAndClutter: return "trash.slash"
        case .trips: return "airplane"
        case .manualSwipe: return "hand.draw"
        }
    }
}
