import Foundation
import MultipeerConnectivity

extension ComputeCoordinator {
    func receiveHandoff(archive: URL, peer: MCPeerID, metadata: ScanHandoffMetadata) async {
        guard let peerID = network.installationID(for: peer), pairing.isAuthenticated(peerID) else {
            network.removeReceivedResource(archive)
            addLog("Rejected unauthenticated scan resource from \(peer.displayName)")
            return
        }
        let expiredOfferIDs = pruneExpiredPendingOffers()
        if let jobID = metadata.jobID, expiredOfferIDs.contains(jobID) {
            network.removeReceivedResource(archive)
            return
        }
        if let jobID = metadata.jobID {
            guard let offer = pendingOffers[jobID],
                  offer.peerID == peerID,
                  offer.scanID == metadata.scanID,
                  (try? HandoffResourceDescriptor.inspect(archive)) == offer.offer.resource else {
                network.removeReceivedResource(archive)
                if let scanID = metadata.scanID,
                   remoteJobJournal.records[jobID]?.peerID == peerID,
                   remoteJobJournal.records[jobID]?.scanID == scanID {
                    recordRemoteJob(jobID: jobID, scanID: scanID, peerID: peerID, state: .failed, progress: 0)
                }
                send(
                    .failed(HandoffFailure(code: .corruptArchive, detail: "The offered resource digest did not match.")),
                    jobID: jobID,
                    scanID: metadata.scanID,
                    to: peerID
                )
                addLog("Rejected uncorrelated or corrupt job resource")
                return
            }
            pendingOffers.removeValue(forKey: jobID)
            updateQueueProjection()
        }
        await enqueueHandoff(archive: archive, peer: peer, peerID: peerID, metadata: metadata)
    }

    func enqueueHandoff(
        archive: URL,
        peer: MCPeerID,
        peerID: HandoffInstallationID,
        metadata: ScanHandoffMetadata
    ) async {
        guard let values = try? archive.resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = values.fileSize,
              fileSize > 0 else {
            rejectHandoffArchive(archive, peerID: peerID, metadata: metadata, detail: "The received scan size could not be verified.")
            return
        }
        let byteCount = Int64(fileSize)
        let queuedByteCount = pendingHandoffs.reduce(Int64(0)) { total, handoff in
            let (next, overflow) = total.addingReportingOverflow(handoff.byteCount)
            return overflow ? Int64.max : next
        }
        guard HandoffResourceAdmissionPolicy.admitsQueuedResource(
            queuedResourceCount: pendingHandoffs.count,
            queuedByteCount: queuedByteCount,
            activeByteCount: activeHandoffByteCount,
            incomingByteCount: byteCount
        ) else {
            rejectHandoffArchive(archive, peerID: peerID, metadata: metadata, detail: "The compute hand-off queue is full or exceeds its storage limit.")
            return
        }
        pendingHandoffs.append(.init(
            archive: archive,
            byteCount: byteCount,
            replyPeer: peer,
            peerInstallationID: peerID,
            metadata: metadata
        ))
        updateQueueProjection()
        addLog("Queued hand-off from \(peer.displayName) (\(pendingHandoffs.count) waiting)")
        guard !isDrainingHandoffs else { return }
        isDrainingHandoffs = true
        defer { isDrainingHandoffs = false }
        while !pendingHandoffs.isEmpty {
            let handoff = pendingHandoffs.removeFirst()
            activeHandoffByteCount = handoff.byteCount
            updateQueueProjection()
            await process(
                archive: handoff.archive,
                replyPeer: handoff.replyPeer,
                captureMode: handoff.metadata.captureMode,
                detailTier: handoff.metadata.detailTier,
                sourceScanID: handoff.metadata.scanID,
                replyPeerID: handoff.peerInstallationID,
                jobID: handoff.metadata.jobID
            )
            activeHandoffByteCount = 0
        }
    }

    func pruneExpiredPendingOffers(now: Date = Date()) -> Set<UUID> {
        let expiredOffers = pendingOffers.filter { $0.value.expiresAt <= now }
        for (jobID, offer) in expiredOffers {
            pendingOffers.removeValue(forKey: jobID)
            recordRemoteJob(jobID: jobID, scanID: offer.scanID, peerID: offer.peerID, state: .failed, progress: 0)
            send(
                .failed(HandoffFailure(code: .timedOut, detail: "The compute offer expired before its scan arrived.")),
                jobID: jobID,
                scanID: offer.scanID,
                to: offer.peerID
            )
        }
        if !expiredOffers.isEmpty { updateQueueProjection() }
        return Set(expiredOffers.keys)
    }

    private func rejectHandoffArchive(
        _ archive: URL,
        peerID: HandoffInstallationID,
        metadata: ScanHandoffMetadata,
        detail: String
    ) {
        network.removeReceivedResource(archive)
        if let jobID = metadata.jobID, let scanID = metadata.scanID {
            recordRemoteJob(jobID: jobID, scanID: scanID, peerID: peerID, state: .failed, progress: 0)
            send(.failed(HandoffFailure(code: .transferFailed, detail: detail)), jobID: jobID, scanID: scanID, to: peerID)
        }
        addLog("Rejected scan hand-off: \(detail)")
    }
}
