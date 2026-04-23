//
//  HomeView.swift
//  PhotosCleanup
//
//  Dashboard: hero, mode cards, scan setup → scanning, last activity, banner.
//

import SwiftUI
import Photos

struct HomeView: View {
    @StateObject private var library: PhotoLibraryService
    @StateObject private var duplicateService: DuplicateDetectionService
    @StateObject private var bestPhotoService: BestPhotoService
    @StateObject private var similarGroupingService: SimilarGroupingService
    @ObservedObject var deletionManager: DeletionManager
    @ObservedObject var analyticsService: AnalyticsService
    @ObservedObject var adManager: AdManager
    @ObservedObject var lastSmartScanResult: LastSmartScanResult
    @Binding var selectedTab: RootView.Tab
    @StateObject private var orchestrator: CleanupOrchestrator

    @State private var photoCount: Int?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var scanConfig = ScanConfig.default()
    @State private var showScanSetup = false
    @State private var showScanning = false
    @State private var showScanComplete = false
    @State private var lastResultSummary: (duplicates: Int, similar: Int) = (0, 0)
    @State private var showInterruptedScanAlert = false
    @State private var interruptedJobState: ScanJobState?
    @State private var pendingScanConfig: ScanConfig?

    init(
        deletionManager: DeletionManager,
        analyticsService: AnalyticsService,
        adManager: AdManager,
        lastSmartScanResult: LastSmartScanResult,
        selectedTab: Binding<RootView.Tab>
    ) {
        let lib = PhotoLibraryService()
        let dup = DuplicateDetectionService(photoLibrary: lib)
        let best = BestPhotoService(photoLibrary: lib)
        let sim = SimilarGroupingService(photoLibrary: lib)
        let orch = CleanupOrchestrator(
            photoLibrary: lib,
            duplicateService: dup,
            bestPhotoService: best,
            similarGroupingService: sim,
            deletionManager: deletionManager
        )
        _library = StateObject(wrappedValue: lib)
        _duplicateService = StateObject(wrappedValue: dup)
        _bestPhotoService = StateObject(wrappedValue: best)
        _similarGroupingService = StateObject(wrappedValue: sim)
        _deletionManager = ObservedObject(wrappedValue: deletionManager)
        _analyticsService = ObservedObject(wrappedValue: analyticsService)
        _adManager = ObservedObject(wrappedValue: adManager)
        _lastSmartScanResult = ObservedObject(wrappedValue: lastSmartScanResult)
        _selectedTab = selectedTab
        _orchestrator = StateObject(wrappedValue: orch)
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading library…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage {
                    ContentUnavailableView(
                        "Couldn't load photos",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                } else {
                    scrollContent
                }
            }
            .navigationTitle(AppConfig.appName)
            .navigationBarTitleDisplayMode(.large)
            .task { await loadCount() }
            .task { await lastSmartScanResult.loadPersisted(photoLibrary: library) }
            .sheet(isPresented: $showScanSetup) {
                ScanSetupView(
                    config: $scanConfig,
                    adManager: adManager,
                    onStartScan: {
                        if let state = orchestrator.loadInterruptedJobState(),
                           state.lastUpdated.timeIntervalSinceNow > -24 * 3600 {
                            interruptedJobState = state
                            pendingScanConfig = scanConfig
                            showInterruptedScanAlert = true
                        } else {
                            startScanNow(config: scanConfig)
                        }
                    },
                    onDismiss: { showScanSetup = false }
                )
            }
            .alert("Previous scan interrupted", isPresented: $showInterruptedScanAlert) {
                Button("Start new scan") {
                    if let config = pendingScanConfig {
                        startScanNow(config: config)
                    }
                    pendingScanConfig = nil
                    interruptedJobState = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingScanConfig = nil
                    interruptedJobState = nil
                }
            } message: {
                if let state = interruptedJobState {
                    let pct = state.totalAssetCount > 0 ? Int(100 * state.processedCount / state.totalAssetCount) : 0
                    Text("A previous scan stopped at \(pct)% (\(state.processedCount) of \(state.totalAssetCount) photos). Start a new scan from the beginning?")
                }
            }
            .fullScreenCover(isPresented: $showScanning) {
                scanningCover
            }
            .alert("Scan complete", isPresented: $showScanComplete) {
                Button("Done") { showScanComplete = false }
                Button("Review duplicates") {
                    showScanComplete = false
                    selectedTab = .duplicates
                }
                Button("Review similar") {
                    showScanComplete = false
                    selectedTab = .similar
                }
            } message: {
                Text("Found \(lastResultSummary.duplicates) duplicate clusters and \(lastResultSummary.similar) similar groups. Other categories (Screenshots, Junk, etc.) are available from their cards on Home.")
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomStickyBanner
            }
        }
    }

    private var scanningCover: some View {
        Group {
            switch orchestrator.phase {
            case .idle:
                ProgressView("Preparing…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .scanning(let progress):
                ScanningView(progress: progress) {
                    orchestrator.cancelScan()
                    showScanning = false
                }
            case .results(let result):
                ScanCompleteTransitionView(
                    duplicateCount: result.duplicateClusters.count,
                    similarCount: result.similarDayGroups.count,
                    onDismiss: {
                        lastSmartScanResult.set(from: result)
                        lastResultSummary = (result.duplicateClusters.count, result.similarDayGroups.count)
                        showScanning = false
                        showScanComplete = true
                    }
                )
            case .error(let message):
                VStack(spacing: 16) {
                    Text(message)
                        .multilineTextAlignment(.center)
                        .padding()
                    Button("Close") {
                        showScanning = false
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                heroSection

                if lastSmartScanResult.reclaimableEstimateBytes > 0 {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Possible reclaimable space")
                            .font(.subheadline.weight(.semibold))
                        Text("Up to \(lastSmartScanResult.reclaimableEstimateFormatted) if you removed every suggested extra (non-best) photo in your current duplicate and similar results. Estimates only; nothing deletes automatically.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }

                if let lastScan = orchestrator.lastFullScanDate {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass.circle.fill")
                            .foregroundStyle(.secondary)
                        Text("Last scan: \(lastScan, style: .relative) ago")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Cleanup modes")
                    .sectionHeaderStyle()
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    modeCard("Smart cleanup", subtitle: "Recommended", icon: "sparkles") { showScanSetup = true }
                    modeCard("Duplicates", icon: "doc.on.doc") { showScanSetup = true }
                    modeCard("Similar shots", icon: "square.stack.3d.up") { showScanSetup = true }
                    NavigationLink {
                        ScreenshotsListView(deletionManager: deletionManager, adManager: adManager)
                    } label: {
                        modeCardLabel(title: "Screenshots & utility", subtitle: nil, icon: "camera.viewfinder")
                    }
                    .buttonStyle(.plain)
                    NavigationLink {
                        LargeVideosListView(deletionManager: deletionManager, adManager: adManager)
                    } label: {
                        modeCardLabel(title: "Large videos", subtitle: nil, icon: "video.fill")
                    }
                    .buttonStyle(.plain)
                    NavigationLink {
                        LowQualityListView(deletionManager: deletionManager, adManager: adManager)
                    } label: {
                        modeCardLabel(title: "Low-quality older", subtitle: nil, icon: "photo.badge.exclamationmark")
                    }
                    .buttonStyle(.plain)
                    NavigationLink {
                        BlurryAndAccidentalListView(deletionManager: deletionManager, adManager: adManager)
                    } label: {
                        modeCardLabel(title: "Blurry & accidental", subtitle: nil, icon: "camera.metering.unknown")
                    }
                    .buttonStyle(.plain)
                    NavigationLink {
                        JunkListView(deletionManager: deletionManager, adManager: adManager)
                    } label: {
                        modeCardLabel(title: "Junk & clutter", subtitle: nil, icon: "trash.slash")
                    }
                    .buttonStyle(.plain)
                    NavigationLink {
                        TripListView(deletionManager: deletionManager, adManager: adManager)
                    } label: {
                        modeCardLabel(title: "Trips", subtitle: "Vacation, city, landmark", icon: "airplane")
                    }
                    .buttonStyle(.plain)
                    NavigationLink {
                        ManualSwipeEntryView(deletionManager: deletionManager, adManager: adManager)
                    } label: {
                        modeCardLabel(title: "Manual swipe", subtitle: nil, icon: "hand.draw")
                    }
                    .buttonStyle(.plain)
                }

                if let session = orchestrator.lastSession {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Last cleanup: \(session.date, style: .relative) ago · \(formatBytes(session.bytesFreed)) freed.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding()
        }
    }

    /// Pinned above the home indicator; stays on screen while `ScrollView` content moves.
    private var bottomStickyBanner: some View {
        Group {
            if !adManager.isPremium {
                BannerAdWaterfallView(isPremium: adManager.isPremium)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 50, idealHeight: 66, maxHeight: 90)
                    .background(Color(.systemBackground))
            }
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "photo.stack.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(AppTheme.accentGradient)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reclaim your space")
                        .font(.title2.weight(.bold))
                    Text("Find duplicates, similar shots & clutter")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            .background(AppTheme.heroGradient)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private func modeCard(_ title: String, subtitle: String? = nil, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            modeCardLabel(title: title, subtitle: subtitle, icon: icon)
        }
        .buttonStyle(.plain)
    }

    private func modeCardLabel(title: String, subtitle: String?, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(AppTheme.accentGradient)
            Text(title)
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.leading)
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .styledCard()
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func startScanNow(config: ScanConfig) {
        showScanSetup = false
        showScanning = true
        analyticsService.trackSessionStart()
        deletionManager.startNewDeletionRun()
        orchestrator.startSession(config: config)
    }

    private func loadCount() async {
        isLoading = true
        errorMessage = nil
        do {
            let items = try await library.fetchAllPhotos()
            photoCount = items.count
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// Shown when phase switches to .results so user can dismiss scanning cover.
private struct ScanCompleteTransitionView: View {
    let duplicateCount: Int
    let similarCount: Int
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(AppTheme.accent)
            Text("Scan complete")
                .font(.title2.weight(.semibold))
            Text("\(duplicateCount) duplicate clusters · \(similarCount) similar groups")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Done") {
                onDismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    let sub = SubscriptionManager()
    let ad = AdManager(subscriptionManager: sub)
    HomeView(
        deletionManager: DeletionManager(),
        analyticsService: AnalyticsService(),
        adManager: ad,
        lastSmartScanResult: LastSmartScanResult(adManager: ad),
        selectedTab: .constant(RootView.Tab.home)
    )
}
