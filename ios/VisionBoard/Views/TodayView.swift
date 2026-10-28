import SwiftUI

// Today's goal and photo, plus the week ahead. On iPhone Duo's inner display
// the card and the week sit side by side; on the outer display they stack.
struct TodayView: View {
    @Environment(BoardStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(Reminders.self) private var reminders

    var body: some View {
        NavigationStack {
            AdaptiveArrangement {
                TodayCardView(card: DailyCard.pick(from: store.items))
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .padding()
                    .onTapGesture { router.todayCard = DailyCard.pick(from: store.items) }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Opens full screen")
            } secondary: {
                upcoming
            }
            .navigationTitle("Today")
            .toolbar {
                if !reminders.isEnabled {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Daily Reminder", systemImage: "bell.badge") { router.tab = .settings }
                    }
                }
            }
        }
    }

    private var upcoming: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Coming Up")
                .font(.headline)
                .padding(.horizontal)
                .padding(.bottom, 8)
            ForEach(1..<7, id: \.self) { offset in
                let date = Calendar.current.date(byAdding: .day, value: offset, to: .now) ?? .now
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
    }
}
