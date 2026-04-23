//
//  IndexStore.swift
//  PhotosCleanup
//
//  Persists scan progress and optional per-asset index for resumable scans.
//

import Foundation

@MainActor
final class IndexStore: ObservableObject {
    private let defaults = UserDefaults.standard

    private enum Key {
        static let lastScanJob = "indexStore.lastScanJob"
        static let lastFullScanDate = "indexStore.lastFullScanDate"
    }

    /// Load saved scan job state for resume (if any).
    func loadScanJobState() -> ScanJobState? {
        guard let data = defaults.data(forKey: Key.lastScanJob),
              let state = try? JSONDecoder().decode(ScanJobState.self, from: data) else { return nil }
        return state
    }

    /// Save current scan progress so it can be resumed.
    func saveScanJobState(_ state: ScanJobState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Key.lastScanJob)
    }

    /// Clear saved job (e.g. when scan completes or user cancels).
    func clearScanJobState() {
        defaults.removeObject(forKey: Key.lastScanJob)
    }

    /// Last time we did a full library scan (for incremental "fetch modified since").
    var lastFullScanDate: Date? {
        get { defaults.object(forKey: Key.lastFullScanDate) as? Date }
        set { defaults.set(newValue, forKey: Key.lastFullScanDate) }
    }
}
