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

                ForEach(model.deadlineNotices) { notice in
                    deadlineNoticeCard(notice)
                        .padding(.bottom, 10)
                }

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

    /// A court moved a deadline on a tracked claim. Shown until the user
    /// dismisses it — reminders were already rescheduled. Calendar may
    /// have updated in place; if not (write-only access), offer re-add.
    private func deadlineNoticeCard(_ notice: AppModel.DeadlineNotice) -> some View {
        let needsCalendarReadd = !model.calendared.contains(notice.settlementID)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(OwedFont.icon(16))
                    .foregroundStyle(T.stamp)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Deadline changed")
                        .font(OwedFont.body(12.5, weight: .bold))
                        .foregroundStyle(T.ink)
                    Text(needsCalendarReadd
                         ? "\(notice.name) now closes \(notice.newDeadline.formatted(date: .abbreviated, time: .omitted)) (was \(notice.oldDeadline.formatted(date: .abbreviated, time: .omitted))). Reminders are updated — tap below to put the new date on your calendar."
                         : "\(notice.name) now closes \(notice.newDeadline.formatted(date: .abbreviated, time: .omitted)) (was \(notice.oldDeadline.formatted(date: .abbreviated, time: .omitted))). Reminders and your calendar event are updated.")
                        .font(OwedFont.body(12))
                        .foregroundStyle(T.mut)
                }

                Spacer(minLength: 4)

                Button {
                    model.dismissDeadlineNotice(notice)
                } label: {
                    Image(systemName: "xmark")
                        .font(OwedFont.icon(11, weight: .bold))
                        .foregroundStyle(T.mut)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss deadline change notice")
            }

            if needsCalendarReadd {
                Button {
                    Task {
                        if await model.readdCalendar(for: notice) {
                            model.dismissDeadlineNotice(notice)
                        }
                    }
                } label: {
                    Text("Add updated date to Calendar")
                        .font(OwedFont.body(12.5, weight: .bold))
                        .foregroundStyle(T.green)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(T.stampSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
