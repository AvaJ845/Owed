import SwiftUI

/// The $5.99 lifetime paywall, wired to StoreKit 2.
/// Includes Restore Purchases — an App Store review requirement for
/// non-consumables, and half the anti-subscription pitch ("you own it").
struct PaywallView: View {
    @Environment(StoreManager.self) private var store
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private static let points = [
        "Every settlement stays free to browse — no paywall, ever",
        "Lifetime unlocks deadline alerts before claims close",
        "Claim tracker with payout status across all your filings",
        "New settlements pushed the day they open",
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            seal
                .padding(.bottom, 14)

            Text("Lifetime. One payment. That's it.")
                .font(OwedFont.display(22))
                .foregroundStyle(T.ink)
                .multilineTextAlignment(.center)

            (Text(store.displayPrice).font(OwedFont.displayBold(40))
                + Text(" once, forever").font(OwedFont.body(14, weight: .semibold)).foregroundStyle(T.mut))
                .foregroundStyle(T.ink)
                .padding(.top, 8)

            VStack(spacing: 0) {
                ForEach(Self.points, id: \.self) { p in
                    HStack(alignment: .top, spacing: 10) {
                        Text("✓")
                            .font(OwedFont.body(13, weight: .bold))
                            .foregroundStyle(T.green)
                        Text(p)
                            .font(OwedFont.body(13.5))
                            .foregroundStyle(T.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 8)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(T.line).frame(height: 1)
                    }
                }
            }
            .frame(width: 300)
            .padding(.vertical, 16)

            Button {
                Task {
                    await store.purchase()
                    if store.owned {
                        model.lifetime = true
                        dismiss()
                    }
                }
            } label: {
                Group {
                    if store.purchasing {
                        ProgressView().tint(.white)
                    } else {
                        Text("Unlock lifetime — \(store.displayPrice)")
                    }
                }
                .font(OwedFont.body(15, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .background(T.green, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(store.purchasing || store.product == nil)
            .padding(.top, 6)

            Button("Maybe later") { dismiss() }
                .font(OwedFont.body(13.5, weight: .semibold))
                .foregroundStyle(T.mut)
                .padding(12)

            Button("Restore purchases") {
                Task {
                    await store.restore()
                    if store.owned {
                        model.lifetime = true
                        dismiss()
                    }
                }
            }
            .font(OwedFont.body(12))
            .foregroundStyle(T.mut)

            Text("Compare: other apps charge $9.99 every week for the same thing.")
                .font(OwedFont.body(11))
                .foregroundStyle(T.mut)
                .multilineTextAlignment(.center)
                .padding(.top, 10)

            if store.loadFailed {
                Text("Purchases are unavailable right now. Browsing stays free — try again later.")
                    .font(OwedFont.body(11))
                    .foregroundStyle(T.stamp)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(T.paper)
    }

    private var seal: some View {
        Text("OWED")
            .font(OwedFont.displayBold(11))
            .kerning(1)
            .foregroundStyle(T.gold)
            .frame(width: 64, height: 64)
            .background(T.goldSoft, in: .circle)
            .overlay(Circle().strokeBorder(T.gold, lineWidth: 2))
    }
}

#Preview {
    PaywallView()
        .environment(StoreManager())
        .environment(AppModel())
}
