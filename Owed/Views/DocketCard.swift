import SwiftUI

/// One settlement, rendered as a court-docket card.
struct DocketCard: View {
    let settlement: Settlement
    let isTracked: Bool
    var isMatch: Bool = false
    var status: AppModel.ClaimStatus? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(settlement.caseNo)
                        .font(OwedFont.mono(10.5))
                        .foregroundStyle(T.mut)
                    Text(settlement.name)
                        .font(OwedFont.body(15, weight: .bold))
                        .foregroundStyle(T.ink)
                    Text(settlement.category)
                        .font(OwedFont.body(12))
                        .foregroundStyle(T.mut)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(settlement.payoutRange)
                        .font(OwedFont.displayBold(21))
                        .foregroundStyle(T.green)
                    Text(settlement.payoutTerms)
                        .font(OwedFont.body(10.5))
                        .foregroundStyle(T.mut)
                        .multilineTextAlignment(.trailing)
                }
            }

            HStack(spacing: 6) {
                if let status {
                    Tag(text: statusText(status), fg: statusColors(status).fg, bg: statusColors(status).bg)
                } else {
                    if isMatch {
                        Tag(text: "LIKELY MATCH", fg: T.gold, bg: T.goldSoft)
                    }
                    Tag(
                        text: settlement.receiptRequired ? "DOCUMENTATION REQUIRED" : "NO RECEIPT NEEDED",
                        fg: settlement.receiptRequired ? T.tagProofFg : T.green,
                        bg: settlement.receiptRequired ? T.tagProofBg : T.greenSoft
                    )
                }

                Spacer()

                DeadlineStamp(daysLeft: settlement.daysLeft, soon: settlement.closingSoon, closed: settlement.closed)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .docketSurface()
        .overlay(alignment: .topTrailing) {
            if isTracked {
                Text("✓ TRACKING")
                    .font(OwedFont.body(10, weight: .bold))
                    .kerning(0.6)
                    .foregroundStyle(T.gold)
                    .padding(12)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private func statusText(_ s: AppModel.ClaimStatus) -> String {
        switch s {
        case .actionNeeded: "ACTION NEEDED"
        case .pending: "FILED · PENDING"
        case .awaitingPayout: "AWAITING PAYOUT"
        case .paid(let amount): "PAID · \(amount.usd)"
        }
    }

    private func statusColors(_ s: AppModel.ClaimStatus) -> (fg: Color, bg: Color) {
        switch s {
        case .actionNeeded: (T.stamp, T.stampSoft)
        case .pending: (T.green, T.greenSoft)
        case .awaitingPayout: (T.gold, T.goldSoft)
        case .paid: (T.green, T.greenSoft)
        }
    }

    private var accessibilitySummary: String {
        var parts = [settlement.name, settlement.payoutRange, settlement.payoutTerms]
        parts.append(settlement.receiptRequired ? "documentation required" : "no receipt needed")
        parts.append(settlement.closed ? "filing window closed" : "closes in \(settlement.daysLeft) days")
        if isMatch { parts.append("likely match for you") }
        if let status { parts.append(statusText(status).lowercased()) }
        if isTracked { parts.append("tracking") }
        return parts.joined(separator: ", ")
    }
}

/// Small uppercase pill tag used in the card meta row.
private struct Tag: View {
    let text: String
    let fg: Color
    let bg: Color

    var body: some View {
        Text(text)
            .font(OwedFont.body(10, weight: .bold))
            .kerning(0.5)
            .foregroundStyle(fg)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(bg, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// The rotated docket stamp — red once a deadline is inside 21 days,
/// and a neutral terminal "CLOSED" once the filing window has passed
/// (daysLeft floors at 0, so without this a closed claim reads "DUE 0d",
/// i.e. maximally urgent — exactly backwards).
struct DeadlineStamp: View {
    let daysLeft: Int
    let soon: Bool
    var closed: Bool = false

    private var urgent: Bool { soon && !closed }

    var body: some View {
        Text(closed ? "CLOSED" : "DUE \(daysLeft)d")
            .font(OwedFont.mono(11))
            .foregroundStyle(urgent ? T.stamp : T.mut)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                urgent ? T.stampSoft : .clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(urgent ? T.stamp : T.line, lineWidth: 1.5)
            )
            .rotationEffect(.degrees(-1.2))
    }
}

#Preview {
    let feed = SettlementFeed.bundled()?.settlements ?? []
    VStack {
        ForEach(feed.prefix(2)) { s in
            DocketCard(settlement: s, isTracked: s.id == feed.first?.id)
        }
    }
    .padding()
    .background(T.paper)
}
