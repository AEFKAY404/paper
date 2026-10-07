# CEF lifecycle blocker: SwiftUI ignores the principal class

> Superseded on 7 October 2026 by the [WebKit migration](engine-migration.md). This document preserves the observed CEF lifecycle findings; the proposed alternative is no longer planned.

Date: 7 October 2026. Status: **CEF integration stopped before packaging or adapter work**.

## Reproduction in Paper

The approved first step added an `NSApplication` subclass named `PaperApplication` to the existing app target and set `INFOPLIST_KEY_NSPrincipalClass = PaperApplication` for Debug and Release. The generated `Paper.app/Contents/Info.plist` contained `NSPrincipalClass = PaperApplication`, and the project built successfully with Xcode 27 beta.

At runtime, a temporary `ContentView.onAppear` probe printed:

```text
Paper NSApp runtime class: SwiftUI.AppKitApplication
```

The `PaperApplication` initializer did not run. Thus the SwiftUI `@main` bootstrap used its own `NSApplication` class despite the Info.plist principal-class value. A successful build and a correct Info.plist were insufficient to meet CEF's macOS requirement that the actual application object implement `CefAppProtocol`.

The probe, subclass, and build-setting change were removed after this check. The existing `PaperApp: App`, `WindowGroup`, target configuration, signing, and App Sandbox settings are back to the Git baseline. No CEF framework, helper, or Objective-C++ bridge was added.

## Minimal proposed alternative, not yet attempted

Use a small explicit `main.swift` (or Objective-C bootstrap) that constructs the CEF-compatible `NSApplication` subclass before calling `PaperApp.main()`. This would require removing the `@main` attribute from `PaperApp` while retaining its SwiftUI `App` conformance and `WindowGroup`. The goal is to keep SwiftUI's scene lifecycle and install the required Cocoa application object first. This has **not** been verified; SwiftUI may still reject or replace the preexisting singleton. Test the actual `NSApp` class, event dispatch, normal window behavior, and clean termination before introducing CEF.

If that bootstrap cannot coexist with SwiftUI, a dedicated CEF host process is the next architecture option. It would preserve the current SwiftUI process but require cross-process rendering, input, focus, and lifecycle coordination. That is a larger change and was not attempted.

The instruction approving integration explicitly says to stop if SwiftUI cannot reliably use the custom principal class. This observed runtime failure meets that condition. No workaround that changes the lifecycle has been applied without further review.
