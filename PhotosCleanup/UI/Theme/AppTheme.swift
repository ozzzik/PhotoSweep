//
//  AppTheme.swift
//  PhotosCleanup
//
//  Shared colors, typography, and styling for a cohesive look.
//

import SwiftUI

enum AppTheme {
    /// Primary accent — teal/emerald for a fresh, photo-cleanup feel.
    static let accent = Color(red: 0.2, green: 0.6, blue: 0.65)
    static let accentGradient = LinearGradient(
        colors: [Color(red: 0.25, green: 0.65, blue: 0.7), Color(red: 0.12, green: 0.52, blue: 0.58)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    /// Secondary accent for highlights.
    static let accentLight = Color(red: 0.35, green: 0.75, blue: 0.78)
    /// Card background — subtle tint.
    static let cardBackground = Color(red: 0.96, green: 0.98, blue: 0.99)
    static let cardBackgroundDark = Color(red: 0.18, green: 0.2, blue: 0.22)
    /// Card shadow for depth.
    static let cardShadow = Color.black.opacity(0.06)
    static let cardShadowDark = Color.black.opacity(0.3)
    /// Section header color.
    static let sectionHeader = Color.secondary
    /// Hero gradient for headers.
    static let heroGradient = LinearGradient(
        colors: [
            Color(red: 0.2, green: 0.6, blue: 0.65).opacity(0.15),
            Color(red: 0.2, green: 0.6, blue: 0.65).opacity(0.05)
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - View modifiers

struct StyledCardModifier: ViewModifier {
    @Environment(\.colorScheme) var colorScheme

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(colorScheme == .dark ? AppTheme.cardBackgroundDark : AppTheme.cardBackground)
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            LinearGradient(
                                colors: [
                                    AppTheme.accent.opacity(colorScheme == .dark ? 0.08 : 0.04),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.06), lineWidth: 1)
            )
            .shadow(color: colorScheme == .dark ? AppTheme.cardShadowDark : AppTheme.cardShadow, radius: 6, x: 0, y: 3)
    }
}

struct SectionHeaderModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.headline.weight(.semibold))
            .foregroundStyle(AppTheme.sectionHeader)
            .textCase(.uppercase)
            .tracking(0.5)
    }
}

extension View {
    func styledCard() -> some View {
        modifier(StyledCardModifier())
    }

    func sectionHeaderStyle() -> some View {
        modifier(SectionHeaderModifier())
    }
}
