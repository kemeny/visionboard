import Foundation
import Observation
import StoreKit

// Whether this person has VisionBoard Pro. Gate every Pro feature through
// this object only.
//
// Purchases go through StoreKit 2 with no server of our own: isPro comes from
// the verified transactions in Transaction.currentEntitlements, and a
// listener on Transaction.updates (started at launch) picks up renewals,
// refunds, Ask to Buy approvals and purchases made on other devices.
@MainActor
@Observable
final class ProAccess {
    static let shared = ProAccess()

    private(set) var isPro: Bool

    // How many boards the free plan keeps
    static let freeBoardLimit = 1

    enum Plan: String, CaseIterable, Identifiable {
        case yearly, monthly

        var id: String { rawValue }

        var productID: String {
            switch self {
            case .yearly: "com.kemenystudio.visionboard.pro.yearly"
            case .monthly: "com.kemenystudio.visionboard.pro.monthly"
            }
        }

        init?(productID: String) {
            guard let plan = Plan.allCases.first(where: { $0.productID == productID }) else { return nil }
            self = plan
        }
    }

    enum LoadState: Equatable {
        case idle, loading, loaded, failed
    }

    // Products from the App Store, keyed by plan. Prices come from here only.
    private(set) var products: [Plan: Product] = [:]
    private(set) var loadState: LoadState = .idle
    // True while a purchase or restore sheet is up
    private(set) var isPurchasing = false
    private(set) var isRestoring = false
    // The plan that is active right now, when there is one
    private(set) var activePlan: Plan?
    // Whether this Apple Account can still get the yearly plan's free trial
    private(set) var isEligibleForTrial = false
    // A purchase waiting for approval (Ask to Buy, a bank check)
    private(set) var hasPendingPurchase = false
    // Plain words for the paywall when something went wrong
    var errorMessage: String?

    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var started = false

    private static let cachedProKey = "pro-active"
    private static let softPaywallShownKey = "pro-soft-paywall-shown"
    private static let opensKey = "pro-opens-since-onboarding"
    private static let onboardingFinishedAtKey = "pro-onboarding-finished-at"
    // Each subscription's originalID, once counted for analytics: "trial"
    // while it is in its free trial, "paid" once a paid period was counted
    private static let countedKey = "pro-counted-original-ids"
    // The soft paywall waits this long after onboarding, so a trip to Photos
    // to set the wallpaper doesn't count as a second open
    private static let softPaywallDelay: TimeInterval = 12 * 3600

    private init() {
        // The last known answer, so Pro features don't flicker off at launch
        // or offline while StoreKit answers
        isPro = UserDefaults.standard.bool(forKey: Self.cachedProKey)
    }

    // MARK: Lifecycle

