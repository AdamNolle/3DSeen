import Combine
import MultipeerConnectivity
import SwiftData
import XCTest
@testable import ThreeDSeen

final class HandoffProtocolTests: XCTestCase {
    func testJobTransitionsFollowTheDurablePipeline() throws {
        var job = HandoffJobRecord(
            scanID: UUID(),
            captureMode: .object,
            detailTier: "Full"
        )

        try job.transition(to: .sending)
        try job.transition(to: .processing)
        try job.transition(to: .returning)
        try job.transition(to: .completed)

        XCTAssertEqual(job.state, .completed)
        XCTAssertEqual(job.attemptCount, 1)
        XCTAssertEqual(job.progress, 1)
        XCTAssertTrue(job.state.isTerminal)
    }

    func testInstallationIdentityPersistsWithoutUsingDisplayName() {
        let suiteName = "HandoffInstallationIdentityTests-\(UUID())"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = HandoffInstallationIdentityStore(defaults: defaults)

        let first = store.loadOrCreate()
        let second = HandoffInstallationIdentityStore(defaults: defaults).loadOrCreate()

        XCTAssertEqual(first, second)
    }

    func testTypedControlMessagesRoundTripAndValidateVersion() throws {
        let sender = HandoffInstallationID(rawValue: UUID())
        let peer = HandoffPeer(
            installationID: sender,
            displayName: "Render Mac",
            platform: .macOS,
            capabilities: [.photogrammetry, .trainedSplat],
            connectionState: .authenticated
        )
        let descriptor = HandoffResourceDescriptor(byteCount: 4_096, sha256: String(repeating: "a", count: 64))
        let payloads: [HandoffMessagePayload] = [
            .hello(peer),
            .authenticationChallenge(Data("nonce".utf8)),
            .authenticationResponse(Data("hmac".utf8)),
            .jobOffer(HandoffJobOffer(captureMode: .landscape, detailTier: "Full", resource: descriptor)),
            .jobAccepted,
            .progress(0.5),
            .resultReady(descriptor),
            .failed(HandoffFailure(code: .reconstructionFailed, detail: "No geometry")),
            .cancel,
            .cancelled,
            .statusRequest,
            .statusResponse(HandoffJobStatus(state: .processing, progress: 0.75)),
            .protocolRejected(minimum: 1, maximum: 2),
        ]

        for payload in payloads {
            let envelope = HandoffMessageEnvelope(
                jobID: UUID(),
                scanID: UUID(),
                senderInstallationID: sender,
                payload: payload
            )
            let decoded = try JSONDecoder().decode(
                HandoffMessageEnvelope.self,
                from: JSONEncoder().encode(envelope)
            )
            XCTAssertEqual(decoded, envelope)
            XCTAssertNoThrow(try decoded.validateVersion())
        }

        let rejected = HandoffMessageEnvelope(
            protocolVersion: 99,
            senderInstallationID: sender,
            payload: .statusRequest
        )
        XCTAssertThrowsError(try rejected.validateVersion())
    }

    func testJobRejectsImpossibleTransition() {
        var job = HandoffJobRecord(
            scanID: UUID(),
            captureMode: .space,
            detailTier: "RoomPlan"
        )

        XCTAssertThrowsError(try job.transition(to: .completed)) { error in
            XCTAssertEqual(
                error as? HandoffJobError,
                .invalidTransition(from: .queued, to: .completed)
            )
        }
    }

