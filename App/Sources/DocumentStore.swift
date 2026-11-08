import Foundation

/// Reads and writes the planner's JSON documents.
///
/// Two places hold them:
/// - this device: `Application Support/Pencilled In/` (always available, works offline)
/// - a folder in iCloud Drive that the user picks once per device. Apps installed with a free
///   Apple ID cannot use iCloud containers, but they can keep access to a folder the user picks
///   (a "security-scoped bookmark"), and iCloud Drive syncs that folder between devices.
///
/// This class only moves text around. Merging is done by the web code, which can be tested.
/// All methods are called on one serial queue owned by `PlannerViewController`.
final class DocumentStore {
    enum StoreError: LocalizedError {
        case noFolder, badName, notReachable(String)
        var errorDescription: String? {
            switch self {
            case .noFolder: return "No iCloud folder is chosen yet."
            case .badName: return "That document name isn't allowed."
            case .notReachable(let detail): return "The iCloud folder can't be opened (\(detail))."
            }
        }
    }

    static let dataFolderName = "Pencilled In"
    private static let bookmarkKey = "cloudFolderBookmark"

    private let fm = FileManager.default
    private let localDir: URL
    private var folderURL: URL?

    init() {
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        localDir = support.appendingPathComponent("Pencilled In", isDirectory: true)
        try? fm.createDirectory(at: localDir, withIntermediateDirectories: true)
        restoreFolder()
    }

    // MARK: - Names

    private func check(_ name: String?) throws -> String {
        guard let name = name, !name.isEmpty, name.count <= 80,
              name.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil,
              !name.hasPrefix("..") else { throw StoreError.badName }
        return name
    }

    // MARK: - This device

    func localReadAll() -> [String: String] {
        var out: [String: String] = [:]
        let files = (try? fm.contentsOfDirectory(at: localDir, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "json" {
            if let text = try? String(contentsOf: file, encoding: .utf8) {
                out[file.deletingPathExtension().lastPathComponent] = text
            }
        }
        return out
    }

    func localWrite(_ name: String?, _ text: String?) throws {
        let name = try check(name)
        let url = localDir.appendingPathComponent(name + ".json")
        try Data((text ?? "").utf8).write(to: url, options: .atomic)
    }

    // MARK: - iCloud Drive folder

    private func restoreFolder() {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else { return }
        _ = url.startAccessingSecurityScopedResource()
        if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: Self.bookmarkKey)
        }
        folderURL = url
    }

    /// Called with the folder the user picked in the document picker.
    func setFolder(_ url: URL) throws -> [String: Any] {
        let gotAccess = url.startAccessingSecurityScopedResource()
        do {
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            if let old = folderURL, old != url { old.stopAccessingSecurityScopedResource() }
            UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
            folderURL = url
            try ensureDataDir()
            return status()
        } catch {
            if folderURL == url {
                // Don't stay linked to a folder we are about to lose access to.
                folderURL = nil
                UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
            }
            if gotAccess { url.stopAccessingSecurityScopedResource() }
            throw StoreError.notReachable(error.localizedDescription)
        }
    }

    func unlink() -> [String: Any] {
        folderURL?.stopAccessingSecurityScopedResource()
        folderURL = nil
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        return status()
    }

    /// The folder the files live in: the picked folder itself if it is called "Pencilled In",
    /// otherwise a "Pencilled In" folder inside it.
    private var dataDir: URL? {
        guard let root = folderURL else { return nil }
        if root.lastPathComponent == Self.dataFolderName { return root }
        return root.appendingPathComponent(Self.dataFolderName, isDirectory: true)
    }

    private func ensureDataDir() throws {
        guard let dir = dataDir else { throw StoreError.noFolder }
        if fm.fileExists(atPath: dir.path) { return }
        var coordError: NSError?
        var innerError: Error?
        NSFileCoordinator().coordinate(writingItemAt: dir, options: [], error: &coordError) { url in
            do { try self.fm.createDirectory(at: url, withIntermediateDirectories: true) } catch { innerError = error }
        }
        if let e = coordError { throw e }
        if let e = innerError { throw e }
    }

    func status() -> [String: Any] {
        guard let root = folderURL, let dir = dataDir else { return ["linked": false] }
        let inICloud = (try? root.resourceValues(forKeys: [.isUbiquitousItemKey]))?.isUbiquitousItem ?? false
        return ["linked": true, "folder": displayPath(dir), "inICloud": inICloud]
    }

