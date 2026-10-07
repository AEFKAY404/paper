import Combine
import Foundation

@MainActor
final class BrowserUIState: ObservableObject {
    @Published var isPaletteVisible = false
    @Published var paletteInput = ""
    @Published private(set) var focusRequest = 0
    @Published var isHandbookVisible = false

    func openPalette(prefill: String = "") {
        paletteInput = prefill
        isPaletteVisible = true
        focusRequest += 1
    }

    func dismissPalette() {
        isPaletteVisible = false
    }

    func openHandbook() {
        dismissPalette()
        isHandbookVisible = true
    }
}
