import CoreSpotlight
import Foundation

/// Puts every open settlement into Spotlight so searching "class action"
/// or a company name on the home screen surfaces Owed's content — free
/// re-engagement no web-wrapper competitor gets.
enum SpotlightIndexer {
    static func index(_ settlements: [Settlement]) {
        let items = settlements.filter { !$0.closed }.map { s in
            let attrs = CSSearchableItemAttributeSet(contentType: .text)
            attrs.title = s.name
            attrs.contentDescription =
                "\(s.payoutRange) \(s.payoutTerms) — \(s.category). Claims close in \(s.daysLeft) days."
            attrs.keywords = ["class action", "settlement", "refund", "claim", s.name]
            return CSSearchableItem(
                uniqueIdentifier: "owed.settlement.\(s.id)",
                domainIdentifier: "owed.settlements",
                attributeSet: attrs
            )
        }
        // Wipe the domain first so settlements that closed since the
        // last launch drop out instead of lingering with stale copy.
        let index = CSSearchableIndex.default()
        index.deleteSearchableItems(withDomainIdentifiers: ["owed.settlements"]) { _ in
            index.indexSearchableItems(items)
        }
    }
}
