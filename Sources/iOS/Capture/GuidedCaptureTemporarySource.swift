import Foundation

enum GuidedCaptureTemporarySource {
    private static let prefixes = ["guided-object-", "landscape-", "space-"]

    static func isOwned(_ url: URL, temporaryDirectory: URL = FileManager.default.temporaryDirectory) -> Bool {
        let root = temporaryDirectory.standardizedFileURL
        let candidate = url.standardizedFileURL
        guard candidate.deletingLastPathComponent() == root else { return false }
        return prefixes.contains { prefix in
            candidate.lastPathComponent.hasPrefix(prefix)
                && !candidate.lastPathComponent.dropFirst(prefix.count).isEmpty
        }
    }

    static func discardIfOwned(
        _ url: URL,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) throws {
        guard isOwned(url, temporaryDirectory: temporaryDirectory) else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
