//
//  ScanningView.swift
//  PhotosCleanup
//
//  Large progress, message, pause/cancel. "You can safely leave the app; we'll continue in the background."
//

import SwiftUI

struct ScanningView: View {
    let progress: ScanProgress
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 8)
                    .frame(width: 160, height: 160)
                Circle()
                    .trim(from: 0, to: progressFraction)
                    .stroke(AppTheme.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 160, height: 160)
                    .rotationEffect(.degrees(-90))
                Text("\(progress.current)")
                    .font(.title.weight(.bold))
            }
            Text(progress.message)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("Analyzing with on-device AI. You can safely leave the app; we'll continue in the background.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Cancel", role: .cancel) {
                onCancel()
            }
            .padding(.top, 16)
            Spacer()
            Text("Tip: plug in your phone to speed up the scan.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 24)
        }
    }

    private var progressFraction: CGFloat {
        guard progress.total > 0 else { return 0 }
        return min(1, CGFloat(progress.current) / CGFloat(progress.total))
    }
}

#Preview {
    ScanningView(
        progress: ScanProgress(current: 3215, total: 27430, message: "Scanning duplicates (3,215 / 27,430)"),
        onCancel: {}
    )
}
