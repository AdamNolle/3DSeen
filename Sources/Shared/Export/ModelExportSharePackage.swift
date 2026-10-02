import Foundation
import ZIPFoundation

/// Package an app-owned export folder so material and image references survive sharing.
/// Each format has its own folder; sharing never collects other formats or captured sources.
enum ModelExportSharePackage {
    static func prepare(for modelURL: URL, measurementURL: URL?) throws -> URL? {
        let fileManager = FileManager.default
        let directory = modelURL.deletingLastPathComponent()
        let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil,
                                                       options: [.skipsHiddenFiles])
        let companionFiles = files.filter {
            $0.lastPathComponent != modelURL.lastPathComponent
                && $0.pathExtension.lowercased() != "csv"
        }
        guard !companionFiles.isEmpty else { return nil }
        let packages = directory.deletingLastPathComponent().appendingPathComponent("SharePackages", isDirectory: true)
        try fileManager.createDirectory(at: packages, withIntermediateDirectories: true)
        let output = packages.appendingPathComponent(modelURL.lastPathComponent + ".zip")
        let pending = packages.appendingPathComponent(".pending-\(UUID().uuidString).zip")
        let staging = packages.appendingPathComponent(".pending-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? fileManager.removeItem(at: pending)
            try? fileManager.removeItem(at: staging)
        }
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        for file in files where file.pathExtension.lowercased() != "csv"
            || file.lastPathComponent == measurementURL?.lastPathComponent {
            try fileManager.copyItem(at: file, to: staging.appendingPathComponent(file.lastPathComponent))
        }
        try fileManager.zipItem(at: staging, to: pending, shouldKeepParent: false)
        if fileManager.fileExists(atPath: output.path) {
            _ = try fileManager.replaceItemAt(output, withItemAt: pending)
        } else {
            try fileManager.moveItem(at: pending, to: output)
        }
        return output
    }
}
