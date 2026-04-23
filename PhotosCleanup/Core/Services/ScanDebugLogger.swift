//
//  ScanDebugLogger.swift
//  PhotosCleanup
//
//  Debug logging and timing for scan pipeline. Use Console filter "Scan" to view.
//

import Foundation
import os.log

#if DEBUG
enum ScanDebugLogger {
    private static let log = Logger(subsystem: "com.whio.photoscleanup.app", category: "Scan")
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func log(_ message: String) {
        let ts = formatter.string(from: Date())
        print("[Scan \(ts)] \(message)")
    }

    static func logPhase(_ phase: String, duration: TimeInterval, extra: String = "") {
        let msg = extra.isEmpty ? "\(phase): \(String(format: "%.2f", duration))s" : "\(phase): \(String(format: "%.2f", duration))s (\(extra))"
        log(msg)
    }

    static func start(_ label: String, scope: String = "") {
        log("▶ START \(label)\(scope.isEmpty ? "" : " [\(scope)]")")
    }

    static func finish(_ label: String, duration: TimeInterval, summary: String = "") {
        log("■ FINISH \(label): \(String(format: "%.2f", duration))s\(summary.isEmpty ? "" : " — \(summary)")")
    }
}
#else
enum ScanDebugLogger {
    static func log(_ message: String) {}
    static func logPhase(_ phase: String, duration: TimeInterval, extra: String = "") {}
    static func start(_ label: String, scope: String = "") {}
    static func finish(_ label: String, duration: TimeInterval, summary: String = "") {}
}
#endif
