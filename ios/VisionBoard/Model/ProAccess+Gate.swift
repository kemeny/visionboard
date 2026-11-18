import Foundation

// TEMP: a stand-in until the Pro workstream lands its own
// `ProAccess.requirePro(from:)` (which also shows the paywall). When merging,
// delete this file if ProAccess.swift already defines the method.
extension ProAccess {
    @discardableResult
    func requirePro(from source: String) -> Bool {
        isPro
    }
}
