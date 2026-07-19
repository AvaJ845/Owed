import SwiftUI

enum FeedFilter: String, CaseIterable, Identifiable {
    case forYou, all, soon, noReceipt, high
    var id: Self { self }

    var label: String {
        switch self {
        case .forYou: "For you"
        case .all: "All"
        case .soon: "Closing soon"
        case .noReceipt: "No receipt"
        case .high: "$500+"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .forYou: "For you — settlements matching your quiz"
        case .all: "All settlements"
        case .soon: "Closing soon"
        case .noReceipt: "No receipt needed"
        case .high: "Payout five hundred dollars or more"
        }
    }

    func apply(_ feed: [Settlement], isMatch: (Settlement) -> Bool) -> [Settlement] {
        let filtered: [Settlement] = switch self {
        case .forYou: feed.filter(isMatch)
        case .all: feed
        case .soon: feed.filter { $0.daysLeft <= 30 }
        case .noReceipt: feed.filter { !$0.receiptRequired }
        case .high: feed.filter { $0.payoutHi >= 500 }
        }
        return filtered.sorted { $0.deadline < $1.deadline }
    }
}

struct FindView: View {
    @Environment(AppModel.self) private var model
    @Environment(StoreManager.self) private var store
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var filter: FeedFilter = .all
    @State private var selected: Settlement?
    @State private var showPaywall = false
    @State private var showQuiz = false
    @Namespace private var filterNamespace

    private var visibleFilters: [FeedFilter] {
        model.profile.isEmpty
            ? FeedFilter.allCases.filter { $0 != .forYou }
            : FeedFilter.allCases
    }

    private var feed: [Settlement] {
        // Browse only open settlements — closed ones aren't actionable
        // here and live on in My Claims if tracked (AppModel).
        filter.apply(model.browsableSettlements, isMatch: model.isMatch)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero
                    filterChips
                    LazyVStack(spacing: 12) {
                        if filter == .forYou && feed.isEmpty {
                            forYouEmptyState
                        }
                        ForEach(feed) { s in
                            Button { selected = s } label: {
                                DocketCard(
                                    settlement: s,
                                    isTracked: model.isTracked(s),
                                    isMatch: model.isMatch(s)
                                )
                            }
                            .buttonStyle(.plain)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .trailing)),
                                removal: .opacity
                            ))
                        }
                    }
                    .padding(.horizontal, 16)
                    .animation(OwedMotion.listChange(reduceMotion: reduceMotion), value: filter)
                    .animation(OwedMotion.listChange(reduceMotion: reduceMotion), value: feed.map(\.id))
                }
                .padding(.bottom, 24)
            }
            .refreshable {
                await model.refreshFeed()
            }
        }
        .background(T.paper)
        .sheet(item: $selected) { s in
            SettlementDetailView(settlement: s)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .sheet(isPresented: $showQuiz) {
            // Swiping the sheet away counts as "offered" too — otherwise
            // the first-launch quiz re-prompts on every launch.
            model.profileCompleted = true
            if model.profile.isEmpty && filter == .forYou { filter = .all }
        } content: {
            MatchQuizView(initial: model.profile) { answers in
                model.profile = answers
                model.profileCompleted = true
                filter = answers.isEmpty ? .all : .forYou
            }
            .presentationDragIndicator(.visible)
        }
        .task {
            // First launch: offer the quiz once. Skipping is one tap and
            // it never auto-appears again.
            if !model.profileCompleted {
                try? await Task.sleep(for: .milliseconds(350))
                showQuiz = true
            }
        }
        .onChange(of: navigation.pendingFindFilter) { _, pending in
            guard let pending else { return }
            if visibleFilters.contains(pending) {
                withAnimation(OwedMotion.listChange(reduceMotion: reduceMotion)) {
                    filter = pending
                }
            }
            navigation.pendingFindFilter = nil
        }
        .onChange(of: navigation.pendingSettlementID) { _, id in
            guard let id else { return }
            openDeepLinkedSettlement(id: id)
        }
        .onAppear {
            if let id = navigation.pendingSettlementID {
                openDeepLinkedSettlement(id: id)
            }
            if let pending = navigation.pendingFindFilter, visibleFilters.contains(pending) {
                filter = pending
                navigation.pendingFindFilter = nil
            }
        }
    }

    private func openDeepLinkedSettlement(id: String) {
        let match = model.settlements.first { $0.id == id }
            ?? model.trackedSettlements.first { $0.id == id }
        navigation.pendingSettlementID = nil
        guard let match else { return }
        selected = match
    }

    private var topBar: some View {
        HStack {
            (Text("Owed") + Text(".").foregroundStyle(T.green))
                .font(OwedFont.displayBold(24))
                .foregroundStyle(T.ink)
                .accessibilityAddTraits(.isHeader)

            Spacer()

            Button { showQuiz = true } label: {
                Image(systemName: "sparkles")
                    .font(OwedFont.icon(15))
                    .foregroundStyle(T.gold)
                    .padding(6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Tune your matches")

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
            .accessibilityLabel(model.lifetime ? "Lifetime unlocked" : "Get Lifetime for \(store.displayPrice)")
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
                heroCard(
                    amount: model.potentialRange,
                    label: "POTENTIAL ACROSS \(model.trackedSettlements.count) TRACKED"
                )
            } else if !model.matchedSettlements.isEmpty {
                heroCard(
                    amount: model.matchedRange,
                    label: "\(model.matchedSettlements.count) LIKELY \(model.matchedSettlements.count == 1 ? "MATCH" : "MATCHES") FOR YOU"
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    private func heroCard(amount: String, label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(amount)
                .font(OwedFont.displayBold(25))
                .foregroundStyle(T.green)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .contentTransition(.numericText())
            Text(label)
                .font(OwedFont.body(10, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(T.mut)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .docketSurface(cornerRadius: 14)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }

    private var forYouEmptyState: some View {
        VStack(spacing: 8) {
            Text("No matches yet")
                .font(OwedFont.display(18))
                .foregroundStyle(T.ink)
            Text("Answer a couple more quiz questions, or browse everything under All.")
                .font(OwedFont.body(13))
                .foregroundStyle(T.mut)
                .multilineTextAlignment(.center)
            Button("Tune my matches") { showQuiz = true }
                .font(OwedFont.body(13.5, weight: .bold))
                .foregroundStyle(T.green)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(visibleFilters) { f in
                    Button {
                        withAnimation(OwedMotion.selection(reduceMotion: reduceMotion)) {
                            filter = f
                        }
                    } label: {
                        Text(f.label)
                            .font(OwedFont.body(12.5, weight: .semibold))
                            .foregroundStyle(filter == f ? T.paper : T.ink)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 7)
                            .background {
                                if filter == f {
                                    Capsule()
                                        .fill(T.ink)
                                        .matchedGeometryEffect(id: "filterChip", in: filterNamespace)
                                } else {
                                    Capsule()
                                        .fill(T.card)
                                }
                            }
                            .overlay(Capsule().strokeBorder(filter == f ? T.ink : T.line, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(f.accessibilityLabel)
                    .accessibilityAddTraits(filter == f ? [.isSelected] : [])
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
        .environment(AppNavigation())
}
