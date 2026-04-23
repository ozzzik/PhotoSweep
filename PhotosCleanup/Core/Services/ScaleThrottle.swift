//
//  ScaleThrottle.swift
//  PhotosCleanup
//
//  Throttle heavy work (e.g. Vision) on low battery or high thermal state. PRD §6: 100k–150k support.
//

import Foundation
import UIKit

enum ScaleThrottle {
    private static let throttleYieldSeconds: UInt64 = 1_500_000_000  // 1.5s
    private static let lowBatteryLevel: Float = 0.15  // 15%

    /// True when we should yield/slow down to avoid thermal or battery issues.
    @MainActor
    static func shouldThrottle() -> Bool {
        let processInfo = ProcessInfo.processInfo
        switch processInfo.thermalState {
        case .critical, .serious:
            return true
        case .fair, .nominal:
            break
        @unknown default:
            break
        }
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        guard device.batteryState == .unplugged else { return false }
        if device.batteryLevel >= 0 && device.batteryLevel <= lowBatteryLevel {
            return true
        }
        return false
    }

    /// If shouldThrottle(), yields for a short time so the device can cool / save battery.
    static func yieldIfNeeded() async {
        let throttle = await MainActor.run { shouldThrottle() }
        guard throttle else { return }
        #if DEBUG
        ScanDebugLogger.log("ScaleThrottle: yielding (thermal/battery)")
        #endif
        try? await Task.sleep(nanoseconds: throttleYieldSeconds)
    }
}
