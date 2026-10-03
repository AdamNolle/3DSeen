import ARKit
import UIKit

extension GuidedObjectCaptureController {
    func sessionWasInterrupted(_ session: ARSession) {
        lock.withLock { acceptsFrames = false }
        publish {
            $0.phase = .failed
            $0.instruction = "Scan paused because the camera was interrupted. Return here and tap Try Again."
        }
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        publish {
            $0.phase = .failed
            $0.instruction = "Camera is available again. Tap Try Again to relock the object."
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        lock.withLock { acceptsFrames = false }
        logger.error("AR session failed: \(error.localizedDescription)")
        publishFailure("Camera tracking stopped. Tap Try Again to restart without saving bad frames.")
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        let status: String
        switch camera.trackingState {
        case .normal:
            status = "tracking"
        case .limited(let reason):
            switch reason {
            case .initializing: status = "initializing"
            case .excessiveMotion: status = "move slower"
            case .insufficientFeatures: status = "need more texture or light"
            case .relocalizing: status = "relocalizing"
            @unknown default: status = "limited"
            }
        case .notAvailable:
            status = "unavailable"
        }
        publish { $0.trackingStatus = status }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let presentation = lock.withLock {
            FramePresentation(
                viewportSize: viewportSize,
                orientation: interfaceOrientation,
                acceptsFrames: acceptsFrames,
                sessionGeneration: sessionGeneration
            )
        }
        guard presentation.acceptsFrames,
              presentation.viewportSize.width > 0,
              presentation.viewportSize.height > 0
        else { return }
        let pose = CapturePose(transform: frame.camera.transform, timestamp: frame.timestamp)
        let previousPose = lock.withLock { () -> CapturePose? in
            defer { previousObservedPose = pose }
            return previousObservedPose
        }
        let trackingIsNormal: Bool
        if case .normal = frame.camera.trackingState {
            trackingIsNormal = true
        } else {
            trackingIsNormal = false
        }
        scheduleDetection(for: frame, orientation: presentation.orientation)
        let subject = lock.withLock { latestSubject }
        let surfaceMask = subject.flatMap { subject -> LiDARSurfaceMask? in
            guard subject.isFresh(at: frame.timestamp, maximumAge: 0.7) else { return nil }
            return LiDARSurfaceMask(
                labels: subject.mask.labels,
                width: subject.mask.width,
                height: subject.mask.height,
                selectedLabel: subject.mask.selectedLabel,
                orientation: subject.imageOrientation
            )
        }
        let candidate = FrameCandidate(
            frame: frame,
            pixelBuffer: frame.capturedImage,
            pose: pose,
            orientation: presentation.orientation,
            sessionGeneration: presentation.sessionGeneration,
            surfaceMask: surfaceMask,
            trackingIsNormal: trackingIsNormal,
            quality: CameraFrameQualityAnalyzer.analyze(frame.capturedImage),
            motionIsAcceptable: CameraMotionGate.isAcceptable(current: pose, previous: previousPose)
        )
        lock.withLock { latestFrame = candidate }

        let subjectProjection = subject.flatMap { subject -> SubjectImageProjection? in
            guard subject.isFresh(at: frame.timestamp, maximumAge: 0.7) else { return nil }
            return SubjectImageProjection(
                subject: subject,
                imageToViewTransform: frame.displayTransform(
                    for: presentation.orientation,
                    viewportSize: presentation.viewportSize
                ),
                viewportSize: presentation.viewportSize
            )
        }
        let pointResult = trackedPoints(
            in: frame,
            subjectProjection: subjectProjection,
            viewport: presentation.viewportSize,
            orientation: presentation.orientation
        )
        let coverageState = lock.withLock { () -> CoverageFramePublication in
            _ = surfaceCoverage.insert(pointResult.surfacePoints)
            let shouldPublish = snapshotPublicationGate.shouldPublish(at: frame.timestamp)
            let shouldPublishPoints = shouldPublish
                && surfaceCoverage.points.count != lastPublishedSurfaceCount
                && frame.timestamp - lastSurfacePublicationTime >= 0.25
            let points = shouldPublishPoints ? surfaceCoverage.points : nil
            if shouldPublishPoints {
                lastPublishedSurfaceCount = surfaceCoverage.points.count
                lastSurfacePublicationTime = frame.timestamp
            }
            return CoverageFramePublication(
                shouldPublish: shouldPublish,
                count: surfaceCoverage.points.count,
                hapticMilestone: surfaceCoverage.hapticMilestone,
                points: points
            )
        }
        if coverageState.shouldPublish {
            publish { snapshot in
                snapshot.subjectBounds = subjectProjection?.screenBounds
                snapshot.points = pointResult.points
                snapshot.pointSource = pointResult.source
                snapshot.surfacePointCount = coverageState.count
                snapshot.coverageHapticMilestone = coverageState.hapticMilestone
                if let surfacePoints = coverageState.points {
                    snapshot.surfacePoints = surfacePoints
                }
                snapshot.phase = subjectProjection == nil ? .seekingSubject : .capturing
                if !candidate.trackingIsNormal {
                    snapshot.instruction = "Hold still while camera tracking recovers."
                } else if subjectProjection == nil {
                    snapshot.instruction = "Center one object and hold still for detection."
                } else if !candidate.quality.isAcceptable {
                    snapshot.instruction = candidate.quality.meanLuminance < 0.10
                        ? "Add more even light, then keep the object centered."
                        : "Aim at a textured edge and hold the phone steady."
                } else if !candidate.motionIsAcceptable {
                    snapshot.instruction = "Move more slowly so each photo stays sharp."
                } else if snapshot.frameCount >= snapshot.recommendedFrameCount {
                    snapshot.instruction = "Photo set ready. Add top or underside views, or finish."
                } else if snapshot.frameCount < 8 {
                    snapshot.instruction = "Move slowly around the object. Photos save automatically."
                } else {
                    snapshot.instruction = "Keep circling. Capture the top and every side."
                }
            }
        }
        evaluateAndCapture(candidate, manual: false)
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        updateObjectMesh(anchors)
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        updateObjectMesh(anchors)
    }

    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        guard lock.withLock({ acceptsFrames }), !meshCaptureDisabled else { return }
        for anchor in anchors {
            surfaceMeshes[anchor.identifier] = nil
        }
        publishMeshTriangleCount()
        scheduleLiveMeshPreview()
    }

