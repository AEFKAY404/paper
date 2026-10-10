import SwiftUI

struct VoiceCommandOverlay: View {
    @ObservedObject var voice: VoiceCommandController

    var body: some View {
        Group {
            switch voice.state {
            case .idle: EmptyView()
            case .preparing:
                status("Preparing microphone…", symbol: "mic", accessibility: "Preparing voice commands")
            case .listening:
                HStack(spacing: 12) {
                    Image(systemName: "mic.fill")
                    Text("Listening…")
                    Spacer(minLength: 20)
                    Button("Stop") { voice.end() }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Stop listening and run voice command")
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Listening for a voice command")
            case .processing:
                status("Understanding…", symbol: "waveform", accessibility: "Processing voice command")
            case .result(let message, let success):
                status(message, symbol: success ? "checkmark" : "questionmark", accessibility: message)
            case .choosing(let prompt, let choices):
                VStack(alignment: .leading, spacing: 4) {
                    Text(prompt).font(PaperTypography.sectionHeading).padding(.bottom, 4)
                    ForEach(Array(choices.enumerated()), id: \.element.id) { index, choice in
                        Button { voice.choose(index) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(choice.title).lineLimit(1)
                                    Text(choice.detail).font(PaperTypography.metadata).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 6).padding(.horizontal, 8)
                            .background(index == voice.selectedChoice ? Color.accentColor.opacity(0.12) : .clear,
                                        in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(choice.title), \(choice.detail)")
                    }
                    Text("Use arrow keys and Return, or click a tab. Escape cancels.")
                        .font(PaperTypography.metadata).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .contain)
            }
        }
        .font(PaperTypography.supporting)
        .padding(.horizontal, 15).padding(.vertical, 11)
        .frame(minWidth: 210, maxWidth: 380)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 5)
        .accessibilityIdentifier("paper.voice.overlay")
    }

    private func status(_ text: String, symbol: String, accessibility: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
            Text(text).lineLimit(2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility)
    }
}
