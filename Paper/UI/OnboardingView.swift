import SwiftUI

struct OnboardingView: View {
    @ObservedObject var state: OnboardingState
    let dismissPalette: () -> Void
    let newTab: () -> Void
    let nextTab: () -> Void
    let closeTab: () -> Void
    @State private var practice = ""
    @FocusState private var practiceFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("A little room to explore")
                    .font(PaperTypography.onboardingHeading)
                Spacer()
                Button("Skip") { state.skip(); dismissPalette() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .accessibilityLabel("Skip introduction")
            }
            if let step = state.step {
                Text("\(step.rawValue + 1) OF 3")
                    .font(PaperTypography.eyebrow)
                    .tracking(1.5)
                    .foregroundStyle(.secondary)
            }
            switch state.step {
            case .navigate:
                Text("No address bar stays on screen. Press ⌘L to open Paper's command palette.")
                if state.triedLocation {
                    Button("Continue") { dismissPalette(); state.continueFromLocation() }
                        .buttonStyle(.borderedProminent)
                }
            case .search:
                Text("A new tab accepts a search or a web address. Try typing either here; this practice stays on your Mac.")
                TextField("Search or enter a URL", text: $practice)
                    .textFieldStyle(.roundedBorder)
                    .focused($practiceFocused)
                    .task(id: state.step) {
                        practiceFocused = false
                        try? await Task.sleep(for: .milliseconds(30))
                        guard !Task.isCancelled else { return }
                        practiceFocused = true
                    }
                    .onSubmit { state.submitPractice(practice) }
                    .accessibilityIdentifier("paper.onboarding.practice")
                Button("Continue") { state.submitPractice(practice) }
                    .disabled(practice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            case .tabs:
                Text("Try the tab commands. You can also use their keyboard shortcuts.")
                tabAction("New tab", shortcut: "⌘T", action: .newTab, perform: newTab)
                tabAction("Next tab", shortcut: "⌃Tab", action: .nextTab, perform: nextTab)
                tabAction("Close tab", shortcut: "⌘W", action: .closeTab, perform: closeTab)
                Button("Finish") { state.complete() }
                    .buttonStyle(.borderedProminent)
                    .disabled(state.tabActions.count < 3)
            case nil:
                EmptyView()
            }
        }
        .font(PaperTypography.supporting)
        .padding(22)
        .frame(width: 350, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.quaternary))
        .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
        .onChange(of: state.step) { _, next in if next == .search { practiceFocused = true } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("paper.onboarding")
    }

    private func tabAction(_ title: String, shortcut: String, action: OnboardingTabAction,
                           perform: @escaping () -> Void) -> some View {
        Button {
            perform()
            state.record(action)
        } label: {
            HStack {
                Image(systemName: state.tabActions.contains(action) ? "checkmark.circle.fill" : "circle")
                Text(title)
                Spacer()
                Text(shortcut).font(PaperTypography.shortcut)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 3)
        .accessibilityLabel("Try \(title), \(shortcut)")
    }
}
