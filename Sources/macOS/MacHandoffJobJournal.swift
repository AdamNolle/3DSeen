import Foundation

func completedRemoteJobIDs(in assetStore: ScanAssetStore?) -> Set<UUID> {
    guard let assetStore else { return [] }
    let fileManager = FileManager.default
    let directories = (try? fileManager.contentsOfDirectory(
        at: assetStore.rootDirectory,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
    )) ?? []
    return Set(directories.compactMap { directory in
        guard let scanID = UUID(uuidString: directory.lastPathComponent),
              let manifest = try? assetStore.loadManifest(for: scanID),
              let jobID = manifest.handoffJobID else { return nil }
        let hasModel = [manifest.usdzFileURL, manifest.sourceModelURL, manifest.previewPLYURL]
            .compactMap { $0 }
            .contains { fileManager.fileExists(atPath: $0.path) }
        return hasModel ? jobID : nil
    })
}

struct MacRemoteJobRecord: Codable, Equatable {
    let jobID: UUID
    let scanID: UUID
    let peerID: HandoffInstallationID
    var state: HandoffJobState
    var progress: Double
    var updatedAt: Date
}

final class MacHandoffJobJournal {
    private let fileURL: URL
    private(set) var records: [UUID: MacRemoteJobRecord]

    init(fileURL: URL) {
        self.fileURL = fileURL
        records = (try? JSONDecoder().decode(
            [MacRemoteJobRecord].self,
            from: Data(contentsOf: fileURL)
        ))?.reduce(into: [:]) { $0[$1.jobID] = $1 } ?? [:]
    }

    func recoverInterruptedWork(completedJobIDs: Set<UUID> = []) throws {
        for (jobID, var record) in records where !record.state.isTerminal {
            record.state = completedJobIDs.contains(record.jobID) ? .completed : .failed
            record.progress = record.state == .completed ? 1 : record.progress
            record.updatedAt = Date()
            records[jobID] = record
        }
        try persist()
    }

    func upsert(_ record: MacRemoteJobRecord) throws {
        records[record.jobID] = record
        if records.count > 256 {
            let retained = records.values.sorted { $0.updatedAt > $1.updatedAt }.prefix(256)
            records = Dictionary(uniqueKeysWithValues: retained.map { ($0.jobID, $0) })
        }
        try persist()
    }

    private func persist() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let values = records.values.sorted { $0.updatedAt > $1.updatedAt }
        let data = try JSONEncoder().encode(values)
        try data.write(to: fileURL, options: .atomic)
    }
}
