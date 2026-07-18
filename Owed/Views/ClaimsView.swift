import SwiftUI

struct ClaimsView: View {
    @Environment(AppModel.self) private var model
    @State private var selected: Settlement?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("My claims")
                    .font(OwedFont.display(24))
                    .foregroundStyle(T.ink)
                    .padding(.leading, 4)
                    .padding(.bottom, 14)

                if model.totalRecovered > 0 {
                    recoveredCard
                        .padding(.bottom, 14)
                }

                if model.trackedSettlements.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(model.trackedSettlements) { s in
                            Button { selected = s } label: {
                                DocketCard(
                                    settlement: s,
                                    isTracked: true,
                                    status: model.status(for: s)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(T.paper)
        .sheet(item: $selected) { s in
            SettlementDetailView(settlement: s)
                .presentationDragIndicator(.visible)
        }
    }

    /// Lifetime recovered total — the retention number and the screenshot
    /// users share.
    private var recoveredCard: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(model.totalRecovered.usd)
                .font(OwedFont.displayBold(25))
                .foregroundStyle(T.green)
                .contentTransition(.numericText())
            Text("RECOVERED WITH OWED")
                .font(OwedFont.body(10, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(T.mut)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .docketSurface(cornerRadius: 14)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("Nothing tracked yet")
                .font(OwedFont.display(20))
                .foregroundStyle(T.ink)
            Text("Start a claim from the Find tab and it'll live here with its payout status.")
                .font(OwedFont.body(13.5))
                .foregroundStyle(T.mut)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .padding(.horizontal, 30)
    }
}

#Preview {
    ClaimsView().environment(AppModel())
}
