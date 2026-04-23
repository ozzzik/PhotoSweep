//
//  ScanScope.swift
//  PhotosCleanup
//
//  Where to focus each cleanup run: recent, by year, custom range, or entire library.
//

import Foundation

/// Scope of the photo library to scan for cleanup.
enum ScanScope: Equatable, Hashable, Sendable {
    /// Last N days (e.g. 7 or 30).
    case recent(days: Int)
    /// Current calendar month (archive-friendly; less iCloud download).
    case thisMonth
    /// Current calendar year (archive-friendly).
    case thisYear
    /// Single calendar year.
    case year(Int)
    /// Custom date range (start inclusive, end inclusive).
    case custom(from: Date, to: Date)
    /// Entire library (slower; recommend when plugged in).
    case entireLibrary

    var title: String {
        switch self {
        case .recent(let days): return "Last \(days) days"
        case .thisMonth: return "This month"
        case .thisYear: return "This year"
        case .year(let y): return "\(y)"
        case .custom(let from, let to):
            let f = formatShort(from)
            let t = formatShort(to)
            return "\(f) – \(t)"
        case .entireLibrary: return "All photos"
        }
    }

    private func formatShort(_ d: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: d)
    }
}

/// User-facing scope option for the scan setup UI (e.g. segmented control).
enum ScanScopeOption: String, CaseIterable, Identifiable {
    case recent = "Recent (30 days)"
    case thisMonth = "This month"
    case thisYear = "This year"
    case byYear = "By year"
    case custom = "Specific dates"
    case all = "All photos"
    public var id: String { rawValue }

    /// Scopes that require PhotoSweep Premium (shown disabled in the menu for free users).
    /// **By year** is free; **Specific dates** and **All photos** stay premium.
    public var requiresPremium: Bool {
        switch self {
        case .recent, .thisMonth, .thisYear, .byYear: false
        case .custom, .all: true
        }
    }

    /// Menu row title; locked rows include “(premium)” when the user is not subscribed.
    public func scopeMenuLabel(userHasPremium: Bool) -> String {
        if requiresPremium, !userHasPremium {
            return "\(rawValue) (premium)"
        }
        return rawValue
    }
}
