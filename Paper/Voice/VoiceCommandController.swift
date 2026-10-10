import Combine
import Foundation

enum VoiceOverlayState: Equatable {
    case idle
    case preparing
    case listening
    case processing
    case result(String, success: Bool)
    case choosing(String, [VoiceTabChoice])
}

@MainActor
final class VoiceCommandController: ObservableObject {
    static let enabledKey = "paper.voice.enabled"
    @Published private(set) var state: VoiceOverlayState = .idle
    @Published private(set) var selectedChoice = 0

    private weak var browser: BrowserController?
    private weak var ui: BrowserUIState?
    private weak var onboarding: OnboardingState?
    private var openSettings: (() -> Void)?
    private let resolver: any VoiceIntentResolving
    private var capture: NativeSpeechCapture?
    private var pressed = false
    private var generation = UUID()
    private var dismissalTask: Task<Void, Never>?
    private var listeningLimitTask: Task<Void, Never>?

    private(set) var activationMilliseconds: Double?
    private(set) var recognitionMilliseconds: Double?
    private(set) var resolutionMilliseconds: Double?
    private(set) var routingMilliseconds: Double?

    init(resolver: (any VoiceIntentResolving)? = nil) {
        self.resolver = resolver ?? RuleBasedVoiceIntentResolver()
    }

    func attach(browser: BrowserController, ui: BrowserUIState, onboarding: OnboardingState,
                openSettings: @escaping () -> Void) {
        self.browser = browser
        self.ui = ui
        self.onboarding = onboarding
        self.openSettings = openSettings
    }

    func begin() {
        guard UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true else { return }
        guard !pressed, state != .listening, state != .processing else { return }
        dismissalTask?.cancel()
        pressed = true
        generation = UUID()
        let token = generation
        let began = ProcessInfo.processInfo.systemUptime
        state = .preparing
        Task { [weak self] in
            guard let self else { return }
            do {
                let service = capture ?? NativeSpeechCapture()
                capture = service
                try await service.authorize()
                guard generation == token, pressed else {
                    if generation == token { state = .idle }
                    return
                }
                try service.startCapture()
                activationMilliseconds = (ProcessInfo.processInfo.systemUptime - began) * 1_000
                state = .listening
                listeningLimitTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(12))
                    guard !Task.isCancelled else { return }
                    self?.end()
                }
            } catch {
                guard generation == token else { return }
                pressed = false
                showResult(error.localizedDescription, success: false)
            }
        }
    }

    func end() {
        guard pressed else { return }
        pressed = false
        listeningLimitTask?.cancel()
        listeningLimitTask = nil
        guard state == .listening, let capture else {
            if state == .preparing { state = .idle }
            return
        }
        state = .processing
        let token = generation
        let began = ProcessInfo.processInfo.systemUptime
        Task { [weak self] in
            let transcript = await capture.stopCapture()
            guard let self, generation == token else { return }
            recognitionMilliseconds = (ProcessInfo.processInfo.systemUptime - began) * 1_000
            guard let transcript, !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let browser else { showResult("Didn't understand", success: false); return }
            let resolutionBegan = ProcessInfo.processInfo.systemUptime
            let resolved = resolver.resolve(transcript, tabs: browser.tabs)
            resolutionMilliseconds = (ProcessInfo.processInfo.systemUptime - resolutionBegan) * 1_000
            switch resolved.intent {
            case .command(let action) where resolved.confidence == .exact || resolved.confidence == .strong:
                let routingBegan = ProcessInfo.processInfo.systemUptime
                perform(action)
                routingMilliseconds = (ProcessInfo.processInfo.systemUptime - routingBegan) * 1_000
                showResult(resolved.label, success: true)
            case .chooseTab(let choices):
                selectedChoice = 0
                state = .choosing(resolved.label, choices)
            default:
                showResult("Didn't understand", success: false)
            }
        }
    }

    func cancel() {
        generation = UUID()
        pressed = false
        listeningLimitTask?.cancel()
        dismissalTask?.cancel()
        capture?.cancel()
        state = .idle
    }

    func choose(_ index: Int) {
        guard case .choosing(_, let choices) = state, choices.indices.contains(index) else { return }
        let choice = choices[index]
        perform(.switchTab(choice.id))
        showResult(choice.title, success: true)
    }

    func handleChooserKey(_ code: UInt16) -> Bool {
        guard case .choosing(_, let choices) = state else { return false }
        switch code {
        case 125, 124: selectedChoice = (selectedChoice + 1) % choices.count
        case 126, 123: selectedChoice = (selectedChoice - 1 + choices.count) % choices.count
        case 36: choose(selectedChoice)
        case 53: state = .idle
        default: return false
        }
        return true
    }

    private func perform(_ action: PaletteAction) {
        guard let browser, let ui, let onboarding else { return }
        let search = SearchEngine(rawValue: UserDefaults.standard.string(forKey: "paper.searchEngine") ?? "") ?? .google
        BrowserActionRouter.perform(action, browser: browser, ui: ui, onboarding: onboarding,
                                    searchEngine: search, openSettings: openSettings)
    }

    private func showResult(_ message: String, success: Bool) {
        state = .result(message, success: success)
        dismissalTask?.cancel()
        dismissalTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1_300))
            guard !Task.isCancelled else { return }
            self?.state = .idle
        }
    }
}