    @MainActor
    func testInvitationRequiresExplicitUserResponse() async throws {
        let manager = NetworkHandoffManager()
        let remotePeerID = MCPeerID(displayName: "Render Mac")
        let remotePeer = HandoffPeer(
            installationID: HandoffInstallationID(),
            displayName: remotePeerID.displayName,
            platform: .macOS,
            capabilities: [.photogrammetry]
        )
        let advertiser = MCNearbyServiceAdvertiser(
            peer: MCPeerID(displayName: "Test iPhone"),
            discoveryInfo: nil,
            serviceType: "3dseen"
        )
        var response: Bool?

        manager.advertiser(
            advertiser,
            didReceiveInvitationFromPeer: remotePeerID,
            withContext: try JSONEncoder().encode(remotePeer)
        ) { accepted, _ in
            response = accepted
        }
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertNil(response)
        XCTAssertEqual(manager.pendingInvitations.first?.peer.installationID, remotePeer.installationID)
        let invitation = try XCTUnwrap(manager.pendingInvitations.first)
        manager.respond(to: invitation.id, accept: false)
        XCTAssertEqual(response, false)
        XCTAssertTrue(manager.pendingInvitations.isEmpty)
    }

    @MainActor
    func testControlDispatchCorrelatesSenderAndDeduplicatesMessageID() async throws {
        let manager = NetworkHandoffManager()
        let remotePeerID = MCPeerID(displayName: "Render Mac")
        let remotePeer = HandoffPeer(
            installationID: HandoffInstallationID(),
            displayName: remotePeerID.displayName,
            platform: .macOS,
            capabilities: [.photogrammetry]
        )
        let advertiser = MCNearbyServiceAdvertiser(
            peer: MCPeerID(displayName: "Test iPhone"),
            discoveryInfo: nil,
            serviceType: "3dseen"
        )
        manager.advertiser(
            advertiser,
            didReceiveInvitationFromPeer: remotePeerID,
            withContext: try JSONEncoder().encode(remotePeer)
        ) { _, _ in }
        try await Task.sleep(for: .milliseconds(50))
        let message = HandoffMessageEnvelope(
            senderInstallationID: remotePeer.installationID,
            payload: .statusRequest
        )
        let data = try JSONEncoder().encode(message)
        var events: [HandoffControlEvent] = []
        let cancellable = manager.controlEventsPublisher.sink { events.append($0) }

        manager.session(MCSession(peer: MCPeerID(displayName: "Receiver")), didReceive: data, fromPeer: remotePeerID)
        manager.session(MCSession(peer: MCPeerID(displayName: "Receiver")), didReceive: data, fromPeer: remotePeerID)
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(events, [HandoffControlEvent(message: message, peerID: remotePeer.installationID)])
        withExtendedLifetime(cancellable) {}
    }

    @MainActor
    func testAppCoordinatorOwnsPackagingAndTransportSend() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("handoff-coordinator-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let capture = root.appendingPathComponent("capture", isDirectory: true)
        try FileManager.default.createDirectory(at: capture, withIntermediateDirectories: true)
        try Data("frame".utf8).write(to: capture.appendingPathComponent("frame.jpg"))

        let transport = FakeHandoffTransport(connectedName: "Render Mac")
        let remoteID = transport.connectedHandoffPeers[0].installationID
        let secret = Data(repeating: 4, count: 32)
        let credentials = InMemoryPairingCredentialStore()
        try credentials.store(secret: secret, for: remoteID)
        let coordinator = IOSHandoffCoordinator(
            transport: transport,
            journal: HandoffJobJournal(fileURL: root.appendingPathComponent("jobs.json")),
            credentialStore: credentials
        )
        try await Task.sleep(for: .milliseconds(50))
        let localChallenge = try XCTUnwrap(transport.sentMessages.compactMap { message -> Data? in
            guard case .authenticationChallenge(let challenge) = message.payload else { return nil }
            return challenge
        }.first)
        transport.deliver(
            HandoffMessageEnvelope(
                senderInstallationID: remoteID,
                payload: .authenticationResponse(HandoffAuthenticator.authenticationResponse(
                    secret: secret,
                    challenge: localChallenge,
                    responderID: remoteID
                ))
            ),
            from: remoteID
        )
        try await Task.sleep(for: .milliseconds(50))
        coordinator.selectPeer(remoteID)
        let scan = ScanSession(
            captureMode: .object,
            tier: "Full",
            rawArchiveURL: capture,
            captureStatus: .captured
        )

        XCTAssertTrue(coordinator.startOffload(scan: scan))
        let job = try XCTUnwrap(coordinator.jobs.first)
        XCTAssertEqual(job.state, .offered)
        XCTAssertTrue(transport.sentMessages.contains { message in
            message.jobID == job.id && message.scanID == scan.id && {
                if case .jobOffer = message.payload { return true }
                return false
            }()
        })
        transport.deliver(
            HandoffMessageEnvelope(
                jobID: job.id,
                scanID: scan.id,
                senderInstallationID: remoteID,
                payload: .jobAccepted
            ),
            from: remoteID
        )
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(transport.sentMetadata?.scanID, scan.id)
        XCTAssertEqual(transport.sentMetadata?.detailTier, "Full")
        XCTAssertEqual(transport.sendCount, 1)
        XCTAssertEqual(coordinator.jobs.first?.state, .sending)
        XCTAssertEqual(scan.computeStatus, .offloaded)
    }

