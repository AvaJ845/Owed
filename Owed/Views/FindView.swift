import SwiftUI

enum FeedFilter: String, CaseIterable, Identifiable {
    case all, soon, noReceipt, high
    var id: Self { self }

    var label: String {
        switch self {
        case .all: "All"
        case .soon: "Closing soon"
        case .noReceipt: "No receipt"
        case .high: "$500+"
        }
    }

    func apply(_ feed: [Settlement]) -> [Settlement] {
        let filtered: [Settlement] = switch self {
        case .all: feed
        case .soon: feed.filter { $0.daysLeft <= 30 }
        case .noReceipt: feed.filter { !$0.receiptRequired }
        case .high: feed.filter { $0.payoutHi >= 500 }
        }
        return filtered.sorted { $0.daysLeft < $1.daysLeft }
    }
}

struct FindView: View {
    @Environment(AppModel.self) private var model
    @Environment(StoreManager.self) private var store

    @State private var filter: FeedFilter = .all
    @State private var selected: Settlement?
    @State private var showPaywall = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero
                    filterChips
                    LazyVStack(spacing: 12) {
                        ForEach(filter.apply(model.settlements)) { s in
                            Button { selected = s } label: {
                                DocketCard(settlement: s, isTracked: model.isTracked(s))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .animation(.snappy(duration: 0.25), value: filter)
                }
                .padding(.bottom, 24)
            }
        }
        .background(T.paper)
        .sheet(item: $selected) { s in
            SettlementDetailView(settlement: s)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
    }

    private var topBar: some View {
        HStack {
            (Text("Owed") + Text(".").foregroundStyle(T.green))
                .font(OwedFont.displayBold(24))
                .foregroundStyle(T.ink)

            Spacer()

            Button {
                if !model.lifetime { showPaywall = true }
            } label: {
                Text(model.lifetime ? "LIFETIME ✓" : "LIFETIME \(store.displayPrice)")
                    .font(OwedFont.body(10.5, weight: .bold))
                    .kerning(0.6)
                    .foregroundStyle(model.lifetime ? T.green : T.gold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(model.lifetime ? T.greenSoft : T.goldSoft, in: .capsule)
                    .overlay(Capsule().strokeBorder(model.lifetime ? T.green : T.gold, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 6) {
            (Text("Find out what ") + Text("you're owed.").foregroundStyle(T.green))
                .font(OwedFont.display(29))
                .foregroundStyle(T.ink)
                .lineSpacing(2)

            Text("Active class-action settlements, verified against court dockets. Free to browse — always.")
                .font(OwedFont.body(13))
                .foregroundStyle(T.mut)

            if !model.trackedSettlements.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(model.potentialTotal.usd)
                        .font(OwedFont.displayBold(25))
                        .foregroundStyle(T.green)
                        .contentTransition(.numericText())
                    Text("POTENTIAL ACROSS \(model.trackedSettlements.count) TRACKED")
                        .font(OwedFont.body(10, weight: .semibold))
                        .kerning(0.8)
                        .foregroundStyle(T.mut)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .docketSurface(cornerRadius: 14)
                .padding(.top, 8)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FeedFilter.allCases) { f in
                    Button { filter = f } label: {
                        Text(f.label)
                            .font(OwedFont.body(12.5, weight: .semibold))
                            .foregroundStyle(filter == f ? T.paper : T.ink)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 7)
                            .background(filter == f ? T.ink : T.card, in: .capsule)
                            .overlay(Capsule().strokeBorder(filter == f ? T.ink : T.line, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 12)
    }
}

#Preview {
    FindView()
        .environment(AppModel())
        .environment(StoreManager())
}
