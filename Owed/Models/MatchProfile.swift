import Foundation

/// One yes/no life-fact the on-device matcher keys on. Raw values are
/// stable identifiers — the production feed gains a `match_keys[]` field
/// with the same vocabulary (PIPELINE.md §3).
///
/// Privacy contract: answers live in UserDefaults on this device and are
/// matched locally. Nothing is ever uploaded — that's the headline
/// feature, not an implementation detail.
enum MatchKey: String, Codable, CaseIterable, Identifiable {
    case streaming
    case groceries
    case smartphone
    case spamTexts
    case breachNotice

    var id: String { rawValue }

    /// Quiz wording — one tap, no typing, plain language.
    var question: String {
        switch self {
        case .streaming: "Used a video-streaming service in the last five years?"
        case .groceries: "Buy groceries at big chain stores?"
        case .smartphone: "Bought a smartphone new in the last ten years?"
        case .spamTexts: "Gotten marketing texts after replying STOP?"
        case .breachNotice: "Ever received a data-breach notice?"
        }
    }

    var icon: String {
        switch self {
        case .streaming: "play.tv"
        case .groceries: "cart"
        case .smartphone: "iphone"
        case .spamTexts: "message.badge"
        case .breachNotice: "lock.trianglebadge.exclamationmark"
        }
    }
}
