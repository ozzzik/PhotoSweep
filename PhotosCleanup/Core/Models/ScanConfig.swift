//
//  ScanConfig.swift
//  PhotosCleanup
//
//  User's choices for a single cleanup run: scope + enabled modes + options.
//

import Foundation

/// Configuration for one cleanup scan: where to scan and which modes to run.
struct ScanConfig: Equatable, Sendable {
    /// Scope (resolved from ScanScopeOption when user picks "By year" or "Custom").
    var scope: ScanScope
    /// Modes enabled for this run.
    var enabledModes: Set<CleanupMode>
    /// Protect favorites (never auto-select for deletion).
    var protectFavorites: Bool = true
    /// Exclude shared albums / recently added from shared.
    var excludeSharedAlbums: Bool = false

    static func `default`() -> ScanConfig {
        ScanConfig(
            scope: .recent(days: 30),
            enabledModes: [.duplicates, .similarShots, .screenshotsAndUtility]
        )
    }
}