    // Called once at launch. Listens for transactions for the life of the
    // app and checks what this Apple Account is entitled to.
    func start() {
        guard !started else { return }
        started = true
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(result)
            }
        }
        Task { await refresh() }
    }

    // Reads the current entitlements again. Cheap; called when the app comes
    // to the front so an expired or refunded plan turns off.
    func refresh() async {
        var plan: Plan?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  let found = Plan(productID: transaction.productID),
                  transaction.revocationDate == nil
            else { continue }
            if let expires = transaction.expirationDate, expires < .now { continue }
            // Yearly wins when both show up during a plan change
            if plan != .yearly { plan = found }
        }
        activePlan = plan
        setPro(plan != nil)
        await updateTrialEligibility()
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else { return }
        await transaction.finish()
        hasPendingPurchase = false
        await refresh()
        countFromUpdates(transaction)
    }

    // Purchases that finish outside purchase() (Ask to Buy approval, offer
    // codes, another device) and trials that turn into a paid plan. Each
    // subscription is counted once as a trial and once as paid.
    private func countFromUpdates(_ transaction: Transaction) {
        guard let plan = Plan(productID: transaction.productID), transaction.revocationDate == nil else { return }
        let id = String(transaction.originalID)
        let isTrial = transaction.offer?.type == .introductory
        switch Self.counted(id) {
        case nil:
            if isTrial {
                Self.setCounted(id, "trial")
                Analytics.capture("trial_started", ["plan": plan.rawValue, "source": "updates"])
            } else {
                Self.setCounted(id, "paid")
                Analytics.capture("subscribed", ["plan": plan.rawValue, "source": "updates", "trial_converted": false])
            }
        case .some("trial") where !isTrial:
            Self.setCounted(id, "paid")
            Analytics.capture("subscribed", ["plan": plan.rawValue, "source": "updates", "trial_converted": true])
        default:
            break
        }
    }

    private static func counted(_ originalID: String) -> String? {
        (UserDefaults.standard.dictionary(forKey: countedKey) as? [String: String])?[originalID]
    }

    private static func setCounted(_ originalID: String, _ value: String) {
        var all = (UserDefaults.standard.dictionary(forKey: countedKey) as? [String: String]) ?? [:]
        all[originalID] = value
        UserDefaults.standard.set(all, forKey: countedKey)
    }

    // The signed App Store transaction for the active plan, so the Worker can
    // check Pro itself before it runs a Pro feature (Create with AI)
    func entitlementJWS() async -> String? {
        var yearly: String?
        var other: String?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  let plan = Plan(productID: transaction.productID),
                  transaction.revocationDate == nil
            else { continue }
            if let expires = transaction.expirationDate, expires < .now { continue }
            if plan == .yearly { yearly = result.jwsRepresentation } else { other = result.jwsRepresentation }
        }
        return yearly ?? other
    }

    private func setPro(_ value: Bool) {
        isPro = value
        UserDefaults.standard.set(value, forKey: Self.cachedProKey)
    }

    // MARK: Products

    func loadProducts() async {
        if loadState == .loading { return }
        if loadState == .loaded, products.count == Plan.allCases.count { return }
        loadState = .loading
        do {
            let found = try await Product.products(for: Plan.allCases.map(\.productID))
            var byPlan: [Plan: Product] = [:]
            for product in found {
                if let plan = Plan(productID: product.id) { byPlan[plan] = product }
            }
            products = byPlan
            loadState = byPlan.isEmpty ? .failed : .loaded
            await updateTrialEligibility()
        } catch {
            loadState = .failed
        }
    }

    private func updateTrialEligibility() async {
        guard let yearly = products[.yearly], let subscription = yearly.subscription,
              subscription.introductoryOffer?.paymentMode == .freeTrial
        else {
            isEligibleForTrial = false
            return
        }
        isEligibleForTrial = await subscription.isEligibleForIntroOffer
    }

    // Whether buying this plan right now starts the free trial
    func startsTrial(_ plan: Plan) -> Bool {
        guard isEligibleForTrial, let product = products[plan] else { return false }
        return product.subscription?.introductoryOffer?.paymentMode == .freeTrial
    }

    // The plan's free trial length as the App Store has it set up, written
    // out in the app's language ("7 days", "1 month"). Nil without a trial.
    func trialLength(_ plan: Plan) -> String? {
        guard let offer = products[plan]?.subscription?.introductoryOffer, offer.paymentMode == .freeTrial else { return nil }
        let period = offer.period
        var parts = DateComponents()
        switch period.unit {
        case .day: parts.day = period.value
        case .week: parts.day = period.value * 7
        case .month: parts.month = period.value
        case .year: parts.year = period.value
        @unknown default: return nil
        }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.day, .month, .year]
        return formatter.string(from: parts)
    }

    // MARK: Buying

    // Buys the plan. Returns true when Pro is on afterwards.
    @discardableResult
    func purchase(_ plan: Plan) async -> Bool {
        guard !isPurchasing, let product = products[plan] else { return false }
        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }
        let trial = startsTrial(plan)
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    Analytics.capture("purchase_failed", ["reason": "unverified", "plan": plan.rawValue])
                    errorMessage = String(localized: "The App Store couldn't confirm this purchase. Try again, or tap Restore Purchases.")
                    return false
                }
                await transaction.finish()
                await refresh()
                // A trial start is not a subscription yet: `subscribed`
                // counts paid plans only, and a trial that converts is
                // counted when its first paid renewal arrives
                let originalID = String(transaction.originalID)
                if trial {
                    Self.setCounted(originalID, "trial")
                    Analytics.capture("trial_started", ["plan": plan.rawValue])
                } else {
                    Self.setCounted(originalID, "paid")
                    Analytics.capture("subscribed", [
                        "plan": plan.rawValue,
                        "price_tier": Self.priceTier(product),
                        "source": "purchase",
                        "trial_converted": false,
                    ])
                }
                return isPro
            case .userCancelled:
                Analytics.capture("purchase_failed", ["reason": "cancelled", "plan": plan.rawValue])
                return false
            case .pending:
                hasPendingPurchase = true
                Analytics.capture("purchase_failed", ["reason": "pending", "plan": plan.rawValue])
                return false
            @unknown default:
                Analytics.capture("purchase_failed", ["reason": "unknown", "plan": plan.rawValue])
                return false
            }
        } catch {
            let reason = Self.reason(for: error)
            Analytics.capture("purchase_failed", ["reason": reason, "plan": plan.rawValue])
            if reason != "cancelled" {
                errorMessage = reason == "network"
                    ? String(localized: "Couldn't reach the App Store. Check your connection and try again.")
                    : String(localized: "The purchase didn't go through. You weren't charged. Please try again.")
            }
            return false
        }
    }

    // Asks the App Store for this Apple Account's purchases again. Returns
    // true when Pro is on afterwards.
    @discardableResult
    func restore() async -> Bool {
        guard !isRestoring else { return isPro }
        isRestoring = true
        errorMessage = nil
        defer { isRestoring = false }
        Analytics.capture("restore_tapped")
        do {
            try await AppStore.sync()
        } catch {
            if Self.reason(for: error) != "cancelled" {
                errorMessage = String(localized: "Couldn't reach the App Store. Check your connection and try again.")
            }
            return isPro
        }
        await refresh()
        if isPro {
            Analytics.capture("restore_succeeded", ["plan": activePlan?.rawValue ?? "unknown"])
        } else {
            errorMessage = String(localized: "No active VisionBoard Pro plan was found for this Apple Account.")
        }
        return isPro
    }

    private static func reason(for error: Error) -> String {
        if let storeError = error as? StoreKitError {
            switch storeError {
            case .userCancelled: return "cancelled"
            case .networkError: return "network"
            case .notAvailableInStorefront: return "not_available"
            case .notEntitled: return "not_entitled"
            default: return "store_error"
            }
        }
        if error is Product.PurchaseError { return "purchase_error" }
        if error is URLError { return "network" }
        return "unknown"
    }

    // The price as a plain number with its currency, like "19.99 USD". A
    // price tier, not board content.
    private static func priceTier(_ product: Product) -> String {
        "\(product.price) \(product.priceFormatStyle.currencyCode)"
    }

    // MARK: Gating

    // True when Pro is on. Otherwise shows the paywall and returns false.
    // `source` names the place that asked, for analytics (for example
    // "ai_board" or "board_limit").
    @discardableResult
    func requirePro(from source: String) -> Bool {
        if isPro { return true }
        AppRouter.shared.paywallSource = source
        return false
    }

    // The free plan keeps one board. People who already have more keep them
    // all; only making another one asks for Pro.
    func canCreateBoard(currentCount: Int) -> Bool {
        isPro || currentCount < Self.freeBoardLimit
    }

    // MARK: Soft paywall

    // Counts app opens once onboarding is done. The onboarding run counts as
    // the first, so the paywall can show once from the second open on, at
    // least 12 hours after onboarding, when the board has at least 3 things.
    func noteOnboardingFinished() {
        UserDefaults.standard.set(1, forKey: Self.opensKey)
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: Self.onboardingFinishedAtKey)
    }

    // Called each time the app comes to the front after onboarding. Returns
    // true when the one-time paywall should show now.
    func noteAppOpen(itemCount: Int) -> Bool {
        let defaults = UserDefaults.standard
        let opens = defaults.integer(forKey: Self.opensKey) + 1
        defaults.set(opens, forKey: Self.opensKey)
        guard !isPro, opens >= 2, itemCount >= 3, !defaults.bool(forKey: Self.softPaywallShownKey) else { return false }
        // Not in the same sitting as onboarding: its own steps send people to
        // Photos and back. Installs from before this was saved have no date.
        let finishedAt = defaults.double(forKey: Self.onboardingFinishedAtKey)
        if finishedAt > 0, Date.now.timeIntervalSince1970 - finishedAt < Self.softPaywallDelay { return false }
        return true
    }

    func markSoftPaywallShown() {
        UserDefaults.standard.set(true, forKey: Self.softPaywallShownKey)
    }
}
