import StoreKit
import SwiftUI

// VisionBoard Pro. Shown as a sheet from RootView whenever
// AppRouter.paywallSource is set. Prices always come from the App Store.
struct PaywallView: View {
    let source: String

    @Environment(ProAccess.self) private var pro
    @Environment(\.dismiss) private var dismiss
    @State private var plan: ProAccess.Plan = .yearly
    @State private var didAppear = false

    private static let termsURL = URL(string: "https://visionboard.kemenystudio.com/terms")
    private static let privacyURL = URL(string: "https://visionboard.kemenystudio.com/privacy")

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    benefits
                    plans
                    purchaseArea
                    footerLinks
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            guard !didAppear else { return }
            didAppear = true
            pro.errorMessage = nil
            Analytics.capture("paywall_viewed", ["source": source])
        }
        .task { await pro.loadProducts() }
        .onChange(of: pro.isPro) { _, isPro in
            if isPro { dismiss() }
        }
    }

    // MARK: Parts

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Make Your Vision Real")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text("VisionBoard Pro")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 14) {
            BenefitRow(symbol: "square.stack.3d.up", text: "Unlimited boards")
            BenefitRow(symbol: "wand.and.stars", text: "Create a board with AI from a few words")
            BenefitRow(symbol: "photo.on.rectangle", text: "Share and wallpapers without the VisionBoard mark")
            BenefitRow(symbol: "heart", text: "Support an indie studio")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var plans: some View {
        switch pro.loadState {
        case .loaded:
            VStack(spacing: 12) {
                ForEach(ProAccess.Plan.allCases) { option in
                    if let product = pro.products[option] {
                        PlanRow(
                            plan: option,
                            product: product,
                            showsTrialBadge: pro.startsTrial(option),
                            trialLength: pro.trialLength(option),
                            isSelected: plan == option
                        ) {
                            guard plan != option else { return }
                            plan = option
                            Analytics.capture("plan_selected", ["plan": option.rawValue])
                        }
                    }
                }
            }
        case .failed:
            VStack(spacing: 10) {
                Text("Couldn't load the plans. Check your connection and try again.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Try Again") { Task { await pro.loadProducts() } }
            }
            .frame(maxWidth: .infinity, minHeight: 120)
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 120)
        }
    }

    private var selectedProduct: Product? { pro.products[plan] }

    private var purchaseArea: some View {
        VStack(spacing: 12) {
            Button {
                Task { await pro.purchase(plan) }
            } label: {
                Group {
                    if pro.isPurchasing {
                        ProgressView()
                    } else {
                        if pro.startsTrial(plan) {
                            Text("Start Free Trial")
                        } else {
                            Text("Subscribe")
                        }
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(selectedProduct == nil || pro.isPurchasing || pro.isRestoring)

            if let product = selectedProduct {
                Text(disclosure(for: product))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if pro.hasPendingPurchase {
                Label("Your purchase is waiting for approval. Pro turns on as soon as it goes through.", systemImage: "clock")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let error = pro.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await pro.restore() }
            } label: {
                if pro.isRestoring {
                    ProgressView()
                } else {
                    Text("Restore Purchases")
                }
            }
            .disabled(pro.isPurchasing || pro.isRestoring)
        }
    }

    private var footerLinks: some View {
        HStack(spacing: 20) {
            if let terms = Self.termsURL {
                Link("Terms of Use", destination: terms)
            }
            if let privacy = Self.privacyURL {
                Link("Privacy Policy", destination: privacy)
            }
        }
        .font(.footnote)
    }

    // What Apple asks to show next to the button: the price, how often it
    // bills, that it renews on its own and how to cancel
    private func disclosure(for product: Product) -> String {
        let price = product.displayPrice
        let terms: String
        switch plan {
        case .yearly:
            // The trial length comes from the App Store's offer, never a fixed number
            if pro.startsTrial(.yearly) {
                if let length = pro.trialLength(.yearly) {
                    terms = String(localized: "Free for \(length), then \(price) per year.")
                } else {
                    terms = String(localized: "Free trial, then \(price) per year.")
                }
            } else {
                terms = String(localized: "\(price) per year.")
            }
        case .monthly:
            terms = String(localized: "\(price) per month.")
        }
        return terms + " " + String(localized: "Renews automatically until you cancel. Cancel anytime in Settings at least 24 hours before it renews.")
    }
}

private struct BenefitRow: View {
    let symbol: String
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(.tint)
                .frame(width: 26)
                .accessibilityHidden(true)
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct PlanRow: View {
    let plan: ProAccess.Plan
    let product: Product
    let showsTrialBadge: Bool
    // From the App Store's introductory offer, like "7 days"
    let trialLength: String?
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Group {
                            if plan == .yearly {
                                Text("Yearly")
                            } else {
                                Text("Monthly")
                            }
                        }
                        .font(.headline)
                        if showsTrialBadge {
                            Group {
                                if let trialLength {
                                    Text("\(trialLength) free")
                                } else {
                                    Text("Free trial")
                                }
                            }
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                            .foregroundStyle(Color.accentColor)
                        }
                    }
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var subtitle: String {
        let price = product.displayPrice
        switch plan {
        case .yearly:
            let monthly = (product.price / 12).formatted(product.priceFormatStyle)
            return String(localized: "\(price) per year (\(monthly) per month)")
        case .monthly:
            return String(localized: "\(price) per month")
        }
    }
}

#Preview {
    PaywallView(source: "preview")
        .environment(ProAccess.shared)
}
