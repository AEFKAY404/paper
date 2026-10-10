# Paper

Paper is a native macOS browser built with SwiftUI, AppKit, and WebKit. Its controls stay out of the way until you invoke them: search or enter a URL on the new-tab page, use the command palette, or open the temporary tab overview.

The project is under active development. See [known limitations](docs/known-limitations.md) for features that still need hands-on validation.

## What it includes

- Persistent WebKit tabs, native history navigation, downloads, and session restoration for standard tabs.
- A command palette, spatial tab overview, keyboard shortcuts, and optional tab-switch gestures.
- Local content blocking using bundled EasyList and EasyPrivacy data, site controls, and private tabs backed by WebKit's nonpersistent data store.
- Site permissions, site-data clearing, an Accounts view based on cookie metadata, and optional on-device voice commands.

Paper does not bundle uBlock Origin or its code. Blocking behavior is limited by WebKit and Paper's own implementation; it should not be treated as equivalent to uBlock Origin.

## Build and run

Requires a Mac with a version of macOS and Xcode that supports the project's **macOS 27.0** deployment target. Select the appropriate Xcode installation first, then run:

```bash
xcodebuild -project Paper.xcodeproj -scheme Paper -configuration Debug -derivedDataPath /tmp/PaperBuild build
open /tmp/PaperBuild/Build/Products/Debug/Paper.app
```

If `xcodebuild` selects the wrong Xcode installation, set `DEVELOPER_DIR` to the actual `Contents/Developer` directory for your installed Xcode before building. You can also open `Paper.xcodeproj` in Xcode and run the `Paper` scheme.

## Everyday controls

| Action | Shortcut |
| --- | --- |
| Open command palette / enter URL | `⌘L` |
| New tab | `⌘T` |
| New private tab | `⌘⇧N` |
| Tab overview | `⌘⇧\` |
| Next / previous tab | `⌃Tab` / `⌃⇧Tab` |
| On-device voice command (hold to speak) | `⌃⇧Space` |

The command palette also opens Privacy, Accounts, Settings, and the in-app handbook. Voice commands require macOS microphone and Speech Recognition permission and may be unavailable for some locales. See the [interaction specification](docs/phase1b-interaction-spec.md), [privacy controls](docs/privacy-controls.md), and [voice command guide](docs/voice-commands.md) for details.

## Development

Run the project's test scheme with:

```bash
xcodebuild -project Paper.xcodeproj -scheme Paper -configuration Debug -derivedDataPath /tmp/PaperBuild test
```

Some live-site and performance suites depend on network access, macOS permissions, or a particular environment. The [architecture](docs/architecture.md) and [development roadmap](docs/development-roadmap.md) describe the current design and verification state.

## Licenses and attribution

Paper includes EasyList, EasyPrivacy, and the Public Suffix List as bundled data. Their licenses, source revisions, and attribution are listed in [Third-Party Notices](THIRD_PARTY_NOTICES.md). The generated filter data derives from the bundled EasyList and EasyPrivacy snapshots and remains subject to their license.

**No project-wide license has been granted for Paper's own source code or artwork.** Public availability of this repository does not, by itself, grant permission to reuse those parts. The third-party data retains its own licenses; this statement does not narrow those licenses. A project-wide license should be chosen before offering Paper as reusable open-source software.
