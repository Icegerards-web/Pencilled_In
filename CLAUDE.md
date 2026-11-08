# Pencilled In (iOS)

Native shell around a single-page planner. Most logic lives in `Web/index.html`.

- Native code: `App/Sources` (UIKit + WKWebView). Keep it thin: it only reads/writes files.
- Bridge: the page calls `window.webkit.messageHandlers.pencilled.postMessage({cmd, name, text})` and gets a Promise.
  Commands: `local.readAll`, `local.write`, `cloud.status`, `cloud.pick`, `cloud.unlink`, `cloud.list`, `cloud.read`, `cloud.write`, `net.fetch` (downloads a calendar link; returns text), `notify.request` (→ Bool), `notify.schedule` ({group, items:[{id,title,body,at ms}]}, replaces that group's pending local notifications).
  Native → page events: `window.__pencilledNative.event('active' | 'inactive' | 'pencilTap')`.
- Sync and three-way merge live in the `Store` object in `Web/index.html` (search for "iOS app: files on this device").
- Synced documents: `w<monday>` weeks, `todos`, `presets`, `deadlines`, `calendars`, `series` (see `SYNCED`). Device-only: `prefs`.
- Calendar import (.ics parser, recurrence expansion, applyImport) is in `Web/index.html` under "calendar import".
- No Xcode project is committed; Codemagic runs `xcodegen generate` from `project.yml`.
- Build: Codemagic `ios-unsigned` workflow → unsigned `PencilledIn.ipa` → SideStore (free Apple ID, so no iCloud entitlements).
- Repeating blocks: series definitions in `series`; each week gets real blocks with deterministic ids (`seriesBlockId`), per-week deletions in `week.sx`, individually edited copies flagged `own`.
