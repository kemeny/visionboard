import SwiftUI

// Today's goal and photo, plus the week ahead. On iPhone Duo's inner display
// the card and the week sit side by side; on the outer display they stack.
struct TodayView: View {
    @Environment(BoardStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(Reminders.self) private var reminders
    @State private var yearShown: Int?

    var body: some View {
        NavigationStack {
            // Redraws each minute, so the card turns over when the day does
            // even if the app stays open
            TimelineView(.everyMinute) { context in
                AdaptiveArrangement {
                    TodayCardView(card: DailyCard.pick(from: store.items, on: context.date))
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .padding()
                        .onTapGesture { router.todayCard = DailyCard.pick(from: store.items) }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint("Opens full screen")
                } secondary: {
                    VStack(alignment: .leading, spacing: 0) {
                        if let year = YearRecap.year(on: context.date) {
                            yearCard(year)
                        }
                        upcoming(from: context.date)
                    }
                }
            }
            .navigationTitle("Today")
            .fullScreenCover(isPresented: Binding(get: { yearShown != nil }, set: { if !$0 { yearShown = nil } })) {
                YearRecapView(year: yearShown ?? Calendar.current.component(.year, from: .now))
            }
            // today_viewed for the tab fires in RootView on tab selection:
            // onAppear also runs again when a full-screen cover closes
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Your Week", systemImage: "calendar") { router.weeklyRecapSource = "today" }
                }
                if !reminders.isEnabled {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Daily Reminder", systemImage: "bell.badge") { router.tab = .settings }
                    }
                }
            }
        }
    }

    private func yearCard(_ year: Int) -> some View {
        Button {
            yearShown = year
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(
                        LinearGradient(colors: [Color(red: 0.36, green: 0.18, blue: 0.32), Color(red: 0.86, green: 0.48, blue: 0.32)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your \(String(year)) on VisionBoard")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("See your goals, photos and days")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .padding(.top)
        .padding(.bottom, 4)
    }

    private func upcoming(from now: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Coming Up")
                .font(.headline)
                .padding(.horizontal)
                .padding(.bottom, 8)
            ForEach(1..<7, id: \.self) { offset in
                let date = Calendar.current.date(byAdding: .day, value: offset, to: now) ?? now
                let card = DailyCard.pick(from: store.items, on: date)
                HStack(spacing: 12) {
                    if let image = card.image {
                        BoardImage(content: image)
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.quaternary)
                            .frame(width: 52, height: 52)
                            .overlay { Image(systemName: "sparkles").foregroundStyle(.secondary) }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(date, format: .dateTime.weekday(.wide))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(card.text)
                            .font(.body)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.vertical)
    }
}

// The photo with the goal over it. Used in the Today tab and full screen when
// a reminder is tapped.
struct TodayCardView: View {
    let card: DailyCard

    var body: some View {
        ZStack {
            Color(red: 0.10, green: 0.09, blue: 0.08)
            if let image = card.image {
                // Fill the card without letting the photo's size stretch the layout
                Color.clear
                    .overlay { BoardImage(content: image) }
                    .clipped()
            }
            LinearGradient(colors: [.black.opacity(0.8), .black.opacity(0.2), .clear], startPoint: .bottom, endPoint: .center)
            FoldAware {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Today")
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.7))
                    Text(card.text)
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.5)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Today: \(card.text)")
    }
}

struct TodayFullScreen: View {
    let card: DailyCard
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TodayCardView(card: card)
            .ignoresSafeArea()
            .overlay(alignment: .topTrailing) {
                Button("Close", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(.ultraThinMaterial, in: Circle())
                    .padding()
            }
            .onTapGesture { dismiss() }
            .statusBarHidden()
            .onAppear { Analytics.capture("today_viewed", ["surface": "full_screen"]) }
    }
}
