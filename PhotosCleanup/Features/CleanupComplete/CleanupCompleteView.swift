//
//  CleanupCompleteView.swift
//  PhotosCleanup
//
//  Post-delete screen: "You freed X GB", Undo (15s), Clean another / Done. Interstitial trigger on Done.
//

import SwiftUI
import StoreKit

struct CleanupCompleteView: View {
    var itemCount: Int
    var bytesFreed: Int64
    var adManager: AdManager?
    var onUndo: () -> Void
    var onCleanAnother: () -> Void
    var onDone: () -> Void

    @Environment(\.requestReview) private var requestReview
    @EnvironmentObject private var reviewManager: AppReviewManager

    @State private var undoSecondsLeft: Int = 15

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(AppTheme.accent)
            Text("Nice! You freed \(formattedBytes).")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("\(itemCount) items moved to Recently Deleted. You can recover them there for about 30 days. If you use iCloud Photos, they were removed from all devices.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if undoSecondsLeft > 0 {
                Button("Undo (\(undoSecondsLeft)s)") {
                    onUndo()
                    onDone()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }

            Spacer()
            VStack(spacing: 12) {
                Button("Clean another area") {
                    reviewManager.recordCleanupComplete()
                    tryRequestReviewAfterDone()
                    onDone()
                    onCleanAnother()
                    // After dismiss starts; AdManager defers interstitial so SwiftUI hierarchy is stable.
                    adManager?.showInterstitialIfEligible()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)

                Button("Done") {
                    reviewManager.recordCleanupComplete()
                    tryRequestReviewAfterDone()
                    onDone()
                    adManager?.showInterstitialIfEligible()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .task {
            for _ in 0..<15 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if undoSecondsLeft > 0 { undoSecondsLeft -= 1 }
            }
        }
    }

    private var formattedBytes: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytesFreed)
    }

    /// Ask for App Store review after a short delay (not as direct response to tap).
    private func tryRequestReviewAfterDone() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard reviewManager.shouldRequestReview() else { return }
            reviewManager.markReviewRequested()
            requestReview()
        }
    }
}

#Preview {
    CleanupCompleteView(
        itemCount: 42,
        bytesFreed: 2_100_000_000,
        adManager: nil,
        onUndo: {},
        onCleanAnother: {},
        onDone: {}
    )
    .environmentObject(AppReviewManager())
}
