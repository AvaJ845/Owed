import SwiftUI

/// The detail sheet with the eligibility + perjury attestation gate.
/// The CTA stays disabled until every eligibility box AND the attestation
/// are checked — this is a product/compliance decision, not decoration
/// (PIPELINE.md §6), and it's the trust story App Store review wants to see.
struct SettlementDetailView: View {
    let settlement: Settlement

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var checks: [Bool]
    @State private var attested = false

    init(settlement: Settlement) {
        self.settlement = settlement
        _checks = State(initialValue: Array(repeating: false, count: settlement.eligibility.count))
    }

    private var ready: Bool { checks.allSatisfy(\.self) && attested }
    private var isTracked: Bool { model.isTracked(settlement) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(settlement.caseNo)
                    .font(OwedFont.mono(11))
                    .foregroundStyle(T.mut)
                Text(settlement.name)
                    .font(OwedFont.display(22))
                    .foregroundStyle(T.ink)
                    .padding(.top, 6)
                Text(settlement.category)
                    .font(OwedFont.body(13))
                    .foregroundStyle(T.mut)
                    .padding(.top, 4)
                    .padding(.bottom, 14)

                payoutPanel

                Text("CONFIRM YOUR ELIGIBILITY")
                    .font(OwedFont.body(11, weight: .semibold))
                    .kerning(0.9)
                    .foregroundStyle(T.mut)
                    .padding(.bottom, 8)

                ForEach(settlement.eligibility.indices, id: \.self) { i in
                    CheckRow(isOn: $checks[i], label: settlement.eligibility[i])
                        .padding(.bottom, 8)
                }

                CheckRow(
                    isOn: $attested,
                    label: "I understand claims are filed under penalty of perjury and I'm only claiming settlements I genuinely qualify for."
                )
                .padding(.bottom, 8)

                disclosure

                Button(action: startClaim) {
                    Text(isTracked ? "Open official claim form" : "Start claim & track it")
                        .font(OwedFont.body(15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(14)
                        .background(ready ? T.green : T.ctaOff,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(!ready)
                .animation(.easeOut(duration: 0.2), value: ready)
                .sensoryFeedback(.success, trigger: ready) { $0 == false && $1 == true }
                .accessibilityHint(ready ? "" : "Check every eligibility box and the attestation to enable")

                Button("Not for me") { dismiss() }
                    .font(OwedFont.body(13.5, weight: .semibold))
                    .foregroundStyle(T.mut)
                    .frame(maxWidth: .infinity)
                    .padding(12)
            }
            .padding(20)
            .padding(.bottom, 20)
        }
        .background(T.paper)
    }

    private var payoutPanel: some View {
        VStack(spacing: 2) {
            Text(settlement.payoutRange)
                .font(OwedFont.displayBold(34))
                .foregroundStyle(T.green)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text("\(settlement.payoutTerms) · claims close in \(settlement.daysLeft) days")
                .font(OwedFont.body(12))
                .foregroundStyle(T.mut)
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .docketSurface(cornerRadius: 14)
        .padding(.bottom, 16)
    }

    private var disclosure: some View {
        Text("Owed links you to the court-appointed claim administrator's official form. We never file on your behalf without your review, and we never encourage claims you don't qualify for.")
            .font(OwedFont.body(11.5))
            .foregroundStyle(T.mut)
            .lineSpacing(3)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(T.goldSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color(hex: 0xE7D9B8), lineWidth: 1)
            )
            .padding(.top, 6)
            .padding(.bottom, 14)
    }

    private func startClaim() {
        model.track(settlement)
        // Deep-link to the court-appointed administrator's official form —
        // never an affiliate or lead-gen page (PIPELINE.md §6).
        openURL(settlement.adminURL)
        dismiss()
    }
}

/// Tappable eligibility checkbox row.
private struct CheckRow: View {
    @Binding var isOn: Bool
    let label: String

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.15)) { isOn.toggle() }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isOn ? T.green : .clear)
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(isOn ? T.green : T.line, lineWidth: 1.5)
                    if isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 18, height: 18)
                .padding(.top, 1)

                Text(label)
                    .font(OwedFont.body(13.5))
                    .foregroundStyle(T.ink)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .docketSurface(cornerRadius: 12)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isOn ? T.green : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isOn)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

#Preview {
    SettlementDetailView(settlement: .mockFeed[0])
        .environment(AppModel())
}
