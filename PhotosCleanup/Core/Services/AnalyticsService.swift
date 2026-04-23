//
//  AnalyticsService.swift
//  PhotosCleanup
//
//  Privacy-respecting events only: session, mode usage, items deleted, bytes freed, ad events.
//

import Foundation

struct AnalyticsEvent {
    let name: String
    let params: [String: String]
    let timestamp: Date
}

@MainActor
final class AnalyticsService: ObservableObject {
    private var eventQueue: [AnalyticsEvent] = []

    func trackSessionStart() {
        enqueue("session_start", [:])
    }

    func trackCleanupCompleted(itemsDeleted: Int, bytesFreed: Int64, modes: Set<CleanupMode> = []) {
        enqueue("cleanup_completed", [
            "items_deleted": "\(itemsDeleted)",
            "bytes_freed": "\(bytesFreed)",
            "modes": modes.map(\.id).joined(separator: ",")
        ])
    }

    func trackAdShown(type: String) {
        enqueue("ad_shown", ["type": type])
    }

    func trackOnboardingComplete() {
        enqueue("onboarding_complete", [:])
    }

    private func enqueue(_ name: String, _ params: [String: String]) {
        eventQueue.append(AnalyticsEvent(name: name, params: params, timestamp: Date()))
    }

    /// Flush queued events (e.g. log for debugging or send to backend). Clears the queue.
    func flush() {
        let formatter = ISO8601DateFormatter()
        for event in eventQueue {
            let paramsStr = event.params.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            print("[Analytics] \(event.name) \(paramsStr) @ \(formatter.string(from: event.timestamp))")
        }
        eventQueue.removeAll()
    }
}
