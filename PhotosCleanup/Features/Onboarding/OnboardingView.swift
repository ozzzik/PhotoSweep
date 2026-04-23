//
//  OnboardingView.swift
//  PhotosCleanup
//
//  Welcome → Permission explainer → Allow Photos. No cloud; user confirms every delete.
//

import SwiftUI
@preconcurrency import Photos

struct OnboardingView: View {
    /// Called when user taps "Allow Photos access"; caller should request permission then call onComplete().
    var onRequestPhotoAccess: () async -> Void
    var onComplete: () -> Void

    @State private var step: Step = .welcome

    enum Step {
        case welcome
        case permission
    }

    var body: some View {
        VStack(spacing: 0) {
            if step == .welcome {
                welcomeStep
            } else {
                permissionStep
            }
        }
        .animation(.easeInOut, value: step)
    }

    private var welcomeStep: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "photo.stack.fill")
                .font(.system(size: 70))
                .foregroundStyle(AppTheme.accentGradient)
            Text(AppConfig.appName)
                .font(.largeTitle.weight(.bold))
            Text("Reclaim storage without losing your best memories. Everything's analyzed on your device.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Spacer()
            Button("Next") {
                step = .permission
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent)
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }

    private var permissionStep: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("Photo access")
                .font(.title2.weight(.semibold))
            VStack(alignment: .leading, spacing: 12) {
                bullet("We need access to your Photos library to find duplicates and similar shots.")
                bullet("We analyze on-device — your photos never leave your phone.")
                bullet("You confirm every delete; items go to Recently Deleted for 30 days.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)
            Spacer()
            Button("Allow Photos access") {
                Task {
                    await onRequestPhotoAccess()
                    onComplete()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent)
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(text)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    OnboardingView(onRequestPhotoAccess: { }, onComplete: { })
}
