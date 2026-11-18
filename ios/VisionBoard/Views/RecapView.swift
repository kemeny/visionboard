import SwiftUI

// The weekly recap: which days this week the board was opened, goals marked
// done, and one step to add for next week. Opens from the Sunday
// notification or from the Today tab.
struct RecapView: View {
    let source: String

    @Environment(BoardStore.self) private var store
    @Environment(BoardLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var step = ""
    @State private var addedSteps = 0
    @FocusState private var stepFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    weekDots
                        .padding(.vertical, 8)
                } header: {
                    Text("This Week")
                } footer: {
                    Text(daysText)
                }

                Section("Goals Done") {
                    LabeledContent("This week") {
                        Text(achievedThisWeek, format: .number)
                            .font(.title3.weight(.semibold).monospacedDigit())
                    }
                    LabeledContent("This month") {
                        Text(achievedThisMonth, format: .number)
                            .font(.title3.weight(.semibold).monospacedDigit())
                    }
                }

                Section {
                    TextField("For example: Walk 20 minutes on Monday", text: $step, axis: .vertical)
                        .lineLimit(1...4)
                        .focused($stepFocused)
                        .submitLabel(.done)
                        .onSubmit(addStep)
                    Button("Add to Board", systemImage: "plus.circle.fill", action: addStep)
                        .disabled(step.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if addedSteps > 0 {
                        Label("Added to your board.", systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                            .font(.callout)
                    }
                } header: {
                    Text("What's one step for next week?")
                } footer: {
                    Text("It goes on your board as a new goal.")
                }
            }
            .navigationTitle("Your Week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sensoryFeedback(.success, trigger: addedSteps)
            .onAppear {
                Analytics.capture("recap_viewed", [
                    "kind": "weekly",
                    "source": source,
                    "days_opened": daysOpenedThisWeek,
                    "goals_achieved": achievedThisWeek,
                ])
            }
        }
        .presentationDetents([.large])
    }

    // MARK: Week

    private var week: [Date] { ProgressLog.weekDays() }

    private var daysOpenedThisWeek: Int {
        week.filter { ProgressLog.wasOpened(on: $0) }.count
    }

    private var daysText: String {
        let days = daysOpenedThisWeek
        if days == 1 { return String(localized: "You looked at your board 1 day this week.") }
        return String(localized: "You looked at your board \(days) days this week.")
    }

    private var weekDots: some View {
        let today = Calendar.current.startOfDay(for: .now)
        return HStack(spacing: 0) {
            ForEach(week, id: \.self) { day in
                let opened = ProgressLog.wasOpened(on: day)
                let isToday = Calendar.current.isDate(day, inSameDayAs: today)
                let isFuture = day > today
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(opened ? Color.green : Color.secondary.opacity(isFuture ? 0.08 : 0.18))
                        if opened {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 30, height: 30)
                    .overlay {
                        if isToday {
                            Circle().stroke(Color.accentColor, lineWidth: 2).padding(-3)
                        }
                    }
                    Text(day, format: .dateTime.weekday(.narrow))
                        .font(.caption2.weight(isToday ? .bold : .regular))
                        .foregroundStyle(isToday ? Color.primary : Color.secondary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(day, format: .dateTime.weekday(.wide)))
                .accessibilityValue(opened ? String(localized: "Opened") : String(localized: "Not opened"))
            }
        }
    }

    // MARK: Goals

    private var allItems: [BoardItem] { ProgressStats.allItems(store: store, library: library) }
    private var achievedThisWeek: Int { ProgressStats.achievedInWeek(allItems, containing: .now) }
    private var achievedThisMonth: Int { ProgressStats.achievedInMonth(allItems, containing: .now) }

    // MARK: Next step

    private func addStep() {
        let text = step.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        store.addText(at: Self.spot(below: store.items), content: text)
        Analytics.capture("item_added", ["source": "recap", "board_item_count": store.items.count])
        step = ""
        stepFocused = false
        addedSteps += 1
    }

    // Just under everything already on the board, so nothing gets covered
    private static func spot(below items: [BoardItem]) -> CGPoint {
        guard !items.isEmpty else { return CGPoint(x: 200, y: 200) }
        let minX = items.map(\.x).min() ?? 0
        let maxX = items.map { $0.x + $0.width }.max() ?? 0
        let maxY = items.map { $0.y + $0.height }.max() ?? 0
        return CGPoint(x: (minX + maxX) / 2, y: maxY + 80)
    }
}
