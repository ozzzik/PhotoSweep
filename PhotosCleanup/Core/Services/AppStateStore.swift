//
//  AppStateStore.swift
//  PhotosCleanup
//
//  Persists onboarding completion and app preferences (UserDefaults).
//

import Foundation

@MainActor
final class AppStateStore: ObservableObject {
    private let defaults = UserDefaults.standard

    enum Key {
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }

    @Published var hasCompletedOnboarding: Bool {
        didSet {
            defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding)
        }
    }

    init() {
        self.hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)
    }

    func markOnboardingComplete() {
        hasCompletedOnboarding = true
    }
}
