# Pencilled In (iOS)

Native shell around a single-page planner. Most logic lives in `Web/index.html`.

- Native code: `App/Sources` (UIKit + WKWebView). Keep it thin: it only reads/writes files.
- Bridge: the page calls `window.webkit.messageHandlers.pencilled.postMessage({cmd, name, text})` and gets a Promise.
  Commands: `local.readAll`, `local.write`, `cloud.status`, `cloud.pick`, `cloud.unlink`, `cloud.list`, `cloud.read`, `cloud.write`.
  Native → page events: `window.__pencilledNative.event('active' | 'inactive')`.
- Sync and three-way merge live in the `Store` object in `Web/index.html` (search for "iOS app: files on this device").
- No Xcode project is committed; Codemagic runs `xcodegen generate` from `project.yml`.
- Build: Codemagic `ios-unsigned` workflow → unsigned `PencilledIn.ipa` → SideStore (free Apple ID, so no iCloud entitlements).
