import AppKit
import Foundation

struct SiteDataSummary: Equatable {
    var cookies = 0
    var localStorage = false
    var cache = false
    var other = false
}

/// Events emitted by an engine session. No renderer-specific type crosses this boundary.
enum BrowserEvent {
    case urlChanged(URL?)
    case titleChanged(String)
    case loadingChanged(Bool)
    case navigationChanged(canGoBack: Bool, canGoForward: Bool)
    case navigationFailed(String)
    case navigationSucceeded
    case surfaceColorChanged(NSColor?)
    case blockerStatistics(BlockerStatistics)
    case openNewTab(URL)
}

@MainActor
protocol BrowserSession: AnyObject {
    var view: NSView { get }
    var onEvent: ((BrowserEvent) -> Void)? { get set }
    func load(_ url: URL)
    func goBack()
    func goForward()
    func reload()
    func stop()
    func focus()
    func setHistorySwipe(enabled: Bool)
    func refreshSurfaceColor()
    func snapshot(maxWidth: CGFloat) async -> NSImage?
    func siteDataSummary(for site: String) async -> SiteDataSummary
    func clearSiteData(for site: String) async
    func close()
}

extension BrowserSession {
    func refreshSurfaceColor() {}
}

@MainActor
protocol BrowserEngine {
    func makeSession(privacyMode: TabPrivacyMode) -> any BrowserSession
}
