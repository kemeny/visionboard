import Foundation
import Observation

// Whether this person has VisionBoard Pro. Gate every Pro feature through
// this object only.
//
// This is a stub: everyone is on the free plan. The Pro workstream fills in
// purchases (StoreKit), restoring and the paywall here, without changing the
// call sites.
@MainActor
@Observable
final class ProAccess {
    static let shared = ProAccess()

    private(set) var isPro: Bool = false

    // How many boards the free plan keeps
    static let freeBoardLimit = 1
}
