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
        let presentation = lock.withLock { () -> (CGSize, UIInterfaceOrientation, Bool) in
            (viewportSize, interfaceOrientation, acceptsFrames)
        }
        guard presentation.2, presentation.0.width > 0, presentation.0.height > 0 else { return }
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
        let candidate = FrameCandidate(
            pixelBuffer: frame.capturedImage,
            pose: pose,
            orientation: presentation.1,
            trackingIsNormal: trackingIsNormal,
            quality: CameraFrameQualityAnalyzer.analyze(frame.capturedImage),
            motionIsAcceptable: CameraMotionGate.isAcceptable(current: pose, previous: previousPose)
        )
        lock.withLock { latestFrame = candidate }
        scheduleDetection(for: frame, orientation: presentation.1)

        let subject = lock.withLock { latestSubject }
        let subjectProjection = subject.flatMap { subject -> SubjectImageProjection? in
            guard subject.isFresh(at: frame.timestamp, maximumAge: 0.7) else { return nil }
            return SubjectImageProjection(
                subject: subject,
                imageToViewTransform: frame.displayTransform(
                    for: presentation.1,
                    viewportSize: presentation.0
                ),
                viewportSize: presentation.0,
                orientation: presentation.1
            )
        }
        let pointResult = trackedPoints(
            in: frame,
            subjectProjection: subjectProjection,
            viewport: presentation.0,
            orientation: presentation.1
        )
        publish { snapshot in
            snapshot.subjectBounds = subjectProjection?.screenBounds
            snapshot.points = pointResult.points
            snapshot.pointSource = pointResult.source
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
        evaluateAndCapture(candidate, manual: false)
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
    ) -> (points: [CGPoint], source: GuidedPointSource?) {
        guard let subjectProjection,
              !subjectProjection.screenBounds.isNull,
              !subjectProjection.screenBounds.isEmpty else { return ([], nil) }
        if let depth = frame.smoothedSceneDepth ?? frame.sceneDepth {
            let points = depthPoints(
                depth,
                frame: frame,
                subjectProjection: subjectProjection,
                viewport: viewport,
                orientation: orientation
            )
            if points.count >= 6 { return (points, .lidarDepth) }
        }
        guard let cloud = frame.rawFeaturePoints else { return ([], nil) }
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
        return (points, points.isEmpty ? nil : .visualFeatures)
    }

    private func depthPoints(
        _ depth: ARDepthData,
        frame: ARFrame,
        subjectProjection: SubjectImageProjection,
        viewport: CGSize,
        orientation: UIInterfaceOrientation
    ) -> [CGPoint] {
        let map = depth.depthMap
        let confidence = depth.confidenceMap
        CVPixelBufferLockBaseAddress(map, .readOnly)
        if let confidence { CVPixelBufferLockBaseAddress(confidence, .readOnly) }
        defer {
            CVPixelBufferUnlockBaseAddress(map, .readOnly)
            if let confidence { CVPixelBufferUnlockBaseAddress(confidence, .readOnly) }
        }
        guard let depthBase = CVPixelBufferGetBaseAddress(map) else { return [] }
        let width = CVPixelBufferGetWidth(map)
        let height = CVPixelBufferGetHeight(map)
        let depthRow = CVPixelBufferGetBytesPerRow(map) / MemoryLayout<Float32>.stride
        let confidenceRow = confidence.map { CVPixelBufferGetBytesPerRow($0) } ?? 0
        let confidenceBase = confidence.flatMap { CVPixelBufferGetBaseAddress($0) }?
            .assumingMemoryBound(to: UInt8.self)
        let depthValues = depthBase.assumingMemoryBound(to: Float32.self)
        let sampleStride = max(3, max(width, height) / 34)
        let transform = frame.displayTransform(for: orientation, viewportSize: viewport)
        var result: [CGPoint] = []
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
                if subjectProjection.contains(rawImagePoint: CGPoint(
                    x: (CGFloat(x) + 0.5) / CGFloat(width),
                    y: (CGFloat(y) + 0.5) / CGFloat(height)
                )) { result.append(point) }
                if result.count == 180 { return result }
            }
        }
        return result
    }
}
