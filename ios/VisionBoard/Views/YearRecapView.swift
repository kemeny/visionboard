import SwiftUI
import UIKit

// "Your Year on VisionBoard", shown from December 15 to January 15. The card
// is drawn the same way on screen and in the shared picture.
struct YearRecapStats: Equatable {
    var year: Int
    var goalsAchieved: Int
    var photosAdded: Int
    var daysOpened: Int

    @MainActor
    static func make(year: Int, store: BoardStore, library: BoardLibrary) -> YearRecapStats {
        let items = ProgressStats.allItems(store: store, library: library)
        return YearRecapStats(
            year: year,
            goalsAchieved: ProgressStats.achievedInYear(items, year),
            photosAdded: ProgressStats.photosAdded(items, inYear: year),
            daysOpened: ProgressLog.daysOpened(inYear: year)
        )
    }
}

struct YearRecapCard: View {
    let stats: YearRecapStats

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.12, green: 0.10, blue: 0.20), Color(red: 0.36, green: 0.18, blue: 0.32), Color(red: 0.86, green: 0.48, blue: 0.32)],
                startPoint: .top,
                endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("VisionBoard")
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.7))
                    Text("Your \(String(stats.year)) on VisionBoard")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.6)
                }
                Spacer(minLength: 0)
                stat(stats.goalsAchieved, String(localized: "goals achieved"), symbol: "checkmark.seal.fill")
                stat(stats.photosAdded, String(localized: "photos added"), symbol: "photo.fill")
                stat(stats.daysOpened, String(localized: "days you looked at your board"), symbol: "sun.max.fill")
                Spacer(minLength: 0)
                Text("Here's to the next one.")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .environment(\.colorScheme, .dark)
    }

    private func stat(_ value: Int, _ label: String, symbol: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(value, format: .number)
                    .font(.system(size: 52, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                Text(label)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct YearRecapView: View {
    let year: Int

    @Environment(BoardStore.self) private var store
    @Environment(BoardLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var stats: YearRecapStats?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let stats {
                YearRecapCard(stats: stats)
                    .clipShape(RoundedRectangle(cornerRadius: 28))
                    .padding(.horizontal, 16)
                    .padding(.top, 60)
                    .padding(.bottom, 100)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button("Close", systemImage: "xmark") { dismiss() }
                .labelStyle(.iconOnly)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(minWidth: 44, minHeight: 44)
                .background(.ultraThinMaterial, in: Circle())
                .padding()
        }
        .overlay(alignment: .bottom) {
            Button {
                share()
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.black)
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
            .disabled(stats == nil)
        }
        .statusBarHidden()
        .onAppear {
            let made = YearRecapStats.make(year: year, store: store, library: library)
            stats = made
            Analytics.capture("recap_viewed", [
                "kind": "year",
                "goals_achieved": made.goalsAchieved,
                "photos_added": made.photosAdded,
                "days_opened": made.daysOpened,
            ])
        }
    }

    // A story-sized picture of the card (1080 x 1920)
    private func share() {
        guard let stats else { return }
        let card = YearRecapCard(stats: stats)
            .frame(width: 360, height: 640)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        renderer.isOpaque = true
        guard let image = renderer.uiImage else { return }
        ClippingShare.presentSheet([image]) {
            Analytics.capture("recap_shared", ["kind": "year"])
        }
    }
}
