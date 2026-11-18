import SwiftUI

// Standard tab bar. The system places it: along the bottom on most iPhones,
// down the side on iPhone Duo's outer display and in landscape, and as a
// sidebar where there's room. Navigation stays outside each tab's content,
// as the Duo guidelines ask.
struct RootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(BoardStore.self) private var store
    @Environment(ProAccess.self) private var pro
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("onboarded") private var onboarded = false
    @State private var showOnboarding = false
    // Counts each return from the background once, like app_opened
    @State private var wasInBackground = true

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            Tab("Board", systemImage: "square.on.square", value: AppRouter.Tab.board) {
                BoardView()
            }
            Tab("Feed", systemImage: "rectangle.stack", value: AppRouter.Tab.feed) {
                FeedView()
            }
            Tab("Today", systemImage: "sun.max", value: AppRouter.Tab.today) {
                TodayView()
            }
            Tab("Settings", systemImage: "gearshape", value: AppRouter.Tab.settings) {
                SettingsView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .fullScreenCover(item: $router.todayCard) { card in
            TodayFullScreen(card: card)
        }
        .sheet(isPresented: Binding(
            get: { router.weeklyRecapSource != nil },
            set: { if !$0 { router.weeklyRecapSource = nil } }
        )) {
            RecapView(source: router.weeklyRecapSource ?? "today")
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView {
                onboarded = true
                showOnboarding = false
                pro.noteOnboardingFinished()
            }
        }
        .sheet(isPresented: Binding(
            get: { router.paywallSource != nil },
            set: { if !$0 { router.paywallSource = nil } }
        )) {
            PaywallView(source: router.paywallSource ?? "unknown")
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active:
                guard wasInBackground else { return }
                wasInBackground = false
                Task { await appOpened() }
            case .background:
                wasInBackground = true
            default:
                break
            }
        }
        .onAppear {
            guard !onboarded else { return }
            // People who already have a board don't need the tour
            if store.items.isEmpty { showOnboarding = true } else { onboarded = true }
        }
    }
}

extension RootView {
    // Checks the plan again, and shows the one-time paywall from the second
    // open after onboarding when the board has a few things on it
    private func appOpened() async {
        await pro.refresh()
        guard onboarded, !showOnboarding else { return }
        guard pro.noteAppOpen(itemCount: store.items.count) else { return }
        // Let the board settle on screen first
        try? await Task.sleep(for: .seconds(1.5))
        guard scenePhase == .active, router.paywallSource == nil, router.todayCard == nil, !showOnboarding else { return }
        pro.markSoftPaywallShown()
        router.paywallSource = "soft"
    }
}

extension DailyCard: Identifiable {
    var id: String { text + (image ?? "") }
}

#Preview {
    let store = BoardStore()
    let sync = SyncService(store: store)
    RootView()
        .environment(store)
        .environment(sync)
        .environment(BoardLibrary(store: store, sync: sync))
        .environment(Reminders())
        .environment(AppRouter.shared)
        .environment(ProAccess.shared)
}
