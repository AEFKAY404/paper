import SwiftUI

struct NewTabView: View {
    let tabID: UUID
    let searchEngine: SearchEngine
    let mayFocus: Bool
    let submit: (String) -> Void
    @State private var input = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 6) {
                Text("Paper")
                    .font(PaperTypography.brand)
                    .tracking(-2)
                Text("The web, without the browser.")
                    .font(PaperTypography.supporting)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: 14) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("", text: $input, prompt: Text(placeholder)
                    .font(PaperTypography.newTabInput)
                    .foregroundStyle(PaperTypography.placeholderColor))
                    .textFieldStyle(.plain)
                    .font(PaperTypography.newTabInput)
                    .focused($focused)
                    .onSubmit { submitInput() }
                    .onExitCommand { focused = false }
                    .accessibilityLabel("Search or enter a URL")
                    .accessibilityHint("Press Return to search or open the address")
                    .accessibilityIdentifier("paper.newTab.search")
            }
            .padding(.horizontal, 20)
            .frame(height: 58)
            .frame(maxWidth: 620)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 17))
            .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(.quaternary))
            .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: "\(tabID)-\(mayFocus)") {
            guard mayFocus else { focused = false; return }
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            focused = true
        }
        .onChange(of: tabID) { _, _ in input = "" }
    }

    private var placeholder: String {
        searchEngine == .google ? "Search Google or enter a URL" : "Search \(searchEngine.title) or enter a URL"
    }

    private func submitInput() {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        submit(input)
    }
}