    @MainActor
    func testCoordinatorRejectsSelectedPeerUntilAuthenticated() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("handoff-untrusted-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let capture = root.appendingPathComponent("capture", isDirectory: true)
        try FileManager.default.createDirectory(at: capture, withIntermediateDirectories: true)
        try Data("frame".utf8).write(to: capture.appendingPathComponent("frame.jpg"))
        let transport = FakeHandoffTransport(connectedName: "Untrusted Mac")
        let coordinator = IOSHandoffCoordinator(
            transport: transport,
            journal: HandoffJobJournal(fileURL: root.appendingPathComponent("jobs.json")),
            credentialStore: InMemoryPairingCredentialStore()
        )
        coordinator.selectPeer(transport.connectedHandoffPeers[0].installationID)
        let scan = ScanSession(
            captureMode: .object,
            rawArchiveURL: capture,
            captureStatus: .packaged,
            computeStatus: .queued
        )

        XCTAssertFalse(coordinator.startOffload(scan: scan))
        XCTAssertEqual(transport.sendCount, 0)
        XCTAssertEqual(scan.computeStatus, .failed)
        XCTAssertTrue(coordinator.lastErrorMessage?.contains("six-digit") == true)
    }

    @MainActor
    func testCoordinatorRejectsResultResourceFromUnauthenticatedPeer() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("handoff-untrusted-result-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let package = root.appendingPathComponent("result.zip")
        try Data("untrusted".utf8).write(to: package)
        let transport = FakeHandoffTransport(connectedName: "Untrusted Mac")
        let coordinator = IOSHandoffCoordinator(
            transport: transport,
            journal: HandoffJobJournal(fileURL: root.appendingPathComponent("jobs.json")),
            credentialStore: InMemoryPairingCredentialStore()
        )

        transport.onReceiveResultPackage?(package, MCPeerID(displayName: "Untrusted Mac"), .init())

        XCTAssertFalse(FileManager.default.fileExists(atPath: package.path))
        XCTAssertTrue(coordinator.lastErrorMessage?.contains("unauthenticated") == true)
    }

    @MainActor
    func testCoordinatorRejectsAuthenticatedResultWithoutAnActiveCorrelatedJob() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("handoff-unsolicited-result-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let package = root.appendingPathComponent("unsolicited.3dseen-result.zip")
        try Data("unsolicited".utf8).write(to: package)
        let transport = FakeHandoffTransport(connectedName: "Trusted Mac")
        let remoteID = transport.connectedHandoffPeers[0].installationID
        let secret = Data(repeating: 5, count: 32)
        let credentials = InMemoryPairingCredentialStore()
        try credentials.store(secret: secret, for: remoteID)
        let coordinator = IOSHandoffCoordinator(
            transport: transport,
            journal: HandoffJobJournal(fileURL: root.appendingPathComponent("jobs.json")),
            credentialStore: credentials
        )
        try await authenticate(coordinator: coordinator, transport: transport, remoteID: remoteID, secret: secret)

        transport.onReceiveResultPackage?(package, MCPeerID(displayName: "Trusted Mac"), .init())

        XCTAssertFalse(FileManager.default.fileExists(atPath: package.path))
        XCTAssertTrue(coordinator.lastErrorMessage?.contains("unsolicited") == true)
    }

