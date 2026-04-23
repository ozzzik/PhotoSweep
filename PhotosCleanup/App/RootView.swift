//
//  RootView.swift
//  PhotosCleanup
//
//  Onboarding → Main shell (Home, Duplicates, Similar). Handles photo library permission.
//

import SwiftUI
import Foundation
import Photos

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: Tab = .home
    @State private var backgroundEnteredAt: Date?
    @State private var sessionResetId = UUID()
    @StateObject private var photoPermission = PhotoPermissionController()
    @StateObject private var appState = AppStateStore()
    @StateObject private var analyticsService = AnalyticsService()
    @StateObject private var deletionManager: DeletionManager
    @StateObject private var subscriptionManager: SubscriptionManager
    @StateObject private var adManager: AdManager
    @StateObject private var reviewManager = AppReviewManager()
    @StateObject private var attConsent = AttConsentController()
    @StateObject private var lastSmartScanResult: LastSmartScanResult

    init() {
        let analytics = AnalyticsService()
        _analyticsService = StateObject(wrappedValue: analytics)
        _deletionManager = StateObject(wrappedValue: DeletionManager(analyticsService: analytics))
        let sub = SubscriptionManager()
        _subscriptionManager = StateObject(wrappedValue: sub)
        let ad = AdManager(subscriptionManager: sub, analyticsService: analytics)
        _adManager = StateObject(wrappedValue: ad)
        _lastSmartScanResult = StateObject(wrappedValue: LastSmartScanResult(adManager: ad))
    }

    enum Tab: String, CaseIterable {
        case home = "Home"
        case duplicates = "Duplicates"
        case similar = "Similar"
        case settings = "Settings"
    }

    var body: some View {
        Group {
            if !appState.hasCompletedOnboarding {
                OnboardingView(
                    onRequestPhotoAccess: {
                        await photoPermission.requestAuthorization()
                    },
                    onComplete: {
                        analyticsService.trackOnboardingComplete()
                        appState.markOnboardingComplete()
                    }
                )
            } else if photoPermission.isAuthorized == false && photoPermission.hasAsked == true {
                PermissionDeniedView(onRetry: photoPermission.requestAuthorization)
            } else if photoPermission.isAuthorized == true {
                ZStack(alignment: .top) {
                    TabView(selection: $selectedTab) {
                    HomeView(
                        deletionManager: deletionManager,
                        analyticsService: analyticsService,
                        adManager: adManager,
                        lastSmartScanResult: lastSmartScanResult,
                        selectedTab: $selectedTab
                    )
                        .tabItem { Label(Tab.home.rawValue, systemImage: "photo.on.rectangle.angled") }
                        .tag(Tab.home)

                    DuplicatesListView(
                        deletionManager: deletionManager,
                        adManager: adManager,
                        lastSmartScanResult: lastSmartScanResult
                    )
                        .tabItem { Label(Tab.duplicates.rawValue, systemImage: "doc.on.doc") }
                        .tag(Tab.duplicates)

                    SimilarGroupsListView(
                        deletionManager: deletionManager,
                        adManager: adManager,
                        lastSmartScanResult: lastSmartScanResult
                    )
                        .tabItem { Label(Tab.similar.rawValue, systemImage: "square.stack.3d.up") }
                        .tag(Tab.similar)

                    NavigationStack {
                        SettingsView(
                            adManager: adManager,
                            subscriptionManager: subscriptionManager,
                            lastSmartScanResult: lastSmartScanResult
                        )
                    }
                    .tabItem { Label(Tab.settings.rawValue, systemImage: "gearshape") }
                    .tag(Tab.settings)
                }
                    .id(sessionResetId)
                .tint(AppTheme.accent)

                    if photoPermission.isLimited {
                        limitedAccessBanner
                    }
                }
                .environmentObject(reviewManager)
            } else {
                ProgressView("Checking photo access…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            if appState.hasCompletedOnboarding, photoPermission.isAuthorized == nil {
                await photoPermission.requestAuthorization()
            }
        }
        .task(id: (appState.hasCompletedOnboarding && photoPermission.isAuthorized == true)) {
            guard appState.hasCompletedOnboarding, photoPermission.isAuthorized == true else { return }
            reviewManager.recordLaunch()
            await attConsent.requestIfNeeded()
            adManager.prepareAds()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                analyticsService.flush()
                backgroundEnteredAt = Date()
            }
            if newPhase == .active {
                if appState.hasCompletedOnboarding {
                    photoPermission.refreshAuthorizationFromSystem()
                }
                defer { backgroundEnteredAt = nil }
                // Free tier: long background clears in-memory results (premium unchanged).
                guard !adManager.isPremium, let enteredAt = backgroundEnteredAt else { return }
                let elapsed = Date().timeIntervalSince(enteredAt)
                if elapsed >= AppConfig.freeTierBackgroundSessionResetSeconds {
                    lastSmartScanResult.clearSessionSmartResults()
                    deletionManager.startNewDeletionRun()
                    sessionResetId = UUID()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .premiumUnlockRequested)) { _ in
            selectedTab = .settings
        }
    }

    private var limitedAccessBanner: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "photo.badge.plus")
                Text("You're only scanning selected photos. Expand access to scan all.")
                    .font(.caption)
                Spacer()
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    Link("Settings", destination: settingsURL)
                        .font(.caption.weight(.medium))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.orange.opacity(0.2))
            .padding(.horizontal)
            .padding(.top, 8)
            Spacer()
        }
        .allowsHitTesting(true)
    }
}

// MARK: - Photo library permission

@MainActor
final class PhotoPermissionController: ObservableObject {
    @Published var isAuthorized: Bool? = nil
    @Published var hasAsked: Bool = false
    /// True when user chose "Select Photos…" (limited access). Show banner to expand access.
    @Published var isLimited: Bool = false

    init() {
        applySystemAuthorizationStatus(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    private func applySystemAuthorizationStatus(_ status: PHAuthorizationStatus) {
        switch status {
        case .authorized:
            isAuthorized = true
            isLimited = false
            hasAsked = true
        case .limited:
            isAuthorized = true
            isLimited = true
            hasAsked = true
        case .denied, .restricted:
            isAuthorized = false
            isLimited = false
            hasAsked = true
        case .notDetermined:
            isAuthorized = nil
            isLimited = false
            hasAsked = false
        @unknown default:
            isAuthorized = false
            isLimited = false
            hasAsked = true
        }
    }

    func requestAuthorization() async {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .notDetermined:
            hasAsked = true
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            applySystemAuthorizationStatus(newStatus)
        default:
            hasAsked = true
            applySystemAuthorizationStatus(status)
        }
    }

    /// Call when returning from Settings / Limited library changes so `isLimited` and access state stay accurate.
    func refreshAuthorizationFromSystem() {
        applySystemAuthorizationStatus(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }
}

// MARK: - Permission denied state

struct PermissionDeniedView: View {
    var onRetry: () async -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("Photo Access Needed")
                .font(.title2.weight(.semibold))
            Text("Open Settings and allow access to your photo library so we can find duplicates and group similar photos.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

#Preview("Root") {
    RootView()
}
