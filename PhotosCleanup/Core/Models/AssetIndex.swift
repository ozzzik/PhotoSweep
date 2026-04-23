//
//  AssetIndex.swift
//  PhotosCleanup
//
//  Per-asset metadata for indexing: id, type, dates, flags, optional hashes/features.
//  Used for incremental and resumable scans.
//

import Foundation

/// Stored metadata for one asset (on-device only). Supports resumable scans.
struct AssetIndexRecord: Codable, Sendable {
    var assetId: String
    var creationDate: Date?
    var mediaType: String
    var isFavorite: Bool
    var lastScannedAt: Date?
    var scannedForDuplicates: Bool
    var scannedForSimilar: Bool
    var scannedForScreenshots: Bool
}

/// Persisted state for an in-progress or last-run scan (for resume).
struct ScanJobState: Codable, Sendable {
    var jobId: String
    var scopeDescription: String
    var modes: [String]
    var totalAssetCount: Int
    var processedCount: Int
    var lastUpdated: Date
}
