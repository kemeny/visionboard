import SwiftUI

// Standard tab bar. The system places it: along the bottom on most iPhones,
// down the side on iPhone Duo's outer display and in landscape, and as a
// sidebar where there's room. Navigation stays outside each tab's content,
// as the Duo guidelines ask.
struct RootView: View {
    @Environment(AppRouter.self) private var router

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
    }
}

extension DailyCard: Identifiable {
    var id: String { text + (image ?? "") }
}

#Preview {
    let store = BoardStore()
    RootView()
        .environment(store)
        .environment(SyncService(store: store))
        .environment(Reminders())
        .environment(AppRouter.shared)
}