    @MainActor
    func testAuthenticatedResultWaitsForDescriptorThenImportsCorrelatedScan() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("handoff-correlated-result-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let capture = root.appendingPathComponent("capture", isDirectory: true)
        try FileManager.default.createDirectory(at: capture, withIntermediateDirectories: true)
        try Data("frame".utf8).write(to: capture.appendingPathComponent("frame.jpg"))
        let transport = FakeHandoffTransport(connectedName: "Result Mac")
        let remoteID = transport.connectedHandoffPeers[0].installationID
        let secret = Data(repeating: 6, count: 32)
        let credentials = InMemoryPairingCredentialStore()
        try credentials.store(secret: secret, for: remoteID)
        let storeRoot = root.appendingPathComponent("scans", isDirectory: true)
        let coordinator = IOSHandoffCoordinator(
            transport: transport,
            journal: HandoffJobJournal(fileURL: root.appendingPathComponent("jobs.json")),
            credentialStore: credentials,
            assetStoreRootDirectory: storeRoot
        )
        let container = try ModelContainer(
            for: ScanSession.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let scan = ScanSession(
            captureMode: .object,
            tier: "Medium",
            rawArchiveURL: capture,
            captureStatus: .packaged,
            computeStatus: .queued
        )
        context.insert(scan)
        try context.save()
        coordinator.attach(modelContext: context)
        try await authenticate(coordinator: coordinator, transport: transport, remoteID: remoteID, secret: secret)
        coordinator.selectPeer(remoteID)
        XCTAssertTrue(coordinator.startOffload(scan: scan))
        var job = try XCTUnwrap(coordinator.jobs.first)
        transport.deliver(control(.jobAccepted, job: job, sender: remoteID), from: remoteID)
        try await Task.sleep(for: .milliseconds(30))

        let model = root.appendingPathComponent("model.obj")
        try Data("v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n".utf8).write(to: model)
        let wrongManifest = ScanAssetManifest(
            scanID: UUID(),
            captureMode: .object,
            detailTier: "Medium",
            sourceModelURL: model
        )
        let wrongPackage = try ScanResultPackage().write(output: model, manifest: wrongManifest)
        let wrongDescriptor = try HandoffResourceDescriptor.inspect(wrongPackage)
        transport.deliver(control(.resultReady(wrongDescriptor), job: job, sender: remoteID), from: remoteID)
        transport.onReceiveResultPackage?(
            wrongPackage,
            MCPeerID(displayName: "Result Mac"),
            .init(jobID: job.id, scanID: scan.id)
        )
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(coordinator.jobs.first(where: { $0.id == job.id })?.state, .failed)
        XCTAssertNil(scan.sourceModelURL)

        XCTAssertTrue(coordinator.retry(scan: scan))
        job = try XCTUnwrap(coordinator.jobs.first)
        transport.deliver(control(.jobAccepted, job: job, sender: remoteID), from: remoteID)
        try await Task.sleep(for: .milliseconds(30))
        let manifest = ScanAssetManifest(
            scanID: scan.id,
            captureMode: .object,
            detailTier: "Medium",
            sourceModelURL: model,
            frameCount: 1
        )
        let package = try ScanResultPackage().write(output: model, manifest: manifest)
        let expected = try HandoffResourceDescriptor.inspect(package)
        transport.onReceiveResultPackage?(
            package,
            MCPeerID(displayName: "Result Mac"),
            .init(jobID: job.id, scanID: scan.id)
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: package.path))
        XCTAssertNil(coordinator.lastCompletion)
        transport.deliver(control(.resultReady(expected), job: job, sender: remoteID), from: remoteID)
        try await Task.sleep(for: .milliseconds(50))

        let retained = try XCTUnwrap(scan.sourceModelURL)
        XCTAssertEqual(try Data(contentsOf: retained), try Data(contentsOf: model))
        XCTAssertEqual(scan.computeStatus, .completed)
        XCTAssertEqual(coordinator.lastCompletion?.scanID, scan.id)
        XCTAssertEqual(coordinator.jobs.first(where: { $0.id == job.id })?.state, .completed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: package.path))
    }

    @MainActor
    func testResultImportSaveFailureRestoresPriorAssetsAndManifest() async throws {
        enum SaveFailure: Error { case injected }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("handoff-result-rollback-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let capture = root.appendingPathComponent("capture", isDirectory: true)
        try FileManager.default.createDirectory(at: capture, withIntermediateDirectories: true)
        try Data("frame".utf8).write(to: capture.appendingPathComponent("frame.jpg"))
        let store = try ScanAssetStore(rootDirectory: root.appendingPathComponent("scans", isDirectory: true))
        let scanID = UUID()
        let scanDirectory = try store.directory(for: scanID)
        let oldModel = scanDirectory.appendingPathComponent("model.obj")
        let oldBytes = Data("v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n# old\n".utf8)
        try oldBytes.write(to: oldModel)
        let scan = ScanSession(
            id: scanID,
            captureMode: .object,
            tier: "Medium",
            rawArchiveURL: capture,
            sourceModelURL: oldModel,
            captureStatus: .packaged,
            computeStatus: .queued
        )
        try store.writeManifest(try store.manifest(for: scan))
        let transport = FakeHandoffTransport(connectedName: "Rollback Mac")
        let remoteID = transport.connectedHandoffPeers[0].installationID
        let secret = Data(repeating: 7, count: 32)
        let credentials = InMemoryPairingCredentialStore()
        try credentials.store(secret: secret, for: remoteID)
        let coordinator = IOSHandoffCoordinator(
            transport: transport,
            journal: HandoffJobJournal(fileURL: root.appendingPathComponent("jobs.json")),
            credentialStore: credentials,
            assetStoreRootDirectory: store.rootDirectory,
            persistContext: { _ in throw SaveFailure.injected }
        )
        let container = try ModelContainer(
            for: ScanSession.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        context.insert(scan)
        try context.save()
        coordinator.attach(modelContext: context)
        try await authenticate(coordinator: coordinator, transport: transport, remoteID: remoteID, secret: secret)
        coordinator.selectPeer(remoteID)
        XCTAssertTrue(coordinator.startOffload(scan: scan))
        let job = try XCTUnwrap(coordinator.jobs.first)
        transport.deliver(control(.jobAccepted, job: job, sender: remoteID), from: remoteID)
        try await Task.sleep(for: .milliseconds(30))

        let replacement = root.appendingPathComponent("replacement.obj")
        try Data("v 0 0 0\nv 2 0 0\nv 0 2 0\nf 1 2 3\n".utf8).write(to: replacement)
        let manifest = ScanAssetManifest(
            scanID: scan.id,
            captureMode: .object,
            detailTier: "Full",
            sourceModelURL: replacement
        )
        let package = try ScanResultPackage().write(output: replacement, manifest: manifest)
        let expected = try HandoffResourceDescriptor.inspect(package)
        transport.deliver(control(.resultReady(expected), job: job, sender: remoteID), from: remoteID)
        transport.onReceiveResultPackage?(
            package,
            MCPeerID(displayName: "Rollback Mac"),
            .init(jobID: job.id, scanID: scan.id)
        )
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(try Data(contentsOf: oldModel), oldBytes)
        XCTAssertEqual(scan.sourceModelURL, oldModel)
        XCTAssertEqual(try store.loadManifest(for: scan.id).sourceModelURL, oldModel)
        XCTAssertEqual(coordinator.jobs.first(where: { $0.id == job.id })?.state, .failed)
        XCTAssertNil(coordinator.lastCompletion)
    }

    @MainActor
    func testTypedFailureTimeoutCancelDisconnectAndResultDigestRecovery() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("handoff-recovery-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let capture = root.appendingPathComponent("capture", isDirectory: true)
        try FileManager.default.createDirectory(at: capture, withIntermediateDirectories: true)
        try Data("frame".utf8).write(to: capture.appendingPathComponent("frame.jpg"))
        let transport = FakeHandoffTransport(connectedName: "Render Mac")
        let remoteID = transport.connectedHandoffPeers[0].installationID
        let secret = Data(repeating: 8, count: 32)
        let credentials = InMemoryPairingCredentialStore()
        try credentials.store(secret: secret, for: remoteID)
        let coordinator = IOSHandoffCoordinator(
            transport: transport,
            journal: HandoffJobJournal(fileURL: root.appendingPathComponent("jobs.json")),
            credentialStore: credentials,
            offerTimeout: 0.01,
            processingTimeout: 60
        )
        try await authenticate(coordinator: coordinator, transport: transport, remoteID: remoteID, secret: secret)
        coordinator.selectPeer(remoteID)
        let scan = ScanSession(
            captureMode: .object,
            tier: "Medium",
            rawArchiveURL: capture,
            captureStatus: .packaged,
            computeStatus: .queued
        )

        XCTAssertTrue(coordinator.startOffload(scan: scan))
        let firstJob = try XCTUnwrap(coordinator.jobs.first)
        transport.deliver(control(.jobAccepted, job: firstJob, sender: remoteID), from: remoteID)
        transport.deliver(control(.progress(0.4), job: firstJob, sender: remoteID), from: remoteID)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(coordinator.jobs.first(where: { $0.id == firstJob.id })?.state, .processing)
        XCTAssertEqual(coordinator.jobs.first(where: { $0.id == firstJob.id })?.progress, 0.4)

        let expectedFile = root.appendingPathComponent("expected.zip")
        try Data("expected".utf8).write(to: expectedFile)
        let expected = try HandoffResourceDescriptor.inspect(expectedFile)
        transport.deliver(control(.resultReady(expected), job: firstJob, sender: remoteID), from: remoteID)
        try await Task.sleep(for: .milliseconds(30))
        let corruptResult = root.appendingPathComponent("corrupt.3dseen-result.zip")
        try Data("corrupt".utf8).write(to: corruptResult)
        transport.onReceiveResultPackage?(
            corruptResult,
            MCPeerID(displayName: "Render Mac"),
            .init(jobID: firstJob.id, scanID: scan.id)
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: corruptResult.path))
        XCTAssertEqual(coordinator.jobs.first(where: { $0.id == firstJob.id })?.state, .failed)

        XCTAssertTrue(coordinator.retry(scan: scan))
        let timedJob = try XCTUnwrap(coordinator.jobs.first)
        coordinator.expireTimedOutJobs(now: .distantFuture)
        XCTAssertEqual(coordinator.jobs.first(where: { $0.id == timedJob.id })?.state, .failed)

        XCTAssertTrue(coordinator.retry(scan: scan))
        let cancelledJob = try XCTUnwrap(coordinator.jobs.first)
        transport.deliver(control(.jobAccepted, job: cancelledJob, sender: remoteID), from: remoteID)
        try await Task.sleep(for: .milliseconds(20))
        let lateResult = root.appendingPathComponent("late.3dseen-result.zip")
        try Data("late-result".utf8).write(to: lateResult)
        let lateDescriptor = try HandoffResourceDescriptor.inspect(lateResult)
        transport.deliver(control(.resultReady(lateDescriptor), job: cancelledJob, sender: remoteID), from: remoteID)
        try await Task.sleep(for: .milliseconds(20))
        coordinator.fallbackToLocal(scan: scan)
        transport.onReceiveResultPackage?(
            lateResult,
            MCPeerID(displayName: "Render Mac"),
            .init(jobID: cancelledJob.id, scanID: scan.id)
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: lateResult.path))
        XCTAssertEqual(coordinator.jobs.first(where: { $0.id == cancelledJob.id })?.state, .cancelled)
        XCTAssertEqual(scan.computeStatus, .queued)
        XCTAssertTrue(transport.sentMessages.contains { $0.jobID == cancelledJob.id && $0.payload == .cancel })

        coordinator.selectPeer(remoteID)
        XCTAssertTrue(coordinator.retry(scan: scan))
        let disconnectedJob = try XCTUnwrap(coordinator.jobs.first)
        transport.deliver(control(.jobAccepted, job: disconnectedJob, sender: remoteID), from: remoteID)
        try await Task.sleep(for: .milliseconds(20))
        transport.disconnect()
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(coordinator.jobs.first(where: { $0.id == disconnectedJob.id })?.state, .interrupted)
    }

    @MainActor
    func testCoordinatorRefusesImplicitFirstPeerSelection() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("handoff-selection-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let capture = root.appendingPathComponent("capture", isDirectory: true)
        try FileManager.default.createDirectory(at: capture, withIntermediateDirectories: true)
        try Data("frame".utf8).write(to: capture.appendingPathComponent("frame.jpg"))
        let transport = FakeHandoffTransport(connectedName: "Render Mac")
        let coordinator = IOSHandoffCoordinator(
            transport: transport,
            journal: HandoffJobJournal(fileURL: root.appendingPathComponent("jobs.json"))
        )
        let scan = ScanSession(
            captureMode: .object,
            rawArchiveURL: capture,
            captureStatus: .packaged,
            computeStatus: .queued
        )

        XCTAssertFalse(coordinator.startOffload(scan: scan))
        XCTAssertEqual(transport.sendCount, 0)
        XCTAssertNil(coordinator.selectedPeerID)
    }

    @MainActor
    private func authenticate(
        coordinator: IOSHandoffCoordinator,
        transport: FakeHandoffTransport,
        remoteID: HandoffInstallationID,
        secret: Data
    ) async throws {
        try await Task.sleep(for: .milliseconds(30))
        let challenge = try XCTUnwrap(transport.sentMessages.compactMap { message -> Data? in
            guard case .authenticationChallenge(let value) = message.payload else { return nil }
            return value
        }.first)
        transport.deliver(
            HandoffMessageEnvelope(
                senderInstallationID: remoteID,
                payload: .authenticationResponse(HandoffAuthenticator.authenticationResponse(
                    secret: secret,
                    challenge: challenge,
                    responderID: remoteID
                ))
            ),
            from: remoteID
        )
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertTrue(coordinator.authenticatedPeerIDs.contains(remoteID))
    }

    private func control(
        _ payload: HandoffMessagePayload,
        job: HandoffJobRecord,
        sender: HandoffInstallationID
    ) -> HandoffMessageEnvelope {
        HandoffMessageEnvelope(
            jobID: job.id,
            scanID: job.scanID,
            senderInstallationID: sender,
            payload: payload
        )
    }

}

