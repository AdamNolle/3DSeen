import CoreVideo
import Foundation
import ImageIO
import ARKit
import simd
import Vision

protocol ForegroundSubjectDetecting: AnyObject {
    func detect(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        timestamp: TimeInterval
    ) throws -> DetectedSubject?
}

enum ForegroundSubjectDetectionError: LocalizedError {
    case unsupportedMaskFormat(OSType)

    var errorDescription: String? {
        switch self {
        case .unsupportedMaskFormat(let format):
            return "Vision returned unsupported foreground-mask pixel format \(format)."
        }
    }
}

/// Class-agnostic foreground segmentation. It reports only a stable image region and never claims
/// to recognize, name, or prove reconstructability of the subject.
final class VisionForegroundSubjectDetector: ForegroundSubjectDetecting {
    func detect(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        timestamp: TimeInterval
    ) throws -> DetectedSubject? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation)
        try handler.perform([request])
        guard let observation = request.results?.first else { return nil }
        let mask = observation.instanceMask
        let format = CVPixelBufferGetPixelFormatType(mask)
        guard format == kCVPixelFormatType_OneComponent8 else {
            throw ForegroundSubjectDetectionError.unsupportedMaskFormat(format)
        }

        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(mask) else { return nil }
        let width = CVPixelBufferGetWidth(mask)
        let height = CVPixelBufferGetHeight(mask)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(mask)
        var labels = [UInt8](repeating: 0, count: width * height)
        let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            labels.replaceSubrange(
                y * width..<(y + 1) * width,
                with: UnsafeBufferPointer(start: bytes + y * bytesPerRow, count: width)
            )
        }
        guard let selection = SubjectMaskSelector.select(labels: labels, width: width, height: height) else {
            return nil
        }
        return DetectedSubject(
            normalizedBounds: selection.normalizedBounds,
            timestamp: timestamp,
            instanceLabel: selection.label,
            mask: SubjectInstanceMask(
                labels: labels,
                width: width,
                height: height,
                selectedLabel: selection.label
            ),
            imageOrientation: Self.captureOrientation(for: orientation)
        )
    }

    private static func captureOrientation(for orientation: CGImagePropertyOrientation) -> LiDARCaptureImageOrientation {
        switch orientation {
        case .left: return .portraitUpsideDown
        case .up: return .landscapeLeft
        case .down: return .landscapeRight
        default: return .portrait
        }
    }
}

/// Samples Vision's instance labels against confidence-filtered ARKit depth. The resulting points
/// are already in world coordinates, so the live overlay stays pinned to the measured objects.
final class RoomForegroundObjectDetector {
    func detect(in frame: ARFrame) throws -> [RoomObjectObservation] {
        guard let depth = frame.smoothedSceneDepth ?? frame.sceneDepth else { return [] }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: frame.capturedImage, orientation: .up)
        try handler.perform([request])
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else { return [] }

        let mask = observation.instanceMask
        let depthMap = depth.depthMap
        let maskWidth = CVPixelBufferGetWidth(mask)
        let maskHeight = CVPixelBufferGetHeight(mask)
        let depthWidth = CVPixelBufferGetWidth(depthMap)
        let depthHeight = CVPixelBufferGetHeight(depthMap)
        let imageWidth = CVPixelBufferGetWidth(frame.capturedImage)
        let imageHeight = CVPixelBufferGetHeight(frame.capturedImage)
        guard CVPixelBufferGetPixelFormatType(mask) == kCVPixelFormatType_OneComponent8,
              [kCVPixelFormatType_DepthFloat32, kCVPixelFormatType_OneComponent32Float]
                .contains(CVPixelBufferGetPixelFormatType(depthMap)),
              maskWidth > 0, maskHeight > 0, depthWidth > 0, depthHeight > 0,
              imageWidth > 0, imageHeight > 0 else { return [] }

        guard CVPixelBufferLockBaseAddress(mask, .readOnly) == kCVReturnSuccess else { return [] }
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        guard CVPixelBufferLockBaseAddress(depthMap, .readOnly) == kCVReturnSuccess else { return [] }
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        guard let maskBase = CVPixelBufferGetBaseAddress(mask),
              let depthBase = CVPixelBufferGetBaseAddress(depthMap) else { return [] }

        let confidenceMap = depth.confidenceMap
        let confidenceIsUsable = confidenceMap.map {
            CVPixelBufferGetPixelFormatType($0) == kCVPixelFormatType_OneComponent8
                && CVPixelBufferGetWidth($0) == depthWidth
                && CVPixelBufferGetHeight($0) == depthHeight
        } ?? false
        if confidenceIsUsable, let confidenceMap,
           CVPixelBufferLockBaseAddress(confidenceMap, .readOnly) != kCVReturnSuccess {
            return []
        }
        defer { if confidenceIsUsable, let confidenceMap { CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly) } }
        let confidenceBase = confidenceIsUsable ? confidenceMap.flatMap(CVPixelBufferGetBaseAddress) : nil

        let maskStride = CVPixelBufferGetBytesPerRow(mask)
        let depthStride = CVPixelBufferGetBytesPerRow(depthMap)
        let confidenceStride = confidenceMap.map { confidenceIsUsable ? CVPixelBufferGetBytesPerRow($0) : 0 } ?? 0
        let maskBytes = maskBase.assumingMemoryBound(to: UInt8.self)
        let confidenceBytes = confidenceBase?.assumingMemoryBound(to: UInt8.self)
        let sampleStep = max(6, depthWidth / 40)
        let intrinsics = frame.camera.intrinsics
        var pointsByLabel: [UInt8: [SIMD3<Float>]] = [:]

        for row in stride(from: sampleStep / 2, to: depthHeight, by: sampleStep) {
            for column in stride(from: sampleStep / 2, to: depthWidth, by: sampleStep) {
                let maskX = min(maskWidth - 1, Int((Float(column) + 0.5) * Float(maskWidth) / Float(depthWidth)))
                let maskY = min(maskHeight - 1, Int((Float(row) + 0.5) * Float(maskHeight) / Float(depthHeight)))
                let label = maskBytes[maskY * maskStride + maskX]
                guard label > 0, observation.allInstances.contains(Int(label)) else { continue }
                if let confidenceBytes,
                   confidenceBytes[row * confidenceStride + column] < UInt8(ARConfidenceLevel.medium.rawValue) {
                    continue
                }

                let depth = depthBase.loadUnaligned(fromByteOffset: row * depthStride + column * 4, as: Float.self)
                guard depth.isFinite, depth > 0.08, depth < 8 else { continue }
                let imagePixel = SIMD2<Float>(
                    (Float(column) + 0.5) * Float(imageWidth) / Float(depthWidth),
                    (Float(row) + 0.5) * Float(imageHeight) / Float(depthHeight)
                )
                guard let point = GuidedDepthProjection.worldPosition(
                    pixel: imagePixel,
                    depth: depth,
                    focalLength: SIMD2(intrinsics.columns.0.x, intrinsics.columns.1.y),
                    principalPoint: SIMD2(intrinsics.columns.2.x, intrinsics.columns.2.y),
                    cameraTransform: frame.camera.transform
                ) else { continue }
                pointsByLabel[label, default: []].append(point)
            }
        }

        return pointsByLabel
            .filter { $0.value.count >= 12 }
            .sorted { $0.value.count > $1.value.count }
            .prefix(16)
            .map { RoomObjectObservation(instanceLabel: $0.key, points: $0.value) }
    }
}
