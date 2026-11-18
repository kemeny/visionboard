import PhotosUI
import SwiftUI

// First launch. The goal is the moment of truth: seeing your own goal on your
// Lock Screen on day one. One clear action per page, and Skip always there.
//
// The "onboarding-goals" flag picks the flow. "control" keeps the old tour
// (welcome, a starter template, the daily nudge) as a baseline; anything else
// gets the new one: welcome, your goals, a photo for each, put it on your
// screen, the daily nudge.
struct OnboardingView: View {
    @Environment(BoardStore.self) private var store
    @Environment(SyncService.self) private var sync
    @Environment(Reminders.self) private var reminders
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @AppStorage("canvas-paper") private var paper: PaperColor = .moleskine
    var onFinish: () -> Void

    enum Variant: String {
        case control, test
    }

    // Pages of the new flow
    enum Step: String {
        case welcome, goals, examples, photos, screen, nudge
    }

    private static let flagKey = "onboarding-goals"
    // The variant is kept, so a relaunch mid-onboarding (after a trip to
    // Photos or Settings) shows the same flow and doesn't start it twice
    private static let variantDefaultsKey = "onboarding-variant"
    private static let controlSteps = ["welcome", "templates", "nudge"]
    private static let placeholders: [LocalizedStringKey] = ["Run a half marathon", "Visit Japan", "Save for a home"]

    // Decided once, after the welcome page had a moment to fetch flags
    @State private var variant: Variant?
    // What analytics records: "control", "test", or "unassigned" when the
    // flags hadn't arrived yet (those people see the control flow and are
    // left out of the experiment)
    @State private var variantLabel = "unassigned"
    // New flow: the page shown and the way back
    @State private var step: Step = .welcome
    @State private var history: [Step] = []
    // Old flow: shown after its welcome, on its own paged TabView
    @State private var showControl = false
    @State private var controlPage = 1
    @State private var lastLoggedStep: String?

    // What the person picked, for analytics: goals, template or blank
    @State private var path = "none"
    @State private var templateID: String?
    @State private var startedBlank = false

    // Goals page
    @State private var goals = ["", "", ""]
    @FocusState private var focusedGoal: Int?
    @State private var committedGoals: [String] = []
    @State private var goalIDs: [String] = []

    // Photos page
    @State private var pickedPhotos: [PhotosPickerItem] = []
    @State private var photoIDs: [String] = []
    @State private var importing = false
    @State private var photoError: String?

    // Screen page
    @State private var wallpaper: UIImage?
    @State private var savingWallpaper = false
    @State private var wallpaperSaved = false
    @State private var wallpaperStatus: String?
    @State private var showWidgetGuide = false

    // Stops a second tap from finishing twice while reminders are set up
    @State private var finishing = false
    @State private var didFinish = false

    var body: some View {
        Group {
            if showControl {
                controlFlow
            } else {
                newFlow
            }
        }
        .overlay(alignment: .topTrailing) {
            Button("Skip", action: skip)
                .padding()
        }
        .interactiveDismissDisabled()
        .onAppear { logStep("welcome") }
        .task {
            // The welcome page looks the same in both flows, so a first
            // launch gets a moment for its flags to arrive before choosing
            for _ in 0..<6 {
                if variant != nil { return }
                if Analytics.flag(Self.flagKey) != nil { break }
                try? await Task.sleep(for: .milliseconds(250))
            }
            lockVariant()
        }
        .onChange(of: step) { _, new in logStep(new.rawValue) }
        .onChange(of: controlPage) { _, new in
            if showControl, Self.controlSteps.indices.contains(new) { logStep(Self.controlSteps[new]) }
        }
        .onChange(of: pickedPhotos) { _, picked in
            guard !picked.isEmpty else { return }
            pickedPhotos = []
            Task { await importPhotos(picked) }
        }
        .sheet(isPresented: $showWidgetGuide) {
            WidgetGuide()
        }
    }

