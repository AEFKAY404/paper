# CEF feasibility and architectural decision

> Superseded on 7 October 2026 by the [WebKit migration](engine-migration.md). This document preserves the earlier CEF investigation; its proposed integration path is no longer active.

Status: architectural review approved; the approved principal-class approach then failed its runtime check. See [cef-lifecycle-blocker.md](cef-lifecycle-blocker.md).

## Existing project

- Xcode-created SwiftUI macOS project with `Paper`, `PaperTests`, and `PaperUITests` targets. The project and bundle identifier `ark.Paper` were preserved.
- macOS deployment target 27.0; Apple Silicon host runs macOS 27.2.
- Automatic signing and `ENABLE_APP_SANDBOX = YES`. The project has no explicit network-client entitlement yet.
- No Git repository exists in the Paper directory. There was no initial commit or working-tree baseline to compare against.
- Xcode 27.0 beta is installed at `/Users/akash/Downloads/Xcode-beta.app`. The active `xcode-select` path points to Command Line Tools, so builds require `DEVELOPER_DIR=/Users/akash/Downloads/Xcode-beta.app/Contents/Developer` unless that selection changes.
- The untouched template built successfully using `xcodebuild` with a temporary DerivedData directory and signing disabled for build verification.

## Binary and local feasibility result

- The official macOS ARM64 CEF **154.0.34+g14c5a08+chromium-154.0.8037.98** distribution was downloaded into `/private/tmp`, and its SHA-1 matched the [official CEF build manifest](https://cef-builds.spotifycdn.com/index.html).
- Its `libcef_dll_wrapper` compiled successfully with Xcode 27 beta and the official CEF CMake configuration.
- The official `cefsimple` sample built and launched. The browser process and GPU, network, and renderer helper processes were observed running. This is evidence of CEF runtime feasibility on this machine, but it is not proof that Paper itself can render a website yet.
- The CEF archives and sample were kept outside the Paper project. No binary framework or generated CEF project was added to the existing Xcode project.

## Required change and tradeoff

CEF's macOS header states that **all CEF clients must subclass `NSApplication` and implement `CefAppProtocol`**. Its macOS sample also implements event handling in that subclass. Paper's current `@main` SwiftUI application uses the default application class. A robust integration therefore requires a custom `NSApplication` principal class (while retaining `PaperApp: App` and `WindowGroup`), plus an Objective-C++ bridge. Whether SwiftUI's lifecycle reliably instantiates that principal class must be verified in Paper before proceeding.

CEF also mandates a Chromium framework inside `Paper.app/Contents/Frameworks`, separate helper app bundles and executables, CEF sandbox initialization in the helper, CEF initialization/shutdown in the main process, and message-loop integration. The official sample uses its own main loop. Preserving SwiftUI's main loop requires CEF's external message pump and scheduling callback. Xcode target/build-phase and nested code-signing changes are substantial. The existing App Sandbox must be reconciled with network access and CEF helper entitlements without disabling either protection merely to launch.

**Recommended integration path after review:** retain SwiftUI `@main` and `WindowGroup`; introduce the required `NSApplication` subclass as principal class; initialize CEF from an app lifecycle hook; use the external message pump; implement a narrow Objective-C++ adapter behind `BrowserEngine`; add explicit helper targets and framework copy/sign phases; then validate a signed app with real navigation. This keeps native UI and browser state independent of CEF. An alternate dedicated CEF host process would keep CEF farther from SwiftUI's lifecycle but adds interprocess surface, input, and focus coordination, so it is a larger architecture change.

The [CEF general usage guide](https://chromiumembedded.github.io/cef/general_usage.html), [official macOS sandbox requirements](https://github.com/chromiumembedded/cef/blob/master/docs/sandbox_setup.md), and [official sample target layout](https://github.com/chromiumembedded/cef-project/blob/master/examples/minimal/CMakeLists.txt) support these requirements.

## Current decision

The principal-class change was attempted after approval. SwiftUI instantiated `SwiftUI.AppKitApplication` despite the generated Info.plist naming `PaperApplication`. The failed change was reverted and CEF has **not** been integrated into Paper. See the runtime evidence and minimal proposed alternative in [cef-lifecycle-blocker.md](cef-lifecycle-blocker.md).
