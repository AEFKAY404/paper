import SwiftUI

struct NewTabView: View {
    let tabID: UUID
    let mayFocus: Bool
    let privacyMode: TabPrivacyMode
    let submit: (String) -> Void
    @State private var input = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 26) {
            TextField("", text: $input)
                .textFieldStyle(.plain)
                .font(PaperTypography.newTabInput)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .frame(width: 300, height: 58)
                .contentShape(Rectangle())
                .frame(width: 150, alignment: .leading)
                .focused($focused)
                .onSubmit { submitInput() }
                .onExitCommand { focused = false }
                .accessibilityLabel("Search or enter a URL")
                .accessibilityHint("Press Return to search or open the address")
                .accessibilityIdentifier("paper.newTab.search")

            Text(privacyMode == .private ? "Paper · Private" : "Paper")
                .font(PaperTypography.smallBrand)
                .tracking(1)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PaperSurfaceBackground.color)
        .task(id: "\(tabID)-\(mayFocus)") {
            guard mayFocus else { focused = false; return }
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            focused = true
        }
        .onChange(of: tabID) { _, _ in input = "" }
    }

    private func submitInput() {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        submit(input)
    }
}
