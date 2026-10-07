# Phase 1A status and limitations

Phase 1A is **incomplete**. Paper does not yet load sites, show a command palette, expose browser shortcuts or gestures, render multiple tabs, download files, show settings, or restore a browsing session in the launched UI. The engine-neutral controller and URL-only persistence are implemented and unit tested but are not connected to a CEF adapter.

No Paper UI tests, site-navigation tests, signing tests, or performance benchmarks were run. No cold/warm launch, CPU, memory, navigation, or 1/5/10/20-tab figures are available. Do not infer browser performance from the CEF sample launch.

CEF integration is paused at the substantial macOS lifecycle and packaging change described in [cef-feasibility.md](cef-feasibility.md). The Xcode project structure, SwiftUI entry point, test targets, bundle identifier, deployment target, and signing settings remain untouched.
