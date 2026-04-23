//
//  ScanSetupView.swift
//  PhotosCleanup
//
//  "What do you want to clean?" — Scope (segmented) + Modes (checklist) + Scan now.
//

import SwiftUI

struct ScanSetupView: View {
    @Binding var config: ScanConfig
    @ObservedObject var adManager: AdManager
    var onStartScan: () -> Void
    var onDismiss: () -> Void

    @State private var scopeOption: ScanScopeOption = .recent
    @State private var selectedYear: Int?
    @State private var customFrom: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var customTo: Date = Date()
    @State private var showAdvanced = false
    @State private var yearsWithCounts: [(year: Int, count: Int)] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    scopeSection
                    modesSection
                    if showAdvanced {
                        advancedSection
                    }
                    Button(showAdvanced ? "Hide advanced filters" : "Show advanced filters") {
                        showAdvanced.toggle()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("What do you want to clean?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                scanButton
            }
        }
        .task { await loadYears() }
        .onChange(of: scopeOption) { _, _ in syncScopeToConfig() }
        .onChange(of: selectedYear) { _, _ in syncScopeToConfig() }
        .onChange(of: customFrom) { _, _ in syncScopeToConfig() }
        .onChange(of: customTo) { _, _ in syncScopeToConfig() }
        .onChange(of: adManager.isPremium) { _, isPremium in
            guard !isPremium else { return }
            if scopeOption == .custom || scopeOption == .all {
                scopeOption = .thisYear
                selectedYear = nil
                syncScopeToConfig()
            }
        }
    }

    private var scopeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scope")
                .sectionHeaderStyle()
            ScanScopePicker(scopeOption: $scopeOption, adManager: adManager)

            if scopeOption == .byYear {
                yearPicker
            }
            if adManager.isPremium, scopeOption == .custom {
                customRangePicker
            }

            Text("Photos in iCloud download as needed. Use a smaller scope (e.g. This month) to match your pace.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .styledCard()
    }

    private var yearPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(yearsWithCounts, id: \.year) { y in
                    Button {
                        selectedYear = y.year
                    } label: {
                        Text("\(y.year) (\(y.count.formatted()))")
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(selectedYear == y.year ? AppTheme.accent : Color.secondary.opacity(0.2))
                            .foregroundStyle(selectedYear == y.year ? .white : .primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var customRangePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            DatePicker("From", selection: $customFrom, displayedComponents: .date)
            DatePicker("To", selection: $customTo, displayedComponents: .date)
        }
    }

    private var modesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cleanup modes")
                .sectionHeaderStyle()
            ForEach(Array(CleanupMode.allCases), id: \.id) { mode in
                let isOn = config.enabledModes.contains(mode)
                Button {
                    if isOn {
                        config.enabledModes.remove(mode)
                    } else {
                        config.enabledModes.insert(mode)
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isOn ? AppTheme.accent : Color.secondary)
                        Image(systemName: mode.systemImage)
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .center)
                        Text(mode.shortLabel)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .styledCard()
    }

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Protect Favorites", isOn: Binding(
                get: { config.protectFavorites },
                set: { config.protectFavorites = $0 }
            ))
            Toggle("Exclude Shared Albums", isOn: Binding(
                get: { config.excludeSharedAlbums },
                set: { config.excludeSharedAlbums = $0 }
            ))
        }
    }

    private var scanButton: some View {
        Button {
            syncScopeToConfig()
            onStartScan()
        } label: {
            Text("Scan now")
                .frame(maxWidth: .infinity)
                .padding()
        }
        .buttonStyle(.borderedProminent)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private func syncScopeToConfig() {
        switch scopeOption {
        case .recent:
            config.scope = .recent(days: 30)
        case .thisMonth:
            config.scope = .thisMonth
        case .thisYear:
            config.scope = .thisYear
        case .byYear:
            if let y = selectedYear ?? yearsWithCounts.first?.year {
                config.scope = .year(y)
            } else {
                config.scope = .thisYear
            }
        case .custom:
            if adManager.isPremium {
                config.scope = .custom(from: customFrom, to: customTo)
            } else {
                config.scope = .thisYear
            }
        case .all:
            config.scope = adManager.isPremium ? .entireLibrary : .thisYear
        }
    }

    private func loadYears() async {
        let lib = PhotoLibraryService()
        let years = await lib.fetchYearsWithCounts()
        yearsWithCounts = years
        if selectedYear == nil, let first = years.first {
            selectedYear = first.year
        }
    }
}

// Fix: "Show advanced filters" button had .toggle which is wrong — it's a method. Use {} or ().