extension HandoffProtocolTests {
    func testAutoSelectionRequiresExactlyOneAuthenticatedPeer() {
        let first = HandoffPeer(
            installationID: HandoffInstallationID(),
            displayName: "First Mac",
            platform: .macOS,
            capabilities: [.photogrammetry]
        )
        let second = HandoffPeer(
            installationID: HandoffInstallationID(),
            displayName: "Second Mac",
            platform: .macOS,
            capabilities: [.photogrammetry]
        )

        XCTAssertNil(HandoffPeerSelectionPolicy.preferredPeer(
            connectedPeers: [first],
            authenticatedPeerIDs: [first.installationID],
            autoSelect: false
        ))
        XCTAssertEqual(HandoffPeerSelectionPolicy.preferredPeer(
            connectedPeers: [first, second],
            authenticatedPeerIDs: [first.installationID],
            autoSelect: true
        ), first.installationID)
        XCTAssertNil(HandoffPeerSelectionPolicy.preferredPeer(
            connectedPeers: [first, second],
            authenticatedPeerIDs: [first.installationID, second.installationID],
            autoSelect: true
        ))
    }

    func testJournalPersistsAndMarksActiveWorkInterrupted() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("handoff-journal-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("jobs.json")
        let journal = HandoffJobJournal(fileURL: url)
        var job = HandoffJobRecord(
            scanID: UUID(),
            captureMode: .landscape,
            detailTier: "Medium"
        )
        try job.transition(to: .sending)
        try await journal.upsert(job)

        let reopened = HandoffJobJournal(fileURL: url)
        let interrupted = try await reopened.markInterruptedWork()

        XCTAssertEqual(interrupted.count, 1)
        XCTAssertEqual(interrupted.first?.state, .interrupted)
        XCTAssertNotNil(interrupted.first?.lastError)
    }
}