    private func updateObjectMesh(_ anchors: [ARAnchor]) {
        guard lock.withLock({ acceptsFrames }), !meshCaptureDisabled else { return }
        do {
            for anchor in anchors.compactMap({ $0 as? ARMeshAnchor }) {
                let priorCount = surfaceMeshes[anchor.identifier]?.triangleCount ?? 0
                let total = surfaceMeshes.values.reduce(0) { $0 + $1.triangleCount }
                guard total - priorCount + anchor.geometry.faces.count <= 500_000 else {
                    throw LiDARSurfaceError.tooLarge
                }
                surfaceMeshes[anchor.identifier] = try LiDARCaptureFrames.mesh(anchor)
            }
        } catch {
            meshCaptureDisabled = true
            surfaceMeshes.removeAll(keepingCapacity: false)
            previewRevision &+= 1
            publishLiveMeshPreview(nil, revision: previewRevision)
            logger.error("Object mesh capture stopped: \(error.localizedDescription)")
            publish {
                $0.instruction = "The live mesh reached its safe size limit. Photos are still being saved."
            }
        }
        publishMeshTriangleCount()
        scheduleLiveMeshPreview()
    }

    private func publishMeshTriangleCount() {
        let count = surfaceMeshes.values.reduce(0) { $0 + $1.triangleCount }
        publishMeshTriangleCount(count)
    }

