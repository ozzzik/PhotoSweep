//
//  PhotosCleanupApp.swift
//  PhotosCleanup
//
//  Ad-supported iOS photo cleanup: duplicates, same-day groups, best photo.
//

import GoogleMobileAds
import SwiftUI

extension Notification.Name {
    /// Posted on the main queue after `MobileAds.shared.start` completes — banner loads are safer after this.
    static let googleMobileAdsStartCompleted = Notification.Name("GoogleMobileAdsStartCompleted")
}

@main
struct PhotosCleanupApp: App {
    init() {
        MobileAds.shared.start { _ in
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .googleMobileAdsStartCompleted, object: nil)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