@MainActor
private final class FakeHandoffTransport: ScanHandoffTransport {
    let localInstallationID = HandoffInstallationID()
    var discoveredPeers: [HandoffPeer]
    var connectedHandoffPeers: [HandoffPeer]
    var pendingInvitations: [HandoffInvitation] = []
    var transferProgress: Double = 0
    var onReceiveResultPackage: ((URL, MCPeerID, ScanHandoffMetadata) -> Void)?
    var onSendError: ((Error) -> Void)?
    private let discoveredSubject: CurrentValueSubject<[HandoffPeer], Never>
    private let connectedSubject: CurrentValueSubject<[HandoffPeer], Never>
    private let invitationsSubject = CurrentValueSubject<[HandoffInvitation], Never>([])
    private let controlSubject = PassthroughSubject<HandoffControlEvent, Never>()
    private let progressSubject = CurrentValueSubject<Double, Never>(0)
    private(set) var sentMetadata: ScanHandoffMetadata?
    private(set) var sentMessages: [HandoffMessageEnvelope] = []
    private(set) var sendCount = 0

    var discoveredPeersPublisher: AnyPublisher<[HandoffPeer], Never> {
        discoveredSubject.eraseToAnyPublisher()
    }

    var connectedHandoffPeersPublisher: AnyPublisher<[HandoffPeer], Never> {
        connectedSubject.eraseToAnyPublisher()
    }