    private func displayPath(_ url: URL) -> String {
        let path = url.standardizedFileURL.path
        if let range = path.range(of: "com~apple~CloudDocs") {
            let rest = path[range.upperBound...].split(separator: "/").map(String.init)
            return (["iCloud Drive"] + rest).joined(separator: " › ")
        }
        let parts = url.pathComponents.suffix(2)
        return parts.joined(separator: " › ")
    }

    private func fileURL(_ name: String) throws -> URL {
        guard let dir = dataDir else { throw StoreError.noFolder }
        return dir.appendingPathComponent(name + ".json")
    }

    private func modificationTime(_ url: URL) -> Double {
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return (date?.timeIntervalSince1970 ?? 0) * 1000
    }

    /// Lists the JSON documents in the iCloud folder. Files that iCloud has not downloaded yet
    /// may show up as ".name.json.icloud" placeholders; those are reported under their real name.
    func cloudList() throws -> [[String: Any]] {
        try ensureDataDir()
        guard let dir = dataDir else { throw StoreError.noFolder }
        var result: [[String: Any]] = []
        var coordError: NSError?
        var innerError: Error?
        NSFileCoordinator().coordinate(readingItemAt: dir, options: [], error: &coordError) { url in
            do {
                let items = try self.fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.contentModificationDateKey], options: [])
                var seen = Set<String>()
                for item in items {
                    var file = item.lastPathComponent
                    if file.hasPrefix("."), file.hasSuffix(".icloud") {
                        file = String(file.dropFirst().dropLast(".icloud".count))
                    }
                    guard file.hasSuffix(".json") else { continue }
                    let name = String(file.dropLast(".json".count))
                    guard !seen.contains(name) else { continue }
                    seen.insert(name)
                    let real = dir.appendingPathComponent(file)
                    result.append(["name": name, "mtime": self.modificationTime(real)])
                }
            } catch { innerError = error }
        }
        if let e = coordError { throw e }
        if let e = innerError { throw e }
        return result
    }

    /// Returns ["text": ..., "conflicts": [...]], ["pending": true] while iCloud is still
    /// downloading the file, or nil when it does not exist.
    func cloudRead(_ name: String?) throws -> Any? {
        let url = try fileURL(try check(name))
        let placeholder = url.deletingLastPathComponent().appendingPathComponent("." + url.lastPathComponent + ".icloud")
        guard fm.fileExists(atPath: url.path) || fm.fileExists(atPath: placeholder.path) else { return nil }
        try? fm.startDownloadingUbiquitousItem(at: url)
        // A coordinated read of a file iCloud hasn't downloaded waits for the download, which would
        // stall every other request on the store queue. Report it as pending instead.
        if !fm.fileExists(atPath: url.path) { return ["pending": true] }
        let downloadStatus = (try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))?.ubiquitousItemDownloadingStatus
        if downloadStatus == .notDownloaded { return ["pending": true] }

        var text: String?
        var coordError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) { readURL in
            text = try? String(contentsOf: readURL, encoding: .utf8)
        }
        if let e = coordError { throw e }
        guard let body = text else { return ["pending": true] }

        // When two devices saved at the same moment, iCloud keeps the other copy as a "conflict version".
        // Hand those to the web code so it can merge them in instead of losing them.
        var conflicts: [String] = []
        for version in NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? [] {
            if let t = try? String(contentsOf: version.url, encoding: .utf8) { conflicts.append(t) }
        }
        return ["text": body, "conflicts": conflicts]
    }

    func cloudWrite(_ name: String?, _ text: String?, resolve: Bool) throws -> [String: Any] {
        try ensureDataDir()
        let url = try fileURL(try check(name))
        let data = Data((text ?? "").utf8)
        var coordError: NSError?
        var innerError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordError) { writeURL in
            do { try data.write(to: writeURL, options: .atomic) } catch { innerError = error }
        }
        if let e = coordError { throw e }
        if let e = innerError { throw e }
        if resolve {
            try? NSFileVersion.removeOtherVersionsOfItem(at: url)
            for version in NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? [] { version.isResolved = true }
        }
        return ["mtime": modificationTime(url)]
    }
}
