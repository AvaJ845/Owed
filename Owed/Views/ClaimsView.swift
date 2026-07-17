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

                if model.trackedSettlements.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(model.trackedSettlements) { s in
                            Button { selected = s } label: {
                                DocketCard(settlement: s, isTracked: true)
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