    func scheduleLiveMeshPreview() {
        guard !meshCaptureDisabled, lock.withLock({ acceptsFrames }) else { return }
        guard !surfaceMeshes.isEmpty else {
            previewRevision &+= 1
            previewDirty = false
            publishLiveMeshPreview(nil, revision: previewRevision)
            return
        }
        previewDirty = true
        guard !previewBuildInFlight else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastPreviewBuildTime >= 1.25 else { return }
        previewBuildInFlight = true
        previewDirty = false
        lastPreviewBuildTime = now
        previewRevision &+= 1
        let revision = previewRevision
        let meshSnapshot = Array(surfaceMeshes.values)
        let frameSnapshot = textureFrames
        previewQueue.async { [weak self] in
            guard let self else { return }
            let preview = LiveMeshPreviewBuilder.build(
                meshes: meshSnapshot,
                frames: frameSnapshot,
                revision: revision,
                requireForegroundMask: true,
                isCancelled: { !self.lock.withLock { self.acceptsFrames } }
            )
            DispatchQueue.main.async {
                if let preview, self.lock.withLock({ self.acceptsFrames }) {
                    self.publishLiveMeshPreview(preview, revision: preview.revision)
                }
                self.frameProcessingQueue.async {
                    self.previewBuildInFlight = false
                    if self.previewDirty { self.scheduleLiveMeshPreview() }
                }
            }
        }
    }

    private func scheduleDetection(for frame: ARFrame, orientation: UIInterfaceOrientation) {
        let generation = lock.withLock { () -> Int? in
            guard acceptsFrames, !detectionInFlight,
                  frame.timestamp - lastDetectionTime >= 0.45 else { return nil }
            detectionInFlight = true
            lastDetectionTime = frame.timestamp
            return sessionGeneration
        }
        guard let generation else { return }
        let pixelBuffer = frame.capturedImage
        let timestamp = frame.timestamp
        let imageOrientation = ScannerOrientation.imageProperty(for: orientation)
        analysisQueue.async { [weak self] in
            guard let self else { return }
            do {
                let detected = try self.detector.detect(
                    pixelBuffer: pixelBuffer,
                    orientation: imageOrientation,
                    timestamp: timestamp
                )
                let isLocked = self.lock.withLock { () -> Bool in
                    guard self.sessionGeneration == generation else { return self.latestSubject != nil }
                    if self.acceptsFrames {
                        self.latestSubject = self.subjectLockTracker.update(with: detected)
                    }
                    self.detectionInFlight = false
                    return self.latestSubject != nil
                }
                self.publish { $0.isSubjectLocked = isLocked }
            } catch {
                self.lock.withLock {
                    if self.sessionGeneration == generation { self.detectionInFlight = false }
                }
                self.logger.error("Foreground detection failed: \(error.localizedDescription)")
            }
        }
    }

    private func trackedPoints(
        in frame: ARFrame,
        subjectProjection: SubjectImageProjection?,
        viewport: CGSize,
        orientation: UIInterfaceOrientation
    ) -> (points: [CGPoint], surfacePoints: [SIMD3<Float>], source: GuidedPointSource?) {
        guard let subjectProjection,
              !subjectProjection.screenBounds.isNull,
              !subjectProjection.screenBounds.isEmpty else { return ([], [], nil) }
        if let depth = frame.smoothedSceneDepth ?? frame.sceneDepth {
            let result = depthPoints(
                depth,
                frame: frame,
                subjectProjection: subjectProjection,
                viewport: viewport,
                orientation: orientation
            )
            if result.screenPoints.count >= 6 {
                return (result.screenPoints, result.surfacePoints, .lidarDepth)
            }
        }
        guard let cloud = frame.rawFeaturePoints else { return ([], [], nil) }
        var points: [CGPoint] = []
        let stride = max(1, cloud.points.count / 180)
        for index in Swift.stride(from: 0, to: cloud.points.count, by: stride) {
            let point = frame.camera.projectPoint(
                cloud.points[index],
                orientation: orientation,
                viewportSize: viewport
            )
            if subjectProjection.contains(screenPoint: point) { points.append(point) }
            if points.count == 180 { break }
        }
        return (points, [], points.isEmpty ? nil : .visualFeatures)
    }

