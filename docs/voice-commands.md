# Native Voice Commands V1

## Use

While Paper's browser window is active, hold **Control-Shift-Space**, speak one short command, and release Space. The transient overlay shows preparation, listening, processing, and the result. It disappears automatically. This is app-local push-to-talk; Paper does not listen while the shortcut is idle. Voice Commands can be disabled in Settings. The first invocation requests Speech Recognition and microphone permission. A denial produces an explanatory result and leaves ordinary browsing available.

The suggested Option-Space shortcut was not used because macOS uses it to type a nonbreaking space in text fields. Control-Shift-Space is handled by Paper's local event monitor only when its browser window is key. macOS shortcuts are user configurable, so users with a conflicting system or custom shortcut may need to change that shortcut. Paper does not install a global event tap. The shortcut is not configurable in V1.

## Architecture

`BrowserInputMonitor` detects the hold and release. `VoiceCommandController` owns the transient UI state and lazily creates `NativeSpeechCapture`. Capture uses `AVAudioEngine` and `SFSpeechRecognizer` in the current locale. `SFSpeechAudioBufferRecognitionRequest.requiresOnDeviceRecognition` is always true. If the locale or Mac cannot provide on-device recognition, Paper reports unavailability; it never silently switches to network recognition. The audio tap stops on key release, deactivation, cancellation, or the 12-second limit. A final recognition result is given up to two seconds after release; then the task is cancelled. Captured audio is not retained.

The transcript goes to `VoiceIntentResolving`, implemented by `RuleBasedVoiceIntentResolver`. Its phrase groups, tab ranking, and confidence tiers are deterministic. Successful intents become `PaletteAction`s and run through the existing `BrowserActionRouter`, shared with menus and the command palette. The resolver is protocol-based so a future *local text classifier* could be evaluated separately; V1 contains no model, LLM, agent, or remote service.

## Supported commands

| Say | Action |
| --- | --- |
| “New tab”, “Close tab”, “New private tab” | Tab creation/closure |
| “Next tab”, “Previous tab” | Adjacent tab |
| “Switch to GitHub”, “Open the Apple tab” | Existing tab by title or host |
| “Back”, “Forward”, “Reload”, “Stop loading” | Page navigation |
| “Show tabs” | Tab overview |
| “Open privacy”, “Open settings”, “Open handbook” | Native Paper surfaces |
| “Open accounts” | Detected website sessions |
| “Search for macOS WebKit” | Search through Paper's current search setting |
| “Open github.com” | Address navigation |

Tab selection ranks exact title, host/site name, title prefix, host prefix, then bounded fuzzy similarity. Similarly ranked tabs produce a chooser instead of an arbitrary choice. The chooser accepts mouse, arrows, Enter, and Escape. Unknown phrases do nothing. V1 does not submit forms, grant site permissions, send messages, purchase items, or delete files. All supported actions remain available through keyboard, menu, palette, or their existing native control.

## Privacy and accessibility

Paper does not save audio or transcripts, log them, send them to a Paper server, or use analytics for voice. Apple Speech and macOS permission behavior still apply. The overlay labels its states and controls for VoiceOver and follows Paper's Reduce Motion setting. Settings and the handbook explain how to use voice without making it the only path to any browser action.

## Verification and performance

Automated unit tests feed text directly to the resolver and cover normalization, all core intents, unknown/unsafe phrases, exact/host/fuzzy/ambiguous tab matching, navigation input, and shared routing. The signed Debug core run passed 74 tests; the native UI suite passed 13 tests, including a Settings Voice Commands control check. The known sandbox-dependent blocker benchmark and live-site investigation suites were not part of the core run. These tests do **not** exercise the microphone, speech permission prompt, Apple recognition quality, or physical shortcut handling.

`VoiceCommandController` records transient activation, recognition, resolution, and routing durations in memory for development inspection. On this MacBook Air, one signed XCTest sample of 1,000 resolutions against 20 tabs took **865.697 ms total, 0.866 ms each**. This is a single measured text-resolver sample, not an end-to-end voice latency measurement. The test also places a loose one-second regression guard on the batch. With no invocation, the capture object and audio engine have not been created, so there is no voice audio work scheduled. Idle CPU, memory overhead, and end-to-end voice latency still need instrumented measurement on the target Mac.

## Physical validation still required

In a quiet room and with moderate background noise, test permission prompts, hold/release, every supported navigation and tab command, privacy/private tab commands, unknown phrases, chooser operation, and denied-permission recovery. Confirm the native input device stops recording on release and after Paper loses focus. Inspect the macOS microphone indicator and Activity Monitor/Signposts for actual idle and active costs. This was not established by transcript tests or UI automation.

## Current limits

- On-device recognition depends on Apple's support for the current locale and installed system assets. Paper deliberately has no cloud fallback.
- A phrase like “search Google for …” still uses Paper's selected search provider; V1 treats “Google” as a spoken search cue rather than changing providers.
- The event monitor requires Paper's browser window to be active. Voice cannot be invoked globally or while the handbook is open.
- Background noise, accents, recognition errors, physical shortcut conflicts, and microphone permission behavior have not yet been validated on hardware.

Apple references: [Speech on-device support](https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition), [requesting on-device recognition](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition), [speech authorization](https://developer.apple.com/documentation/speech/asking-permission-to-use-speech-recognition), [macOS Option-Space text behavior](https://support.apple.com/en-afri/guide/numbers/tana45192591/mac).
