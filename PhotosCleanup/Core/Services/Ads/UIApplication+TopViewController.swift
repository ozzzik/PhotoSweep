//
//  UIApplication+TopViewController.swift
//  PhotosCleanup
//
//  Finds a UIViewController suitable for presenting full-screen ads (Unity / AdMob).
//  Avoids SwiftUI PresentationHostingController while its view is leaving the hierarchy.
//

import UIKit

extension UIApplication {
    /// Best-effort key window for the active scene (iOS 13+).
    var adsKeyWindow: UIWindow? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }

    /// Deepest presented controller (legacy; can be a SwiftUI host that is mid-dismiss).
    func adsTopViewController(base: UIViewController? = nil) -> UIViewController? {
        let baseVC = base ?? adsKeyWindow?.rootViewController
        if let nav = baseVC as? UINavigationController {
            return adsTopViewController(base: nav.visibleViewController)
        }
        if let tab = baseVC as? UITabBarController {
            return adsTopViewController(base: tab.selectedViewController)
        }
        if let presented = baseVC?.presentedViewController {
            return adsTopViewController(base: presented)
        }
        return baseVC
    }

    /// Prefer this for Unity/AdMob full-screen ads: only descends into `presentedViewController`
    /// when that view is still in a window (avoids “view is not in the window hierarchy”).
    func adsStablePresenterForFullscreenAd() -> UIViewController? {
        guard let root = adsKeyWindow?.rootViewController else { return nil }
        return adsStablePresenter(from: root)
    }

    private func adsStablePresenter(from vc: UIViewController) -> UIViewController {
        if let nav = vc as? UINavigationController, let visible = nav.visibleViewController {
            return adsStablePresenter(from: visible)
        }
        if let tab = vc as? UITabBarController, let selected = tab.selectedViewController {
            return adsStablePresenter(from: selected)
        }
        if let presented = vc.presentedViewController {
            if presented.isViewLoaded, presented.view.window != nil {
                return adsStablePresenter(from: presented)
            }
        }
        return vc
    }
}
