import Combine
import Foundation
import MultipeerConnectivity
import SwiftData

struct HandoffCompletion: Equatable {
    let scanID: UUID
    let modelURL: URL
}

/// App-lifetime iOS owner for Multipeer handoff, durable job projection, and result import.
/// Compute views invoke this service but never own the session that must receive returned models.
@MainActor
final class IOSHandoffCoordinator: ObservableObject {
    private struct PendingOutboundJob {
        let packageURL: URL
        let metadata: ScanHandoffMetadata
    }

    private struct ExpectedResult {
        let jobID: UUID
        let scanID: UUID
        let peerID: HandoffInstallationID
        let descriptor: HandoffResourceDescriptor
    }

    private struct PendingResult {
        let packageURL: URL
        let expected: ExpectedResult
    }

    @Published private(set) var discoveredPeers: [HandoffPeer] = []
    @Published private(set) var connectedPeers: [HandoffPeer] = []
    @Published private(set) var pendingInvitations: [HandoffInvitation] = []
    @Published private(set) var pendingPairingRequests: [HandoffPairingRequest] = []
    @Published private(set) var authenticatedPeerIDs: Set<HandoffInstallationID> = []
    @Published private(set) var trustedPeerIDs: Set<HandoffInstallationID> = []
    @Published var selectedPeerID: HandoffInstallationID?
    @Published private(set) var transferProgress: Double = 0
    @Published private(set) var jobs: [HandoffJobRecord] = []
    @Published private(set) var lastCompletion: HandoffCompletion?
    @Published private(set) var lastErrorMessage: String?

    private let transport: any ScanHandoffTransport
    private let pairing: HandoffPairingCoordinator
    private let journal: HandoffJobJournal
    private var modelContext: ModelContext?
    private var pendingResults: [PendingResult] = []
    private var earlyResultResources: [UUID: (URL, MCPeerID)] = [:]
    private var pendingOutboundJobs: [UUID: PendingOutboundJob] = [:]
    private var expectedResults: [UUID: ExpectedResult] = [:]
    private var journalWriteTask: Task<Void, Never>?
    private let offerTimeout: TimeInterval
    private let processingTimeout: TimeInterval
    private let assetStoreRootDirectory: URL?
    private let persistContext: (ModelContext) throws -> Void
    private var cancellables = Set<AnyCancellable>()

