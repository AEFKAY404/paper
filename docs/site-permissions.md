# Site permissions — Phase 2B

Paper mediates WebKit's public macOS `WKUIDelegate` hooks for camera, microphone and geolocation, plus popup creation requests. Permission keys are normalized **origins** (scheme, host and nondefault port), so an Allow for `https://news.example.com` does not grant `https://accounts.example.com` or plain HTTP. Blocker exceptions and data clearing separately use registrable domains. The default is Ask. Paper presents an `NSAlert` sheet with Allow, Block, and an optional “Remember for this site” checkbox. A missing window denies the request. macOS device authorization remains a separate gate.

Remembered Allow/Block choices live in local `UserDefaults`. The Privacy sheet displays and changes the current site's future decisions; Settings lists sites with stored decisions and lets users revoke all choices for a site. Private tabs ignore remembered choices and do not save new ones. A combined camera-and-microphone request requires both permissions. A Block decision wins if either is blocked.

Notification permission is labelled “Managed by WebKit” because the installed public macOS `WKUIDelegate` does not expose an equivalent notification decision hook. Paper does not pretend to enforce Ask/Allow/Block for it.

WebKit's `createWebViewWith` delegate returns a view synchronously. Paper currently asks before opening a requested popup URL in a separate Paper tab, then returns `nil` to WebKit. This cannot preserve JavaScript `window.opener` behavior; some OAuth flows that require an opener may fail. Blank popups without a URL are unsupported. These flows need hands-on testing with non-sensitive accounts before stronger compatibility claims.
