import SwiftUI

/// The five-tap match quiz. Runs on first launch and any time from the
/// sparkle button in the Find header. Answers stay on device (see
/// MatchKey) — the copy says so because that IS the pitch.
struct MatchQuizView: View {
    let initial: Set<MatchKey>
    let onDone: (Set<MatchKey>) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<MatchKey>

    init(initial: Set<MatchKey>, onDone: @escaping (Set<MatchKey>) -> Void) {
        self.initial = initial
        self.onDone = onDone
        _selected = State(initialValue: initial)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("MATCH QUIZ · 5 TAPS")
                    .font(OwedFont.mono(11))
                    .foregroundStyle(T.mut)

                (Text("Find what ") + Text("you're owed.").foregroundStyle(T.green))
                    .font(OwedFont.display(26))
                    .foregroundStyle(T.ink)
                    .padding(.top, 6)

                Text("Tap everything that's true for you. We'll match you to settlements you likely qualify for.")
                    .font(OwedFont.body(13.5))
                    .foregroundStyle(T.mut)
                    .lineSpacing(3)
                    .padding(.top, 6)
                    .padding(.bottom, 16)

                ForEach(MatchKey.allCases) { key in
                    QuizRow(key: key, isOn: selected.contains(key)) {
                        withAnimation(.snappy(duration: 0.15)) {
                            if selected.contains(key) { selected.remove(key) }
                            else { selected.insert(key) }
                        }
                    }
                    .padding(.bottom, 8)
                }

                privacyNote

                Button {
                    onDone(selected)
                    dismiss()
                } label: {
                    Text(selected.isEmpty ? "Save" : "Show my matches")
                        .font(OwedFont.body(15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(14)
                        .background(T.green, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)

                Button("Skip — I'll just browse") {
                    onDone(initial)
                    dismiss()
                }
                .font(OwedFont.body(13.5, weight: .semibold))
                .foregroundStyle(T.mut)
                .frame(maxWidth: .infinity)
                .padding(12)
            }
            .padding(20)
            .padding(.bottom, 16)
        }
        .background(T.paper)
    }

    private var privacyNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "iphone.and.arrow.right.inward")
                .font(OwedFont.icon(16))
                .foregroundStyle(T.green)
                .padding(.top, 1)
                .accessibilityHidden(true)
            Text("Your answers never leave this phone. Matching happens on device — nothing is uploaded, no account, ever.")
                .font(OwedFont.body(11.5))
                .foregroundStyle(T.mut)
                .lineSpacing(3)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(T.greenSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.top, 6)
        .padding(.bottom, 14)
    }
}

private struct QuizRow: View {
    let key: MatchKey
    let isOn: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                Image(systemName: key.icon)
                    .font(OwedFont.icon(16, weight: .medium))
                    .foregroundStyle(isOn ? T.green : T.mut)
                    .frame(width: 24)
                    .accessibilityHidden(true)

                Text(key.question)
                    .font(OwedFont.body(13.5, weight: .semibold))
                    .foregroundStyle(T.ink)
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isOn ? T.green : .clear)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(isOn ? T.green : T.line, lineWidth: 1.5)
                    if isOn {
                        Image(systemName: "checkmark")
                            .font(OwedFont.icon(11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .docketSurface(cornerRadius: 12)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isOn ? T.green : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isOn)
        .accessibilityLabel(key.question)
        .accessibilityValue(isOn ? "Selected" : "Not selected")
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

#Preview {
    MatchQuizView(initial: []) { _ in }
}
