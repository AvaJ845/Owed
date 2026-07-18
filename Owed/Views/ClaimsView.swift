import SwiftUI

struct ClaimsView: View {
    @Environment(AppModel.self) private var model
    @Environment(ClaimsPrivacyGate.self) private var privacy
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selected: Settlement?
    @State private var pendingUntrack: Settlement?

    var body: some View {
        Group {
            if privacy.unlocked {
                unlockedBody
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                lockScreen
                    .transition(.opacity)
            }
        }
        .animation(OwedMotion.statusChange(reduceMotion: reduceMotion), value: privacy.unlocked)
        .background(T.paper)
        .sheet(item: $selected) { s in
            SettlementDetailView(settlement: s)
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            "Stop tracking this claim?",
            isPresented: Binding(
                get: { pendingUntrack != nil },
                set: { if !$0 { pendingUntrack = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let s = pendingUntrack {
                Button("Stop tracking", role: .destructive) {
                    withAnimation(OwedMotion.listChange(reduceMotion: reduceMotion)) {
                        model.untrack(s)
                    }
                    pendingUntrack = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingUntrack = nil }
        } message: {
            Text("Your logged payout stays on this device. You can start the claim again from Find.")
        }
    }

    private var unlockedBody: some View {
        List {
            Section {
                Text("My claims")
                    .font(OwedFont.display(24))
                    .foregroundStyle(T.ink)
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 6, trailing: 20))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .accessibilityAddTraits(.isHeader)
            }

            if !model.deadlineNotices.isEmpty {
                Section {
                    ForEach(model.deadlineNotices) { notice in
                        deadlineNoticeCard(notice)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
            }

            if model.totalRecovered > 0 {
                Section {
                    recoveredCard
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }

            Section {
                if model.trackedSettlements.isEmpty {
                    emptyState
                        .listRowInsets(EdgeInsets(top: 40, leading: 30, bottom: 40, trailing: 30))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(model.trackedSettlements) { s in
                        Button { selected = s } label: {
                            DocketCard(
                                settlement: s,
                                isTracked: true,
                                status: model.status(for: s)
                            )
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                pendingUntrack = s
                            } label: {
                                Label("Stop", systemImage: "xmark.circle")
                            }
                            .accessibilityLabel("Stop tracking \(s.name)")
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                openURL(s.adminURL)
                            } label: {
                                Label("File", systemImage: "safari")
                            }
                            .tint(T.green)
                            .accessibilityLabel("Open official claim form for \(s.name)")
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var lockScreen: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(OwedFont.icon(36))
                .foregroundStyle(T.green)
                .accessibilityHidden(true)
            Text("Claims are locked")
                .font(OwedFont.display(24))
                .foregroundStyle(T.ink)
            Text("Your tracked settlements and recovered total stay private. Unlock with \(privacy.biometryLabel) to continue.")
                .font(OwedFont.body(14))
                .foregroundStyle(T.mut)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            Button {
                Task { await privacy.unlock() }
            } label: {
                Text("Unlock with \(privacy.biometryLabel)")
                    .font(OwedFont.body(15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(14)
                    .background(T.green, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 40)
            .padding(.top, 8)
            .accessibilityHint("Authenticates with \(privacy.biometryLabel) to show your claims")
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            // Auto-prompt once when the tab appears locked.
            if !privacy.unlocked {
                _ = await privacy.unlock()
            }
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
                    .accessibilityHidden(true)

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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(model.totalRecovered.usd) recovered with Owed")
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
    }
}

#Preview {
    ClaimsView()
        .environment(AppModel())
        .environment(ClaimsPrivacyGate())
}
