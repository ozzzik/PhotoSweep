//
//  AppReviewManager.swift
//  PhotosCleanup
//
//  Tracks when to ask for App Store review. Call tryRequestReview() after positive moments
//  (e.g. post-cleanup). Uses StoreKit requestReview; system may or may not show the dialog.
//
//  First prompt: after enough launches + at least one cleanup.
//  Later prompts: every N usage events (launch or cleanup tap), with a minimum cooldown between asks.
//

import Foundation
import StoreKit

@MainActor
final class AppReviewManager: ObservableObject {
    private let defaults = UserDefaults.standard

    private enum Key {
        static let launchCount = "appReviewManager.launchCount"
        static let cleanupCompleteCount = "appReviewManager.cleanupCompleteCount"
        static let lastReviewRequestDate = "appReviewManager.lastReviewRequestDate"
        static let totalUsageEvents = "appReviewManager.totalUsageEvents"
        static let lastPromptAtUsageEvent = "appReviewManager.lastPromptAtUsageEvent"
    }

    private let minLaunchesBeforeFirstPrompt = 3
    private let minCleanupsBeforeFirstPrompt = 1
    /// After the first prompt, ask again after this many usage events (launches + completed cleanups).
    private let usageEventsBetweenPrompts = 6
    /// Minimum days between review requests (repeat path). Apple may still cap how often the dialog appears.
    private let minDaysBetweenPrompts = 30

    /// Call on launch (e.g. from RootView or App delegate).
    func recordLaunch() {
        let count = defaults.integer(forKey: Key.launchCount)
        defaults.set(count + 1, forKey: Key.launchCount)
        incrementUsageEvent()
    }

    /// Call when user completes a cleanup (taps Done on Cleanup complete).
    func recordCleanupComplete() {
        let count = defaults.integer(forKey: Key.cleanupCompleteCount)
        defaults.set(count + 1, forKey: Key.cleanupCompleteCount)
        incrementUsageEvent()
    }

    private func incrementUsageEvent() {
        let t = defaults.integer(forKey: Key.totalUsageEvents)
        defaults.set(t + 1, forKey: Key.totalUsageEvents)
    }

    /// Returns true if we're allowed to ask for a review (caller should then invoke requestReview).
    func shouldRequestReview() -> Bool {
        let launches = defaults.integer(forKey: Key.launchCount)
        let cleanups = defaults.integer(forKey: Key.cleanupCompleteCount)
        let totalUsage = defaults.integer(forKey: Key.totalUsageEvents)
        let lastPromptAt = defaults.integer(forKey: Key.lastPromptAtUsageEvent)
        let lastDate = defaults.object(forKey: Key.lastReviewRequestDate) as? Date
        let daysSince: Int = {
            guard let lastDate else { return 999 }
            return Calendar.current.dateComponents([.day], from: lastDate, to: Date()).day ?? 999
        }()

        if lastDate == nil {
            guard launches >= minLaunchesBeforeFirstPrompt else { return false }
            guard cleanups >= minCleanupsBeforeFirstPrompt else { return false }
            return true
        }

        guard daysSince >= minDaysBetweenPrompts else { return false }
        guard totalUsage - lastPromptAt >= usageEventsBetweenPrompts else { return false }
        return true
    }

    /// Call after the user has triggered a positive moment. Updates cooldown and usage baseline.
    func markReviewRequested() {
        defaults.set(Date(), forKey: Key.lastReviewRequestDate)
        defaults.set(defaults.integer(forKey: Key.totalUsageEvents), forKey: Key.lastPromptAtUsageEvent)
    }
}