    init(
        transport: (any ScanHandoffTransport)? = nil,
        journal: HandoffJobJournal? = nil,
        credentialStore: (any PairingCredentialStore)? = nil,
        offerTimeout: TimeInterval = 30,
        processingTimeout: TimeInterval = 7_200,
        assetStoreRootDirectory: URL? = nil,
        persistContext: @escaping (ModelContext) throws -> Void = { try $0.save() }
    ) {
        let selectedTransport = transport ?? NetworkHandoffManager()
        let selectedPairing = HandoffPairingCoordinator(
            transport: selectedTransport,
            credentialStore: credentialStore
        )
        self.transport = selectedTransport
        self.pairing = selectedPairing
        self.journal = journal ?? HandoffJobJournal(fileURL: Self.defaultJournalURL())
        self.offerTimeout = offerTimeout
        self.processingTimeout = processingTimeout
        self.assetStoreRootDirectory = assetStoreRootDirectory
        self.persistContext = persistContext
        self.discoveredPeers = selectedTransport.discoveredPeers
        self.connectedPeers = selectedTransport.connectedHandoffPeers
        self.pendingInvitations = selectedTransport.pendingInvitations
        self.pendingPairingRequests = selectedPairing.pendingRequests
        self.authenticatedPeerIDs = selectedPairing.authenticatedPeerIDs
        self.trustedPeerIDs = selectedPairing.trustedPeerIDs
        self.transferProgress = selectedTransport.transferProgress

        selectedTransport.discoveredPeersPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.discoveredPeers = $0 }
            .store(in: &cancellables)
        selectedTransport.connectedHandoffPeersPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] peers in self?.reconcileConnectedPeers(peers) }
            .store(in: &cancellables)
        selectedTransport.pendingInvitationsPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.pendingInvitations = $0 }
            .store(in: &cancellables)
        selectedTransport.transferProgressPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.transferProgress = $0 }
            .store(in: &cancellables)
        selectedTransport.controlEventsPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.handleControlEvent($0) }
            .store(in: &cancellables)
        Timer.publish(every: 5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] in self?.expireTimedOutJobs(now: $0) }
            .store(in: &cancellables)
        selectedPairing.$pendingRequests
            .sink { [weak self] in self?.pendingPairingRequests = $0 }
            .store(in: &cancellables)
        selectedPairing.$authenticatedPeerIDs
            .sink { [weak self] in self?.reconcileAuthenticatedPeerIDs($0) }
            .store(in: &cancellables)
        selectedPairing.$trustedPeerIDs
            .sink { [weak self] in self?.trustedPeerIDs = $0 }
            .store(in: &cancellables)
        selectedPairing.$lastError
            .compactMap { $0 }
            .sink { [weak self] in self?.lastErrorMessage = $0 }
            .store(in: &cancellables)
        selectedTransport.onReceiveResultPackage = { [weak self] url, peer, metadata in
            self?.receiveResultPackage(url, from: peer, metadata: metadata)
        }
        selectedTransport.onSendError = { [weak self] error in
            self?.handleSendFailure(error)
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                let restoredJobs = try await self.journal.markInterruptedWork()
                let liveIDs = Set(jobs.map(\.id))
                jobs.append(contentsOf: restoredJobs.filter { !liveIDs.contains($0.id) })
                jobs.sort { $0.updatedAt > $1.updatedAt }
                reconcileScanStatuses()
                requestRemoteStatuses()
            } catch {
                lastErrorMessage = "Handoff history could not be restored: \(error.localizedDescription)"
            }
        }
    }

    func attach(modelContext: ModelContext) {
        self.modelContext = modelContext
        reconcileScanStatuses()
        let readyResults = pendingResults
        pendingResults.removeAll()
        for result in readyResults {
            importResultPackage(result.packageURL, expected: result.expected)
        }
    }

    var hasAuthenticatedConnectedPeer: Bool {
        connectedPeers.contains { authenticatedPeerIDs.contains($0.installationID) }
    }

    var selectedPeer: HandoffPeer? {
        guard let selectedPeerID else { return nil }
        return connectedPeers.first { $0.installationID == selectedPeerID }
    }

    func selectPeer(_ peerID: HandoffInstallationID) {
        guard connectedPeers.contains(where: { $0.installationID == peerID }) else { return }
        selectedPeerID = peerID
    }

    func respond(to invitation: HandoffInvitation, accept: Bool) {
        transport.respond(to: invitation.id, accept: accept)
        if accept { selectedPeerID = invitation.peer.installationID }
    }

    func confirmPairing(_ request: HandoffPairingRequest) {
        pairing.confirm(request)
    }

    func rejectPairing(_ request: HandoffPairingRequest) {
        pairing.reject(request)
    }

    func forgetPeer(_ peerID: HandoffInstallationID) {
        pairing.forget(peerID)
    }

    func clearError() {
        lastErrorMessage = nil
    }

    @discardableResult
    func startOffload(scan: ScanSession) -> Bool {
        guard scan.computeStatus != .completed || scan.displayModelURL == nil else {
            fail("This scan already has a completed model.", scan: scan)
            return false
        }
        guard let selectedPeerID,
              let selectedPeer = transport.connectedHandoffPeers.first(where: {
                  $0.installationID == selectedPeerID
              }) else {
            scan.computeStatusRaw = ScanComputeStatus.queued.rawValue
            saveContext()
            fail("Select an approved connected Mac or choose on-device compute.", scan: scan)
            return false
        }
        guard pairing.isAuthenticated(selectedPeerID) else {
            scan.computeStatusRaw = ScanComputeStatus.queued.rawValue
            saveContext()
            fail("Confirm the six-digit code before sending this scan.", scan: scan)
            return false
        }
        guard let rawArchiveURL = scan.rawArchiveURL else {
            fail("Capture package is missing for Mac handoff.", scan: scan)
            return false
        }

        let packageURL: URL
        do {
            packageURL = try ScanHandoffArchive.package(
                rawArchiveURL,
                captureQualityReport: scan.captureQualityReport
            )
        } catch {
            fail(error.localizedDescription, scan: scan)
            return false
        }

        let resource: HandoffResourceDescriptor
        do {
            resource = try HandoffResourceDescriptor.inspect(packageURL)
        } catch {
            fail("The capture package could not be verified. \(error.localizedDescription)", scan: scan)
            return false
        }
        var record = HandoffJobRecord(
            scanID: scan.id,
            peerName: selectedPeer.displayName,
            peerInstallationID: selectedPeerID,
            captureMode: scan.captureMode ?? .object,
            detailTier: scan.tierRaw,
            responseDeadline: Date().addingTimeInterval(offerTimeout)
        )
        do {
            try record.transition(to: .awaitingPeer)
            try record.transition(to: .offered)
        } catch {
            fail(error.localizedDescription, scan: scan)
            return false
        }
        let metadata = ScanHandoffMetadata(
            jobID: record.id,
            scanID: scan.id,
            captureMode: scan.captureMode,
            detailTier: scan.tierRaw
        )
        pendingOutboundJobs[record.id] = PendingOutboundJob(packageURL: packageURL, metadata: metadata)
        upsert(record)

        let message = HandoffMessageEnvelope(
            jobID: record.id,
            scanID: scan.id,
            senderInstallationID: transport.localInstallationID,
            payload: .jobOffer(HandoffJobOffer(
                captureMode: scan.captureMode ?? .object,
                detailTier: scan.tierRaw,
                resource: resource
            ))
        )
        guard transport.send(message, to: selectedPeerID) else {
            pendingOutboundJobs.removeValue(forKey: record.id)
            fail("The connected Mac could not accept this offer.", scan: scan, jobID: record.id)
            return false
        }

        scan.computeStatusRaw = ScanComputeStatus.offloaded.rawValue
        saveContext()
        lastErrorMessage = nil
        return true
    }

    func cancel(scan: ScanSession) {
        guard let index = jobs.firstIndex(where: { $0.scanID == scan.id && !$0.state.isTerminal }) else {
            return
        }
        var record = jobs[index]
        if let peerID = record.peerInstallationID, pairing.isAuthenticated(peerID) {
            _ = transport.send(
                HandoffMessageEnvelope(
                    jobID: record.id,
                    scanID: record.scanID,
                    senderInstallationID: transport.localInstallationID,
                    payload: .cancel
                ),
                to: peerID
            )
        }
        try? record.transition(to: .cancelled)
        pendingOutboundJobs.removeValue(forKey: record.id)
        clearResultState(forJob: record.id)
        upsert(record)
        scan.computeStatusRaw = ScanComputeStatus.queued.rawValue
        saveContext()
    }

    func retry(scan: ScanSession) -> Bool {
        guard scan.computeStatus != .completed else { return false }
        return startOffload(scan: scan)
    }

    func fallbackToLocal(scan: ScanSession) {
        cancel(scan: scan)
        selectedPeerID = nil
        scan.computeStatusRaw = ScanComputeStatus.queued.rawValue
        saveContext()
    }

    func expireTimedOutJobs(now: Date = Date()) {
        for record in jobs where !record.state.isTerminal {
            guard let deadline = record.responseDeadline, deadline <= now else { continue }
            fail("Mac handoff timed out while \(record.state.rawValue).", jobID: record.id)
            updateScanStatus(scanID: record.scanID, status: .failed)
            pendingOutboundJobs.removeValue(forKey: record.id)
        }
    }

    private func reconcileAuthenticatedPeerIDs(_ peerIDs: Set<HandoffInstallationID>) {
        authenticatedPeerIDs = peerIDs
        requestRemoteStatuses()
    }

    private func requestRemoteStatuses() {
        for record in jobs where !record.state.isTerminal {
            guard let peerID = record.peerInstallationID,
                  authenticatedPeerIDs.contains(peerID) else { continue }
            _ = transport.send(
                HandoffMessageEnvelope(
                    jobID: record.id,
                    scanID: record.scanID,
                    senderInstallationID: transport.localInstallationID,
                    payload: .statusRequest
                ),
                to: peerID
            )
        }
    }

    private func reconcileConnectedPeers(_ peers: [HandoffPeer]) {
        connectedPeers = peers
        let connectedIDs = Set(peers.map(\.installationID))
        for var record in jobs where !record.state.isTerminal {
            guard let peerID = record.peerInstallationID,
                  !connectedIDs.contains(peerID),
                  [.offered, .accepted, .sending, .processing, .returning].contains(record.state) else { continue }
            try? record.transition(to: .interrupted, error: "The Mac disconnected.")
            pendingOutboundJobs.removeValue(forKey: record.id)
            clearResultState(for: peerID)
            upsert(record)
            updateScanStatus(scanID: record.scanID, status: .queued)
        }
    }

    private func handleControlEvent(_ event: HandoffControlEvent) {
        guard pairing.isAuthenticated(event.peerID),
              let jobID = event.message.jobID,
              var record = jobs.first(where: { $0.id == jobID }),
              record.peerInstallationID == event.peerID,
              event.message.scanID == record.scanID else { return }
        switch event.message.payload {
        case .jobAccepted:
            guard record.state == .offered, let outbound = pendingOutboundJobs[jobID] else { return }
            do {
                try record.transition(to: .accepted)
                record.responseDeadline = Date().addingTimeInterval(processingTimeout)
                try record.transition(to: .sending)
                upsert(record)
                guard transport.sendScan(
                    outbound.packageURL,
                    to: event.peerID,
                    metadata: outbound.metadata
                ) else {
                    fail("The accepted scan resource could not be sent.", jobID: jobID)
                    updateScanStatus(scanID: record.scanID, status: .failed)
                    return
                }
            } catch {
                fail(error.localizedDescription, jobID: jobID)
            }
        case .progress(let progress):
            if record.state == .sending { try? record.transition(to: .processing) }
            guard record.state == .processing else { return }
            record.progress = min(max(progress, 0), 1)
            record.updatedAt = Date()
            record.responseDeadline = Date().addingTimeInterval(processingTimeout)
            upsert(record)
        case .resultReady(let descriptor):
            if record.state == .sending { try? record.transition(to: .processing) }
            if record.state == .processing { try? record.transition(to: .returning) }
            guard record.state == .returning else { return }
            record.responseDeadline = Date().addingTimeInterval(offerTimeout)
            expectedResults[jobID] = ExpectedResult(
                jobID: jobID,
                scanID: record.scanID,
                peerID: event.peerID,
                descriptor: descriptor
            )
            upsert(record)
            if let early = earlyResultResources.removeValue(forKey: jobID) {
                receiveResultPackage(
                    early.0,
                    from: early.1,
                    metadata: ScanHandoffMetadata(jobID: jobID, scanID: record.scanID)
                )
            }
        case .failed(let failure):
            fail(failure.detail, jobID: jobID)
            updateScanStatus(scanID: record.scanID, status: .failed)
        case .cancelled:
            try? record.transition(to: .cancelled)
            pendingOutboundJobs.removeValue(forKey: jobID)
            clearResultState(forJob: jobID)
            upsert(record)
            updateScanStatus(scanID: record.scanID, status: .queued)
        case .statusResponse(let status):
            reconcile(record: &record, with: status)
            upsert(record)
            if status.state == .failed {
                updateScanStatus(scanID: record.scanID, status: .failed)
            } else if status.state == .cancelled {
                updateScanStatus(scanID: record.scanID, status: .queued)
            }
        default:
            break
        }
    }

    private func reconcile(record: inout HandoffJobRecord, with status: HandoffJobStatus) {
        if record.state == .interrupted {
            switch status.state {
            case .accepted:
                try? record.transition(
                    to: .failed,
                    error: "The accepted upload was interrupted before its resource could be restored."
                )
            case .sending:
                try? record.transition(to: .sending)
            case .processing:
                try? record.transition(to: .sending)
                try? record.transition(to: .processing)
            case .returning, .completed:
                try? record.transition(to: .sending)
                try? record.transition(to: .processing)
                try? record.transition(to: .returning)
            case .failed:
                try? record.transition(to: .failed, error: "The Mac reported that reconstruction failed.")
            case .cancelled:
                try? record.transition(to: .cancelled)
            default:
                break
            }
        }
        record.progress = status.progress
        record.updatedAt = Date()
        if !record.state.isTerminal {
            record.responseDeadline = Date().addingTimeInterval(processingTimeout)
        }
    }

    private func receiveResultPackage(
        _ packageURL: URL,
        from peer: MCPeerID,
        metadata: ScanHandoffMetadata
    ) {
        guard let peerID = transport.installationID(for: peer), pairing.isAuthenticated(peerID) else {
            transport.removeReceivedResource(packageURL)
            lastErrorMessage = "Rejected an unauthenticated result package from \(peer.displayName)."
            return
        }
        let activeJobs = jobs.filter {
            $0.peerInstallationID == peerID && !$0.state.isTerminal
                && [.sending, .processing, .returning, .interrupted].contains($0.state)
        }
        let jobID = metadata.jobID ?? (activeJobs.count == 1 ? activeJobs[0].id : nil)
        guard let jobID,
              let job = jobs.first(where: { $0.id == jobID }),
              !job.state.isTerminal,
              job.peerInstallationID == peerID,
              metadata.scanID == nil || metadata.scanID == job.scanID else {
            transport.removeReceivedResource(packageURL)
            lastErrorMessage = "Rejected an unsolicited result package from \(peer.displayName)."
            return
        }
        guard let expected = expectedResults[jobID] else {
            guard !job.state.isTerminal, earlyResultResources[jobID] == nil else {
                transport.removeReceivedResource(packageURL)
                lastErrorMessage = "Rejected an unsolicited result package from \(peer.displayName)."
                return
            }
            // Multipeer control and resource callbacks are separate channels. Hold one bounded early
            // resource per job until its authenticated resultReady descriptor arrives.
            earlyResultResources[jobID] = (packageURL, peer)
            return
        }
        guard expected.peerID == peerID, expected.scanID == job.scanID else {
            transport.removeReceivedResource(packageURL)
            fail("The returned result identity did not match its job.", jobID: jobID)
            return
        }
        guard (try? HandoffResourceDescriptor.inspect(packageURL)) == expected.descriptor else {
            transport.removeReceivedResource(packageURL)
            fail("The returned result failed its size or SHA-256 check.", jobID: expected.jobID)
            return
        }
        guard modelContext != nil else {
            if !pendingResults.contains(where: { $0.packageURL == packageURL }) {
                pendingResults.append(PendingResult(packageURL: packageURL, expected: expected))
            }
            return
        }
        importResultPackage(packageURL, expected: expected)
    }

    private func importResultPackage(_ packageURL: URL, expected: ExpectedResult) {
        guard let modelContext else {
            if !pendingResults.contains(where: { $0.packageURL == packageURL }) {
                pendingResults.append(PendingResult(packageURL: packageURL, expected: expected))
            }
            return
        }
        defer { transport.removeReceivedResource(packageURL) }

        let fileManager = FileManager.default
        let importDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("3dseen-result-import-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: importDirectory, withIntermediateDirectories: true)
            defer { try? fileManager.removeItem(at: importDirectory) }
            let result = try ScanResultPackage().unpack(packageURL, to: importDirectory)
            guard result.manifest.scanID == expected.scanID else {
                throw ScanAssetStore.StoreError.manifestIdentityMismatch(
                    expected: expected.scanID,
                    actual: result.manifest.scanID
                )
            }
            let scanID = expected.scanID
            let descriptor = FetchDescriptor<ScanSession>(predicate: #Predicate { $0.id == scanID })
            guard let scan = try modelContext.fetch(descriptor).first else {
                throw CocoaError(.fileReadUnknown)
            }

            let store = try ScanAssetStore(rootDirectory: assetStoreRootDirectory)
            let priorManifest = try store.manifest(for: scan)
            let revision = try store.beginRevision(for: scan.id)
            do {
                let modelURL = try revision.stage(file: result.modelURL, named: result.modelURL.lastPathComponent)
                let previewURL = try result.previewPLYURL.map {
                    try revision.stage(file: $0, named: $0.lastPathComponent)
                }
                scan.markComputed(
                    modelURL: modelURL,
                    usdzURL: modelURL.pathExtension.lowercased() == "usdz" ? modelURL : nil,
                    previewPLYURL: previewURL,
                    previewPLYKind: result.manifest.previewPLYKind
                )
                scan.usdzFileURL = modelURL.pathExtension.lowercased() == "usdz" ? modelURL : nil
                scan.previewPLYURL = previewURL
                scan.captureModeRaw = result.manifest.captureMode.rawValue
                scan.tierRaw = result.manifest.detailTier
                scan.frameCount = max(scan.frameCount, result.manifest.frameCount)
                scan.coveragePercent = max(scan.coveragePercent, result.manifest.coveragePercent)
                scan.weakSpotCount = result.manifest.weakSpotCount
                if let report = result.manifest.captureQualityReport { scan.captureQualityReport = report }
                scan.triangles = ModelGeometryInspector.inspect(modelURL: modelURL)?.formattedTriangleCount
                    ?? "Unavailable"
                _ = try revision.stage(
                    data: store.encodedManifest(try store.manifest(for: scan)),
                    named: "manifest.json"
                )
                try revision.commit()
                try persistContext(modelContext)
                try revision.finalize()

                completeJob(jobID: expected.jobID, scanID: scan.id)
                lastErrorMessage = nil
                lastCompletion = HandoffCompletion(scanID: scan.id, modelURL: modelURL)
            } catch {
                modelContext.rollback()
                scan.apply(manifest: priorManifest)
                try? revision.rollback()
                throw error
            }
        } catch {
            fail("The returned Mac result could not be imported. \(error.localizedDescription)", jobID: expected.jobID)
            updateScanStatus(scanID: expected.scanID, status: .failed)
        }
    }

    private func handleSendFailure(_ error: Error) {
        guard let record = jobs.first(where: { $0.state == .sending }) else {
            lastErrorMessage = "Mac handoff failed: \(error.localizedDescription)"
            return
        }
        fail("Mac handoff failed: \(error.localizedDescription)", jobID: record.id)
        updateScanStatus(scanID: record.scanID, status: .failed)
    }

    private func completeJob(jobID: UUID, scanID: UUID) {
        guard var record = jobs.first(where: { $0.id == jobID && $0.scanID == scanID && !$0.state.isTerminal }) else {
            return
        }
        if record.state == .sending { try? record.transition(to: .processing) }
        if record.state == .processing { try? record.transition(to: .returning) }
        try? record.transition(to: .completed)
        pendingOutboundJobs.removeValue(forKey: record.id)
        clearResultState(forJob: record.id)
        upsert(record)
    }

    private func fail(_ message: String, scan: ScanSession? = nil, jobID: UUID? = nil) {
        lastErrorMessage = message
        if let scan {
            scan.computeStatusRaw = ScanComputeStatus.failed.rawValue
            saveContext()
        }
        guard let jobID, var record = jobs.first(where: { $0.id == jobID }) else { return }
        try? record.transition(to: .failed, error: message)
        pendingOutboundJobs.removeValue(forKey: jobID)
        clearResultState(forJob: record.id)
        upsert(record)
    }

    private static func defaultJournalURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("3DSeen", isDirectory: true)
            .appendingPathComponent("Handoff", isDirectory: true)
            .appendingPathComponent("jobs-v2.json")
    }
}

