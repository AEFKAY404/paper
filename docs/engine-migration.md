# Engine migration: CEF plan to WebKit

The Git baseline was inspected before the migration. A checkpoint commit preserved the AppKit-owned CEF experiment. The worktree was not reset to the initial commit.

Preserved: Xcode project and targets, original bundle identifier and sandbox, `BrowserEngine` / `BrowserSession`, `BrowserController`, navigation parsing, URL session snapshots, and mock-engine tests.

Removed from the active app: CEF-specific `main.swift` bootstrap, `PaperApplication` subclass, and `PaperAppDelegate` lifecycle. Restored SwiftUI `@main` and `WindowGroup`. No CEF binary framework, helper target, Objective-C++ bridge, runtime resource, or build phase had been added, so none needed binary removal. The active build has no CEF references. Historical investigation documents are retained and marked superseded.

Added `WebKitEngine` behind the existing protocol. The WebKit adapter controls `WKWebView`, delegates, loading state, navigation, popups, and downloads. The controller and SwiftUI shell remain renderer independent. New Xcode project settings allow outgoing network traffic and user-selected download destinations under App Sandbox.

See [architecture.md](architecture.md) for current ownership and [technical-decisions.md](technical-decisions.md) for rationale.
