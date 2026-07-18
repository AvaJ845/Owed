import Foundation
import LocalAuthentication
import Observation

/// Face ID / Touch ID / device passcode gate for the claims ledger.
///
/// The match quiz and logged payouts are the most sensitive on-device
/// state. Biometric unlock is session-scoped: lock again when the app
/// backgrounds so a borrowed phone can't browse someone else's claims.
@Observable @MainActor
final class ClaimsPrivacyGate {
    private(set) var unlocked = false
    private(set) var biometryAvailable = false
    private(set) var biometryLabel = "Face ID"

    init() {
        refreshAvailability()
    }

    func refreshAvailability() {
        let context = LAContext()
        var error: NSError?
        biometryAvailable = context.canEvaluatePolicy(
            .deviceOwnerAuthentication, error: &error
        )
        switch context.biometryType {
        case .faceID: biometryLabel = "Face ID"
        case .touchID: biometryLabel = "Touch ID"
        case .opticID: biometryLabel = "Optic ID"
        default: biometryLabel = "Passcode"
        }
        // Simulator / devices without enrollment: don't brick Claims.
        if !biometryAvailable { unlocked = true }
    }

    func lock() {
        refreshAvailability()
        if biometryAvailable { unlocked = false }
    }

    @discardableResult
    func unlock() async -> Bool {
        refreshAvailability()
        guard biometryAvailable else {
            unlocked = true
            return true
        }
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        do {
            let ok = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock your claims ledger and recovered totals."
            )
            unlocked = ok
            return ok
        } catch {
            unlocked = false
            return false
        }
    }
}
