//
//  AttConsentController.swift
//  PhotosCleanup
//
//  App Tracking Transparency: request once when main app is shown, before loading ads.
//

import Foundation
import AppTrackingTransparency

@MainActor
final class AttConsentController: ObservableObject {
    @Published private(set) var hasRequested = false
    @Published private(set) var authorizationStatus: ATTrackingManager.AuthorizationStatus = .notDetermined

    /// Call when main app UI is shown (after onboarding). Requests ATT if status is .notDetermined; then ads can be loaded.
    func requestIfNeeded() async {
        let status = ATTrackingManager.trackingAuthorizationStatus
        authorizationStatus = status
        if status == .notDetermined {
            let newStatus: ATTrackingManager.AuthorizationStatus = await withCheckedContinuation { continuation in
                ATTrackingManager.requestTrackingAuthorization { s in
                    continuation.resume(returning: s)
                }
            }
            authorizationStatus = newStatus
        }
        hasRequested = true
    }
}
