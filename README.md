# Pencilled In

A week planner for iPad and iPhone, made for Apple Pencil: draw time blocks, write with ink, reuse day and week presets, and drag to-dos onto the week. Plans and to-dos sync between devices through a folder in iCloud Drive.

Built unsigned with Codemagic and installed with SideStore, the same way as Time Blocker.

## Build and install
1. In Codemagic, add this repository and start the **`ios-unsigned`** workflow.
2. Download `PencilledIn.ipa` from the build's artifacts.
3. Open it in SideStore on your iPad and on your iPhone.

## Turn on iCloud sync (once per device)
On first launch the app asks you to choose a folder:
1. Tap **Choose folder**.
2. In **iCloud Drive**, create a folder called **Pencilled In** and open it.
3. Tap **Open**.

Do the same on the other device and pick the same folder. You can change or stop syncing later from **⋯ › iCloud sync**, or by tapping the status text in the bottom-right corner.

Changes usually arrive within a minute; the app checks every 20 seconds while it is open and whenever you switch back to it. If you edit on both devices at the same time, both edits are kept.

### Why a folder, not "real" iCloud
Apps installed with a free Apple ID can't use Apple's iCloud app storage (CloudKit or iCloud containers); that needs the paid developer program. Any app can, however, keep access to a folder you pick in the Files picker, and iCloud Drive syncs that folder. The data is plain JSON: one file per week (`w2026-11-02.json`), plus `todos.json` and `presets.json`.

## How it's put together
- `Web/index.html`: the whole planner (UI, Pencil handling, presets, to-dos, and the sync and merge logic).
- `App/Sources/PlannerViewController.swift`: shows the page full screen in a `WKWebView` and answers its storage requests.
- `App/Sources/DocumentStore.swift`: reads and writes the JSON files on the device and in the chosen iCloud Drive folder, using `NSFileCoordinator` so iCloud sees every change.
- `project.yml`: XcodeGen spec; Codemagic generates the Xcode project from it.
- `codemagic.yaml`: the build. It also downloads the two fonts (Hanken Grotesk and Bricolage Grotesque, both open source) into `Web/fonts`; if that fails, the app uses Avenir Next.

### Sync in short
Each document carries a timestamp. The app remembers the last version both devices agreed on (the "base"). When the copy in iCloud Drive differs, it compares all three versions item by item (blocks, ink strokes, to-dos, presets each have an id): changes from either side are kept, deletions are applied, and only a true clash on the same item falls back to the newer edit. A document you are currently dragging or editing is never merged under your Pencil; it is synced right after.

## Status
- The Swift code has not been compiled yet. If the Codemagic build fails, look at `App/Sources` first.
- The planner page and its sync logic were tested in a browser with two simulated devices sharing one folder.
