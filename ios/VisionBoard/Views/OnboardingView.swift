import SwiftUI

// First launch: what the app is for, a starting board, and the daily nudge.
// Three pages, each with one clear action, and Skip always available.
struct OnboardingView: View {
    @Environment(BoardStore.self) private var store
    @Environment(Reminders.self) private var reminders
    var onFinish: () -> Void

    @State private var page = 0
    // What the person picked on the starter page, for analytics
    @State private var templateID: String?
    @State private var startedBlank = false
    // Stops a second tap from finishing twice while reminders are set up
    @State private var finishing = false
    @State private var didFinish = false

    var body: some View {
        TabView(selection: $page) {
            welcome.tag(0)
            starter.tag(1)
            nudge.tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .overlay(alignment: .topTrailing) {
            Button("Skip", action: skip)
                .padding()
        }
        .interactiveDismissDisabled()
        .onAppear { Analytics.capture("onboarding_started") }
    }

    private func skip() {
        guard !didFinish else { return }
        didFinish = true
        Analytics.capture("onboarding_skipped", ["page": page])
        onFinish()
    }

    private func finish(reminders: Bool) {
        guard !didFinish else { return }
        didFinish = true
        var properties: [String: Any] = [
            "path": templateID == nil ? "blank" : "template",
            "reminders": reminders,
        ]
        if let templateID { properties["template"] = templateID }
        Analytics.capture("onboarding_completed", properties)
        onFinish()
    }

    private var welcome: some View {
        OnboardingPage(
            symbol: "sparkles",
            title: "See Your Goals Every Day",
            message: "Put the photos and words that pull you forward on a board. VisionBoard shows you one of each, every day."
        ) {
            Button {
                withAnimation { page = 1 }
            } label: {
                Text("Continue").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var starter: some View {
        OnboardingPage(
            symbol: "square.grid.2x2",
            title: "Start Your First Board",
            message: "Begin with an example you can change, or with blank paper."
        ) {
            VStack(spacing: 10) {
                ForEach(BoardTemplate.all) { template in
                    Button {
                        if templateID != template.id, let file = template.load() {
                            store.replaceBoard(with: file)
                            templateID = template.id
                            Analytics.capture("template_loaded", ["template": template.id, "surface": "onboarding"])
                        }
                        withAnimation { page = 2 }
                    } label: {
                        Label(template.name, systemImage: template.symbol)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                Button("Start Blank") {
                    if templateID != nil {
                        // Back from a template: clear it so the board really is blank
                        store.replaceBoard(with: BoardFile(version: 1, items: [], maxZIndex: 1))
                        templateID = nil
                    }
                    if !startedBlank {
                        startedBlank = true
                        Analytics.capture("blank_started", ["surface": "onboarding"])
                    }
                    withAnimation { page = 2 }
                }
                    .padding(.top, 4)
            }
        }
    }

    private var nudge: some View {
        OnboardingPage(
            symbol: "bell.badge",
            title: "A Daily Nudge",
            message: "Get one goal and one photo from your board each morning at 8. You can change the time in Settings."
        ) {
            VStack(spacing: 10) {
                Button {
                    guard !finishing else { return }
                    finishing = true
                    Task {
                        await reminders.enable(hour: 8, items: store.items)
                        finish(reminders: reminders.isEnabled)
                    }
                } label: {
                    Text("Turn On Reminders").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(finishing)
                Button("Not Now") { finish(reminders: false) }
                    .disabled(finishing)
            }
        }
    }
}

private struct OnboardingPage<Actions: View>: View {
    let symbol: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    @ViewBuilder var actions: Actions

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: symbol)
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(.tint)
                    .padding(.top, 72)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                actions
                    .padding(.top, 12)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 64)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
    }
}
