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
    @State private var calendarFailed = false
    @State private var showPayoutAlert = false
    @State private var payoutText = ""

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
                verifiedRow

                if isTracked {
                    trackedSection
                } else {
                    eligibilityGate
                }
            }
            .padding(20)
            .padding(.bottom, 20)
        }
        .background(T.paper)
        .alert("Log your payout", isPresented: $showPayoutAlert) {
            TextField("Amount in dollars", text: $payoutText)
                .keyboardType(.numberPad)
            Button("Save") {
                if let amount = Int(payoutText.filter(\.isNumber)), amount > 0 {
                    model.recordPayment(settlement, amount: amount)
                }
                payoutText = ""
            }
            Button("Cancel", role: .cancel) { payoutText = "" }
        } message: {
            Text("Got your check or deposit? Log it and Owed keeps your recovered total.")
        }
    }

    /// The pre-track flow: eligibility + perjury attestation, then file.
    @ViewBuilder
    private var eligibilityGate: some View {
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
            Text("Start claim & track it")
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

    /// The post-track flow: no re-attestation, just status and one-tap
    /// actions — this is the "easy button" for claims already started.
    @ViewBuilder
    private var trackedSection: some View {
        statusCard

        Button {
            openURL(settlement.adminURL)
        } label: {
            Text("Open official claim form")
                .font(OwedFont.body(15, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(14)
                .background(T.green, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.bottom, 8)

        if !settlement.closed {
            // Added-state lives in the model so a re-opened sheet can't
            // write a duplicate event into the user's calendar.
            let calendarAdded = model.calendared.contains(settlement.id)
            secondaryButton(
                calendarAdded ? "Added to Calendar ✓" : "Add deadline to Calendar",
                icon: "calendar.badge.plus",
                disabled: calendarAdded
            ) {
                Task {
                    if let eventID = await CalendarHelper.addDeadline(for: settlement) {
                        model.markCalendared(settlement, eventIdentifier: eventID)
                        calendarFailed = false
                    } else {
                        calendarFailed = true
                    }
                }
            }
            if calendarFailed {
                Text("Calendar access is off — enable it in Settings to add deadlines.")
                    .font(OwedFont.body(11.5))
                    .foregroundStyle(T.stamp)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 8)
            }
        }

        if case .paid(let amount) = model.status(for: settlement) {
            Text("You recovered \(amount.usd) from this settlement 🎉")
                .font(OwedFont.body(13, weight: .semibold))
                .foregroundStyle(T.green)
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(T.greenSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.bottom, 8)
        } else {
            secondaryButton("Payment received? Log it", icon: "banknote") {
                showPayoutAlert = true
            }
        }

        Button("Stop tracking this claim") {
            model.untrack(settlement)
            dismiss()
        }
        .font(OwedFont.body(13.5, weight: .semibold))
        .foregroundStyle(T.stamp)
        .frame(maxWidth: .infinity)
        .padding(12)
    }

    private var statusCard: some View {
        let (label, detail): (String, String) = switch model.status(for: settlement) {
        case .actionNeeded:
            ("ACTION NEEDED", "The filing window closes in \(settlement.daysLeft) day\(settlement.daysLeft == 1 ? "" : "s"). Make sure your claim is in.")
        case .pending:
            ("FILED · PENDING", "Claims are open until the deadline. Nothing to do unless the administrator emails you.")
        case .awaitingPayout:
            ("AWAITING PAYOUT", "Claims are closed. Payouts usually follow final court approval — we'll keep the status here.")
        case .paid(let amount):
            ("PAID", "You logged \(amount.usd) received from this settlement.")
        }
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "clock.badge.checkmark")
                .font(OwedFont.icon(16))
                .foregroundStyle(T.green)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(OwedFont.mono(11))
                    .foregroundStyle(T.green)
                Text(detail)
                    .font(OwedFont.body(12.5))
                    .foregroundStyle(T.mut)
                    .lineSpacing(3)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .docketSurface(cornerRadius: 12)
        .padding(.bottom, 12)
    }

    private func secondaryButton(
        _ title: String, icon: String, disabled: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(OwedFont.icon(14))
                Text(title)
                    .font(OwedFont.body(14, weight: .semibold))
            }
            .foregroundStyle(disabled ? T.mut : T.green)
            .frame(maxWidth: .infinity)
            .padding(13)
            .docketSurface(cornerRadius: 12)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .padding(.bottom, 8)
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

    /// Provenance made visible — competitors can't show this because
    /// they don't have it (PIPELINE.md §4).
    private var verifiedRow: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(T.green)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text("VERIFIED \(settlement.verifiedAt.formatted(date: .abbreviated, time: .omitted).uppercased())")
                    .font(OwedFont.mono(11))
                    .foregroundStyle(T.green)
                Text("Deadline, payout terms, and the official form were confirmed against the court-appointed administrator.")
                    .font(OwedFont.body(11.5))
                    .foregroundStyle(T.mut)
                    .lineSpacing(3)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(T.greenSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.bottom, 14)
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
    if let first = SettlementFeed.bundled()?.settlements.first {
        SettlementDetailView(settlement: first)
            .environment(AppModel())
    }
}
