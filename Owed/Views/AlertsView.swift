import SwiftUI

/// Alerts tab — doubles as the upsell surface when lifetime isn't owned.
struct AlertsView: View {
    @Environment(AppModel.self) private var model
    @Environment(StoreManager.self) private var store
    @State private var showPaywall = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Alerts")
                .font(OwedFont.display(24))
                .foregroundStyle(T.ink)
                .padding(.leading, 4)
                .padding(.bottom, 14)

            if model.lifetime { covered } else { upsell }

            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(T.paper)
        .sheet(isPresented: $showPaywall) { PaywallView() }
    }

    private var covered: some View {
        VStack(spacing: 6) {
            Text("You're covered")
                .font(OwedFont.display(20))
                .foregroundStyle(T.ink)
            Text("We'll ping you the day a new settlement opens and 7 days before any tracked claim closes.")
                .font(OwedFont.body(13.5))
                .foregroundStyle(T.mut)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .padding(.horizontal, 20)
    }

    private var upsell: some View {
        VStack(spacing: 6) {
            Text("Deadline alerts are a lifetime perk")
                .font(OwedFont.display(20))
                .foregroundStyle(T.ink)
                .multilineTextAlignment(.center)
            Text("One \(store.displayPrice) payment, forever. No subscription, no weekly bill.")
                .font(OwedFont.body(13.5))
                .foregroundStyle(T.mut)
                .multilineTextAlignment(.center)

            Button { showPaywall = true } label: {
                Text("Unlock lifetime — \(store.displayPrice)")
                    .font(OwedFont.body(15, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 13)
                    .background(T.green, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 18)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .padding(.horizontal, 20)
    }
}

#Preview {
    AlertsView()
        .environment(AppModel())
        .environment(StoreManager())
}
