//
//  PremiumUnlockRouter.swift
//  PhotosCleanup
//
//  Simple navigation helper: quota alerts can request that the app route
//  the user to the Settings -> PhotoSweep Premium section.
//

import Foundation

extension Notification.Name {
    static let premiumUnlockRequested = Notification.Name("premiumUnlockRequested")
}