    private func depthPoints(
        _ depth: ARDepthData,
        frame: ARFrame,
        subjectProjection: SubjectImageProjection,
        viewport: CGSize,
        orientation: UIInterfaceOrientation
    ) -> (screenPoints: [CGPoint], surfacePoints: [SIMD3<Float>]) {
        let map = depth.depthMap
        let confidence = depth.confidenceMap
        CVPixelBufferLockBaseAddress(map, .readOnly)
        if let confidence { CVPixelBufferLockBaseAddress(confidence, .readOnly) }
        defer {
            CVPixelBufferUnlockBaseAddress(map, .readOnly)
            if let confidence { CVPixelBufferUnlockBaseAddress(confidence, .readOnly) }
        }
        guard let depthBase = CVPixelBufferGetBaseAddress(map) else { return ([], []) }
        let width = CVPixelBufferGetWidth(map)
        let height = CVPixelBufferGetHeight(map)
        let imageWidth = CVPixelBufferGetWidth(frame.capturedImage)
        let imageHeight = CVPixelBufferGetHeight(frame.capturedImage)
        let depthRow = CVPixelBufferGetBytesPerRow(map) / MemoryLayout<Float32>.stride
        let confidenceRow = confidence.map { CVPixelBufferGetBytesPerRow($0) } ?? 0
        let confidenceBase = confidence.flatMap { CVPixelBufferGetBaseAddress($0) }?
            .assumingMemoryBound(to: UInt8.self)
        let depthValues = depthBase.assumingMemoryBound(to: Float32.self)
        let sampleStride = max(3, max(width, height) / 34)
        let transform = frame.displayTransform(for: orientation, viewportSize: viewport)
        let intrinsics = frame.camera.intrinsics
        let focalX = intrinsics.columns.0.x
        let focalY = intrinsics.columns.1.y
        guard focalX > 0, focalY > 0 else { return ([], []) }
        let principalX = intrinsics.columns.2.x
        let principalY = intrinsics.columns.2.y
        let depthToImageX = Float(imageWidth) / Float(width)
        let depthToImageY = Float(imageHeight) / Float(height)
        var screenPoints: [CGPoint] = []
        var surfacePoints: [SIMD3<Float>] = []
        for y in Swift.stride(from: 0, to: height, by: sampleStride) {
            for x in Swift.stride(from: 0, to: width, by: sampleStride) {
                let metres = depthValues[y * depthRow + x]
                guard metres.isFinite, metres > 0.12, metres < 4 else { continue }
                if let confidenceBase, confidenceBase[y * confidenceRow + x] == 0 { continue }
                let normalized = CGPoint(
                    x: (CGFloat(x) + 0.5) / CGFloat(width),
                    y: (CGFloat(y) + 0.5) / CGFloat(height)
                ).applying(transform)
                let point = CGPoint(x: normalized.x * viewport.width, y: normalized.y * viewport.height)
                let rawImagePoint = CGPoint(
                    x: (CGFloat(x) + 0.5) / CGFloat(width),
                    y: (CGFloat(y) + 0.5) / CGFloat(height)
                )
                guard subjectProjection.contains(rawImagePoint: rawImagePoint) else { continue }

                screenPoints.append(point)
                let pixelX = (Float(x) + 0.5) * depthToImageX
                let pixelY = (Float(y) + 0.5) * depthToImageY
                if let sample = GuidedDepthProjection.worldPosition(
                    pixel: SIMD2<Float>(pixelX, pixelY),
                    depth: metres,
                    focalLength: SIMD2<Float>(focalX, focalY),
                    principalPoint: SIMD2<Float>(principalX, principalY),
                    cameraTransform: frame.camera.transform
                ) {
                    surfacePoints.append(sample)
                }
                if screenPoints.count == 180 { return (screenPoints, surfacePoints) }
            }
        }
        return (screenPoints, surfacePoints)
    }
}