    var pendingInvitationsPublisher: AnyPublisher<[HandoffInvitation], Never> {
        invitationsSubject.eraseToAnyPublisher()
    }

    var controlEventsPublisher: AnyPublisher<HandoffControlEvent, Never> {
        controlSubject.eraseToAnyPublisher()
    }

    var transferProgressPublisher: AnyPublisher<Double, Never> {
        progressSubject.eraseToAnyPublisher()
    }

    init(connectedName: String) {
        let peer = HandoffPeer(
            installationID: HandoffInstallationID(),
            displayName: connectedName,
            platform: .macOS,
            capabilities: [.photogrammetry],
            connectionState: .connected
        )
        discoveredPeers = [peer]
        connectedHandoffPeers = [peer]
        discoveredSubject = CurrentValueSubject([peer])
        connectedSubject = CurrentValueSubject([peer])
    }

    func installationID(for peerID: MCPeerID) -> HandoffInstallationID? {
        connectedHandoffPeers.first { $0.displayName == peerID.displayName }?.installationID
    }

    func invite(peerID: HandoffInstallationID) {}
    func respond(to invitationID: UUID, accept: Bool) {}
    func send(_ message: HandoffMessageEnvelope, to peerID: HandoffInstallationID) -> Bool {
        sentMessages.append(message)
        return connectedHandoffPeers.contains { $0.installationID == peerID }
    }

    func deliver(_ message: HandoffMessageEnvelope, from peerID: HandoffInstallationID) {
        controlSubject.send(HandoffControlEvent(message: message, peerID: peerID))
    }

    func disconnect() {
        connectedHandoffPeers = []
        connectedSubject.send([])
    }

    func sendScan(
        _ fileURL: URL,
        to peerID: HandoffInstallationID,
        metadata: ScanHandoffMetadata
    ) -> Bool {
        guard connectedHandoffPeers.contains(where: { $0.installationID == peerID }),
              FileManager.default.fileExists(atPath: fileURL.path) else { return false }
        sendCount += 1
        sentMetadata = metadata
        return true
    }

    func removeReceivedResource(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
