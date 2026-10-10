# Phase 2E popup policy

`WKUIDelegate.webView(_:createWebViewWith:for:windowFeatures:)` is the native decision point. `PopupPolicy` receives WebKit's navigation type, the destination URL, the site's existing origin-scoped Popups choice, and a short per-site attempt window. It does not globally intercept events or inject a `window.open` shim.

| Request | Decision |
| --- | --- |
| Saved Block | Block |
| Missing URL or non-HTTP(S) URL | Block |
| Saved Allow | Open a Paper tab, up to three scripted requests within five seconds |
| Native `linkActivated` action | Open a Paper tab |
| Scripted request to recognized sign-in/authorization/payment destination | Ask using the existing native site-permission sheet |
| Other scripted request | Block silently |
| Third uncertain auth/payment request within five seconds | Block instead of prompting repeatedly |

Private tabs ignore saved Allow/Block decisions and ask for recognized auth/payment requests without persisting a choice. New Paper tabs inherit the source tab's privacy mode. The Privacy sheet and Settings continue to manage the Popups choice. Direct user links are not rate limited. Scripted requests are limited by the default block; recognized auth/payment prompts are capped at two per five seconds per site, and a saved Allow is limited to three scripted tabs per five seconds.

This deliberately favors a quiet default while preserving native direct links and offering a path for common authentication destinations. WebKit does not expose a public, universal user-activation bit in this delegate action, so a button's script-driven `window.open` to an unrecognized URL may be blocked even when a person clicked it. Set Popups to Allow for a trusted origin if needed. Paper still returns `nil` to WebKit and opens its own tab, so `window.opener` dependent flows and blank popups remain unsupported. The focused test verifies classification and prompt limiting; live OAuth, payment, and legitimate scripted-popup flows were not exercised with credentials.