private extension IOSHandoffCoordinator {
    func clearResultState(forJob jobID: UUID) {
        expectedResults.removeValue(forKey: jobID)
        if let early = earlyResultResources.removeValue(forKey: jobID) {
            transport.removeReceivedResource(early.0)
        }
        let stale = pendingResults.filter { $0.expected.jobID == jobID }
        pendingResults.removeAll { $0.expected.jobID == jobID }
        for result in stale { transport.removeReceivedResource(result.packageURL) }
    }

    func clearResultState(for peerID: HandoffInstallationID) {
        let jobIDs = Set(jobs.filter { $0.peerInstallationID == peerID }.map(\.id))
        for jobID in jobIDs {
            expectedResults.removeValue(forKey: jobID)
            if let early = earlyResultResources.removeValue(forKey: jobID) {
                transport.removeReceivedResource(early.0)
            }
        }
        let stale = pendingResults.filter { jobIDs.contains($0.expected.jobID) }
        pendingResults.removeAll { jobIDs.contains($0.expected.jobID) }
        for result in stale { transport.removeReceivedResource(result.packageURL) }
    }

    func upsert(_ record: HandoffJobRecord) {
        if let index = jobs.firstIndex(where: { $0.id == record.id }) {
            jobs[index] = record
        } else {
            jobs.append(record)
        }
        jobs.sort { $0.updatedAt > $1.updatedAt }

        let previousWrite = journalWriteTask
        journalWriteTask = Task { [journal] in
            _ = await previousWrite?.result
            do {
                try await journal.upsert(record)
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.lastErrorMessage = "Could not persist the handoff job. \(error.localizedDescription)"
                }
            }
        }
    }

    func reconcileScanStatuses() {
        for job in jobs where job.state == .interrupted {
            updateScanStatus(scanID: job.scanID, status: .queued)
        }
    }

    func updateScanStatus(scanID: UUID, status: ScanComputeStatus) {
        guard let modelContext else { return }
        let descriptor = FetchDescriptor<ScanSession>(predicate: #Predicate { $0.id == scanID })
        guard let scan = try? modelContext.fetch(descriptor).first else { return }
        scan.computeStatusRaw = status.rawValue
        saveContext()
    }

    func saveContext() {
        try? modelContext?.save()
    }
}
