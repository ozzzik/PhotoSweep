//
//  ScanScopePicker.swift
//  PhotosCleanup
//
//  Scope as a Menu (not menu-style Picker) so disabled rows use system grey styling.
//

import SwiftUI

struct ScanScopePicker: View {
    @Binding var scopeOption: ScanScopeOption
    @ObservedObject var adManager: AdManager

    var body: some View {
        Menu {
            ForEach(ScanScopeOption.allCases, id: \.id) { opt in
                let locked = !adManager.isPremium && opt.requiresPremium
                Button {
                    guard !locked else { return }
                    scopeOption = opt
                } label: {
                    HStack {
                        Text(opt.scopeMenuLabel(userHasPremium: adManager.isPremium))
                        Spacer(minLength: 8)
                        if locked {
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .disabled(locked)
            }
        } label: {
            HStack {
                Text(scopeOption.scopeMenuLabel(userHasPremium: adManager.isPremium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(Color(.secondarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .menuOrder(.fixed)
    }
}
