# Pencilled In (iOS)

Native shell around a single-page planner. Most logic lives in `Web/index.html`.

- Native code: `App/Sources` (UIKit + WKWebView). Keep it thin: it only reads/writes files.
- Bridge: the page calls `window.webkit.messageHandlers.pencilled.postMessage({cmd, name, text})` and gets a Promise.
  Commands: `local.readAll`, `local.write`, `cloud.status`, `cloud.pick`, `cloud.unlink`, `cloud.list`, `cloud.read`, `cloud.write`, `net.fetch` (downloads a calendar link; returns text).
  Native → page events: `window.__pencilledNative.event('active' | 'inactive')`.
- Sync and three-way merge live in the `Store` object in `Web/index.html` (search for "iOS app: files on this device").
- Synced documents: `w<monday>` weeks, `todos`, `presets`, `deadlines`, `calendars` (see `SYNCED`). Device-only: `prefs`.
- Calendar import (.ics parser, recurrence expansion, applyImport) is in `Web/index.html` under "calendar import".
- No Xcode project is committed; Codemagic runs `xcodegen generate` from `project.yml`.
- Build: Codemagic `ios-unsigned` workflow → unsigned `PencilledIn.ipa` → SideStore (free Apple ID, so no iCloud entitlements).