    // MARK: Flows

    private var newFlow: some View {
        ZStack {
            page(for: step)
                .id(step)
                .transition(.opacity)
        }
        .overlay(alignment: .topLeading) {
            if !history.isEmpty {
                Button(action: back) {
                    Label("Back", systemImage: "chevron.backward")
                        .labelStyle(.iconOnly)
                        .padding(8)
                }
                .padding(8)
            }
        }
    }

    @ViewBuilder
    private func page(for step: Step) -> some View {
        switch step {
        case .welcome: welcome { continueFromWelcome() }
        case .goals: goalsPage
        case .examples: starter(after: { picked in go(to: picked ? .screen : .nudge) })
        case .photos: photosPage
        case .screen: screenPage
        case .nudge: nudge
        }
    }

    // The old tour, kept as the experiment's baseline
    private var controlFlow: some View {
        TabView(selection: $controlPage) {
            welcome { withAnimation { controlPage = 1 } }.tag(0)
            starter(after: { _ in withAnimation { controlPage = 2 } }).tag(1)
            nudge.tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
    }

    // MARK: Navigation

    private var currentStepName: String {
        if showControl, Self.controlSteps.indices.contains(controlPage) { return Self.controlSteps[controlPage] }
        return step.rawValue
    }

    private func go(to next: Step) {
        focusedGoal = nil
        history.append(step)
        withAnimation { step = next }
    }

    private func back() {
        guard let previous = history.popLast() else { return }
        focusedGoal = nil
        withAnimation { step = previous }
    }

    private func continueFromWelcome() {
        lockVariant()
        if variant == .control {
            controlPage = 1
            showControl = true
            logStep(Self.controlSteps[1])
        } else {
            go(to: .goals)
        }
    }

    private func lockVariant() {
        guard variant == nil else { return }
        if let saved = UserDefaults.standard.string(forKey: Self.variantDefaultsKey) {
            variantLabel = saved
            variant = saved == Variant.test.rawValue ? .test : .control
            return
        }
        let label: String
        if !Analytics.flagsKnown {
            label = "unassigned"
        } else {
            // Once flags are known, a missing flag (experiment over) means the new flow
            label = Analytics.flag(Self.flagKey) == "control" ? Variant.control.rawValue : Variant.test.rawValue
        }
        variantLabel = label
        variant = label == Variant.test.rawValue ? .test : .control
        UserDefaults.standard.set(label, forKey: Self.variantDefaultsKey)
        Analytics.capture("onboarding_started", experimentProperties())
    }

    // Every onboarding event carries the variant, and PostHog's own
    // $feature/<flag> property when the person is really in the experiment
    private func experimentProperties(_ extra: [String: Any] = [:]) -> [String: Any] {
        var properties = extra
        properties["variant"] = variantLabel
        if variantLabel != "unassigned" { properties["$feature/\(Self.flagKey)"] = variantLabel }
        return properties
    }

    private func logStep(_ name: String) {
        guard name != lastLoggedStep else { return }
        lastLoggedStep = name
        Analytics.capture("onboarding_step_viewed", experimentProperties(["step": name]))
    }

    private func skip() {
        guard !didFinish else { return }
        didFinish = true
        lockVariant()
        Analytics.capture("onboarding_skipped", experimentProperties(["step": currentStepName]))
        onFinish()
    }

    private func finish(reminders: Bool) {
        guard !didFinish else { return }
        didFinish = true
        lockVariant()
        var properties: [String: Any] = experimentProperties([
            "path": path,
            "goals_count": committedGoals.count,
            "reminders": reminders,
        ])
        if let templateID { properties["template"] = templateID }
        Analytics.capture("onboarding_completed", properties)
        onFinish()
    }

    // MARK: Pages

    private func welcome(next: @escaping () -> Void) -> some View {
        OnboardingPage(
            symbol: "sparkles",
            title: "See Your Goals Every Day",
            message: "Put the photos and words that pull you forward on a board. VisionBoard shows you one of each, every day."
        ) {
            Button(action: next) {
                Text("Continue").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var canCommitGoals: Bool {
        goals.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var goalsPage: some View {
        OnboardingPage(
            symbol: "target",
            title: "What do you want in 2027?",
            message: "Write up to three goals. A few words each is enough."
        ) {
            VStack(spacing: 12) {
                ForEach(goals.indices, id: \.self) { index in
                    TextField(Self.placeholders[index], text: $goals[index])
                        .font(.title3)
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(index < goals.count - 1 ? .next : .done)
                        .focused($focusedGoal, equals: index)
                        .onSubmit { submitGoal(index) }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel(Text("Goal \(index + 1)"))
                }
                Button(action: commitGoals) {
                    Text("Continue").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canCommitGoals)
                .padding(.top, 8)
                Button("Start from an Example") { go(to: .examples) }
                    .padding(.top, 4)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func submitGoal(_ index: Int) {
        if index < goals.count - 1 {
            focusedGoal = index + 1
        } else {
            focusedGoal = nil
            if canCommitGoals { commitGoals() }
        }
    }

    // Both flows: pick an example board or start blank. `after` gets true
    // when a template was loaded.
    private func starter(after: @escaping (Bool) -> Void) -> some View {
        OnboardingPage(
            symbol: "square.grid.2x2",
            title: "Start Your First Board",
            message: "Begin with an example you can change, or with blank paper."
        ) {
            VStack(spacing: 10) {
                ForEach(BoardTemplate.all) { template in
                    Button {
                        if templateID != template.id, !boardHasOutsideContent, let file = template.load() {
                            store.replaceBoard(with: file)
                            templateID = template.id
                            clearOwnGoals()
                            Analytics.capture("template_loaded", ["template": template.id, "surface": "onboarding"])
                        }
                        path = "template"
                        after(true)
                    } label: {
                        Label(template.name, systemImage: template.symbol)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                Button("Start Blank") {
                    if templateID != nil || !goalIDs.isEmpty || !photoIDs.isEmpty {
                        // Back from a template or goals: clear them so the board really is blank
                        store.replaceBoard(with: BoardFile(version: 1, items: [], maxZIndex: 1))
                        templateID = nil
                        clearOwnGoals()
                    }
                    if !startedBlank {
                        startedBlank = true
                        Analytics.capture("blank_started", ["surface": "onboarding"])
                    }
                    path = "blank"
                    after(false)
                }
                .padding(.top, 4)
            }
        }
    }

    private var photosPage: some View {
        OnboardingPage(
            symbol: "photo.on.rectangle.angled",
            title: "Add a Photo for Each",
            message: "Pick up to three photos that show your goals. You can skip this."
        ) {
            VStack(spacing: 10) {
                if importing {
                    ProgressView("Adding photos")
                } else if !photoIDs.isEmpty {
                    Group {
                        if photoIDs.count == 1 {
                            Text("1 photo added")
                        } else {
                            Text("\(photoIDs.count) photos added")
                        }
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                if let photoError {
                    Text(photoError)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
                if photoIDs.isEmpty {
                    PhotosPicker(selection: $pickedPhotos, maxSelectionCount: 3, matching: .images) {
                        Text("Choose Photos").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(importing)
                    Button("Not Now") { go(to: .screen) }
                        .disabled(importing)
                        .padding(.top, 4)
                } else {
                    Button {
                        go(to: .screen)
                    } label: {
                        Text("Continue").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(importing)
                    PhotosPicker(selection: $pickedPhotos, maxSelectionCount: 3, matching: .images) {
                        Text("Choose Different Photos")
                    }
                    .disabled(importing)
                    .padding(.top, 4)
                }
            }
        }
    }

    private var screenPage: some View {
        OnboardingPage(
            symbol: "iphone",
            title: "Put It on Your Screen",
            message: "Make a wallpaper of your board, so your goals are there every time you pick up your phone."
        ) {
            VStack(spacing: 12) {
                if let wallpaper {
                    Image(uiImage: wallpaper)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
                        .accessibilityLabel("Wallpaper preview")
                } else {
                    ProgressView()
                        .frame(minHeight: 120)
                }

                if wallpaperSaved {
                    lockScreenSteps
                    Button {
                        go(to: .nudge)
                    } label: {
                        Text("Continue").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    if let wallpaperStatus {
                        Text(wallpaperStatus)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    Button {
                        Task { await saveWallpaper() }
                    } label: {
                        Text("Make My Wallpaper").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(wallpaper == nil || savingWallpaper)
                }

                Button {
                    showWidgetGuide = true
                    Analytics.capture("widget_guide_viewed")
                } label: {
                    Label("Add the Widget", systemImage: "square.grid.2x2")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                if !wallpaperSaved {
                    Button("Not Now") { go(to: .nudge) }
                        .padding(.top, 4)
                }
            }
        }
        .task {
            // Drawn each time the page shows, so it matches the board
            wallpaper = await WallpaperRenderer.render(.board, items: store.sortedItems, paper: paper, colorScheme: colorScheme, scale: displayScale)
        }
    }

    private var lockScreenSteps: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Set It as Your Lock Screen")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            GuideStep(number: 1, symbol: "photo", text: "Open Photos and tap your new wallpaper.")
            GuideStep(number: 2, symbol: "square.and.arrow.up", text: "Tap Share, then Use as Wallpaper.")
            GuideStep(number: 3, symbol: "lock", text: "Tap Add, then Set as Wallpaper Pair.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
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

    // MARK: Board

    // Turns the goals into text clippings, replacing ones made earlier in
    // this flow if the person came back and changed them
    private func commitGoals() {
        let entered = goals
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !entered.isEmpty else { return }
        let stillThere = !goalIDs.isEmpty && goalIDs.allSatisfy { store.item($0) != nil }
        if entered != committedGoals || !stillThere {
            if templateID != nil {
                // Back from an example: their own goals replace it
                store.replaceBoard(with: BoardFile(version: 1, items: [], maxZIndex: 1))
                templateID = nil
                photoIDs = []
            }
            for id in goalIDs { store.delete(id) }
            goalIDs = entered.map { text in
                let item = store.addText(at: .zero, content: text)
                store.update(item.id) { $0.applyRandomLook() }
                return item.id
            }
            committedGoals = entered
            wallpaperSaved = false
            wallpaperStatus = nil
            arrange()
            Analytics.capture("goals_entered", ["count": entered.count])
            for _ in goalIDs {
                Analytics.capture("item_added", ["source": "onboarding_goal", "board_item_count": store.items.count])
            }
        }
        path = "goals"
        go(to: .photos)
    }

    // A synced board whose cloud copy landed behind this sheet. Onboarding
    // never replaces content it didn't put there itself.
    private var boardHasOutsideContent: Bool {
        sync.isOn && templateID == nil && goalIDs.isEmpty && photoIDs.isEmpty && !store.items.isEmpty
    }

    private func clearOwnGoals() {
        goalIDs = []
        photoIDs = []
        committedGoals = []
        wallpaperSaved = false
        wallpaperStatus = nil
    }

    private func importPhotos(_ picked: [PhotosPickerItem]) async {
        importing = true
        photoError = nil
        defer { importing = false }
        var added: [String] = []
        for photo in picked.prefix(3) {
            do {
                guard let data = try await photo.loadTransferable(type: Data.self) else { continue }
                let imported = try await ImageStore.shared.importPhoto(data)
                let item = store.addImage(content: imported.content, aspect: imported.aspect, at: .zero)
                added.append(item.id)
            } catch {
                photoError = error.localizedDescription
            }
        }
        guard !added.isEmpty else { return }
        // Picking again swaps the photos instead of piling them up
        for id in photoIDs { store.delete(id) }
        photoIDs = added
        wallpaperSaved = false
        wallpaperStatus = nil
        arrange()
        Analytics.capture("photos_added", ["count": added.count])
        for _ in added {
            Analytics.capture("item_added", ["source": "onboarding_photo", "board_item_count": store.items.count])
        }
    }

    // A tidy two-column collage: each goal beside its photo, sides swapping
    // every row. Without photos the goals stack with a slight stagger.
    private func arrange() {
        let texts = goalIDs.compactMap { store.item($0) }
        let photos = photoIDs.compactMap { store.item($0) }
        let rows = max(texts.count, photos.count)
        let column = 220.0
        let gap = 32.0
        let boxWidth = 220.0
        let boxHeight = 240.0
        var top = 0.0
        for row in 0..<rows {
            let text = row < texts.count ? texts[row] : nil
            let photo = row < photos.count ? photos[row] : nil
            var photoWidth = 0.0
            var photoHeight = 0.0
            if let photo, photo.width > 0, photo.height > 0 {
                let scale = min(boxWidth / photo.width, boxHeight / photo.height)
                photoWidth = (photo.width * scale).rounded()
                photoHeight = (photo.height * scale).rounded()
            }
            let rowHeight = max(text?.height ?? 0, photoHeight)
            let textFirst = row % 2 == 0
            let textX: Double
            let photoX: Double
            if photos.isEmpty {
                textX = row % 2 == 0 ? 0 : 48
                photoX = 0
            } else if photo == nil {
                textX = (column + gap) / 2
                photoX = 0
            } else if text == nil {
                textX = 0
                photoX = (column + gap) / 2
            } else {
                textX = textFirst ? 0 : column + gap
                photoX = textFirst ? column + gap : 0
            }
            if let text {
                store.update(text.id) {
                    $0.x = textX
                    $0.y = top + (rowHeight - $0.height) / 2
                }
            }
            if let photo {
                store.update(photo.id) {
                    $0.width = photoWidth
                    $0.height = photoHeight
                    $0.x = photoX + (column - photoWidth) / 2
                    $0.y = top + (rowHeight - photoHeight) / 2
                    $0.rotation = textFirst ? 1.5 : -1.5
                }
            }
            top += rowHeight + gap
        }
    }

    private func saveWallpaper() async {
        guard let wallpaper else { return }
        savingWallpaper = true
        defer { savingWallpaper = false }
        switch await WallpaperRenderer.saveToPhotos(wallpaper) {
        case .saved:
            wallpaperStatus = nil
            wallpaperSaved = true
            Analytics.capture("wallpaper_made", ["kind": "onboarding"])
        case .denied:
            wallpaperStatus = String(localized: "VisionBoard can't save to Photos. Turn it on in Settings > Apps > VisionBoard > Photos.")
        case .failed(let message):
            wallpaperStatus = String(localized: "Couldn't save: \(message)")
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
                    .accessibilityAddTraits(.isHeader)
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

// One numbered step with a symbol, read by VoiceOver as "Step 1, ..."
private struct GuideStep: View {
    let number: Int
    let symbol: String
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(minWidth: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Step \(number)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(text)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// How to add the Home Screen widget, in three steps drawn with SF Symbols
private struct WidgetGuide: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Today's goal and photo on your Home Screen. It changes every day.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    GuideStep(number: 1, symbol: "hand.tap", text: "Touch and hold an empty spot on your Home Screen.")
                    GuideStep(number: 2, symbol: "plus.circle", text: "Tap Edit, then Add Widget. On some iPhones it's the + button.")
                    GuideStep(number: 3, symbol: "magnifyingglass", text: "Search for VisionBoard, pick Today's Goal, then tap Add Widget.")
                }
                .padding()
                .frame(maxWidth: 520, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Add the Widget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
