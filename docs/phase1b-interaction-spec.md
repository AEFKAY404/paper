# Phase 1B interaction specification

## Gestures and conflicts

WebKit's `allowsBackForwardNavigationGestures` remains enabled by default. Paper does not implement a competing unmodified horizontal swipe. Optional Option-swipe tab switching listens only for app-local `NSEvent.swipe` events while Paper's window is key. It requires the Option modifier, a horizontal delta of at least 0.65, horizontal dominance over vertical movement, and a 280 ms debounce. It is ignored while the palette, overview or introduction is open. Ordinary scroll, pinch, drag and text-selection events are not consumed. Custom gestures are off by default; Off and Option-swipe are the only selectable mappings. Physical trackpad behavior over horizontal/nested scrollers, interactive page elements, Mission Control, desktop switching and fullscreen requires manual verification. The keyboard alternative is Control-Tab / Control-Shift-Tab.

## Keyboard and temporary controls

| Action | Shortcut |
| --- | --- |
| Command palette / location | ⌘L |
| Tab overview | ⌘⇧\ |
| New / close tab | ⌘T / ⌘W |
| Next / previous tab | ⌃Tab / ⌃⇧Tab |
| Back / forward | ⌘[ / ⌘] |
| Reload / stop | ⌘R / ⌘. |
| Handbook | ⌘⇧/ |
| Settings | ⌘, |

The command palette offers URL/search navigation and local actions for tabs, overview, reload, history, handbook, Settings, and introduction. Arrow keys select suggestions, Return executes, and Escape dismisses. Suggestions are local; they make no network request and collect no history. The palette and menus share `BrowserActionRouter` for action execution.

The overview opens immediately, with search focused. Mouse clicks or arrow keys and Return activate a tab. Search matches title, domain and URL. Escape or Done closes the overlay; the active session regains focus. Cards show title, domain, loading and active state, with close controls and a new-tab button. A responsive grid scrolls for large tab counts. Static previews come from existing `WKWebView.takeSnapshot` calls and progressively replace placeholders. New tabs render a native Paper card. Previews are not live webpage state.

Automated UI screenshot: [tab overview with two native tabs](screenshots/tab-overview-phase1b.png).

## Motion and accessibility

Only native overlays and transient feedback use short opacity or position changes (120–160 ms). Web views switch immediately without transforms or reloads. System Reduce Motion and Paper's reduced decorative motion preference remove these animations. The overview, palette and cards use labeled native controls; selected overview cards have a visible accent border. The underlying page is hidden from accessibility while an overlay is visible. VoiceOver traversal and contrast in all macOS appearance modes still need physical verification.

## Performance decisions

At most two snapshots run concurrently. The cache holds at most 12 images or 24 MiB, with LRU eviction and a five-minute freshness limit. Navigation completion or failure invalidates a preview. Dismissal or closure cancels/discards obsolete work. Lazy grid appearance prioritizes visible cards. Opening the overview never awaits snapshots. No continuous preview rendering occurs. See [performance-benchmarks.md](performance-benchmarks.md) for measured coverage and gaps.
