import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import simd
import UIKit

struct SubjectInstanceMask: Equatable, Sendable {
    let labels: [UInt8]
    let width: Int
    let height: Int
    let selectedLabel: UInt8

    func contains(normalizedPoint: CGPoint) -> Bool {
        guard width > 0, height > 0,
              normalizedPoint.x >= 0, normalizedPoint.x < 1,
              normalizedPoint.y >= 0, normalizedPoint.y < 1 else { return false }
        let x = min(Int(normalizedPoint.x * CGFloat(width)), width - 1)
        let y = min(Int(normalizedPoint.y * CGFloat(height)), height - 1)
        return labels[y * width + x] == selectedLabel
    }
}

struct DetectedSubject: Equatable, Sendable {
    let normalizedBounds: CGRect
    let timestamp: TimeInterval
    let instanceLabel: UInt8
    let mask: SubjectInstanceMask

    func isFresh(at frameTimestamp: TimeInterval, maximumAge: TimeInterval) -> Bool {
        frameTimestamp >= timestamp && frameTimestamp - timestamp <= maximumAge
    }
}

struct SubjectLockTracker {
    private(set) var lockedSubject: DetectedSubject?
    private var candidate: DetectedSubject?
    private var candidateConfirmations = 0
    private var consecutiveMisses = 0
    var requiredConfirmations = 2
    var allowedMisses = 2
    var minimumIntersectionOverUnion: CGFloat = 0.25

    mutating func update(with detection: DetectedSubject?) -> DetectedSubject? {
        guard let detection else {
            consecutiveMisses += 1
            if consecutiveMisses > allowedMisses {
                lockedSubject = nil
                candidate = nil
                candidateConfirmations = 0
            }
            return lockedSubject
        }
        consecutiveMisses = 0
        if let lockedSubject,
           Self.intersectionOverUnion(lockedSubject.normalizedBounds, detection.normalizedBounds)
            >= minimumIntersectionOverUnion {
            self.lockedSubject = detection
            candidate = nil
            candidateConfirmations = 0
            return detection
        }
        if let candidate,
           Self.intersectionOverUnion(candidate.normalizedBounds, detection.normalizedBounds)
            >= minimumIntersectionOverUnion {
            candidateConfirmations += 1
        } else {
            candidateConfirmations = 1
        }
        candidate = detection
        if candidateConfirmations >= requiredConfirmations {
            lockedSubject = detection
            candidate = nil
            candidateConfirmations = 0
        }
        return lockedSubject
    }

    static func intersectionOverUnion(_ first: CGRect, _ second: CGRect) -> CGFloat {
        let intersection = first.intersection(second)
        guard !intersection.isNull, !intersection.isEmpty else { return 0 }
        let union = first.width * first.height + second.width * second.height
            - intersection.width * intersection.height
        return union > 0 ? intersection.width * intersection.height / union : 0
    }
}

struct SubjectMaskSelection: Equatable {
    let label: UInt8
    /// Normalized, top-left-origin bounds in the oriented camera image.
    let normalizedBounds: CGRect
}

enum SubjectMaskSelector {
    static func select(
        labels: [UInt8],
        width: Int,
        height: Int,
        preferredPoint: CGPoint = CGPoint(x: 0.5, y: 0.5),
        minimumAreaFraction: Double = 0.02
    ) -> SubjectMaskSelection? {
        guard width > 0, height > 0, labels.count == width * height else { return nil }
        let px = min(max(Int(preferredPoint.x * CGFloat(width)), 0), width - 1)
        let py = min(max(Int(preferredPoint.y * CGFloat(height)), 0), height - 1)
        let preferred = labels[py * width + px]

        var counts: [UInt8: Int] = [:]
        for label in labels where label != 0 { counts[label, default: 0] += 1 }
        let minimumCount = Int(ceil(Double(labels.count) * minimumAreaFraction))
        let selectedLabel: UInt8?
        if preferred != 0, counts[preferred, default: 0] >= minimumCount {
            selectedLabel = preferred
        } else {
            selectedLabel = counts.filter { $0.value >= minimumCount }.max { $0.value < $1.value }?.key
        }
        guard let selectedLabel else { return nil }

        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where labels[y * width + x] == selectedLabel {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return SubjectMaskSelection(
            label: selectedLabel,
            normalizedBounds: CGRect(
                x: CGFloat(minX) / CGFloat(width),
                y: CGFloat(minY) / CGFloat(height),
                width: CGFloat(maxX - minX + 1) / CGFloat(width),
                height: CGFloat(maxY - minY + 1) / CGFloat(height)
            )
        )
    }
}

enum ScannerOrientation {
    static func imageProperty(for interfaceOrientation: UIInterfaceOrientation) -> CGImagePropertyOrientation {
        switch interfaceOrientation {
        case .portrait: return .right
        case .portraitUpsideDown: return .left
        case .landscapeLeft: return .up
        case .landscapeRight: return .down
        default: return .right
        }
    }

    static func orientedPoint(fromRaw point: CGPoint, orientation: UIInterfaceOrientation) -> CGPoint {
        switch orientation {
        case .portrait: return CGPoint(x: 1 - point.y, y: point.x)
        case .portraitUpsideDown: return CGPoint(x: point.y, y: 1 - point.x)
        case .landscapeRight: return CGPoint(x: 1 - point.x, y: 1 - point.y)
        default: return point
        }
    }

    static func rawPoint(fromOriented point: CGPoint, orientation: UIInterfaceOrientation) -> CGPoint {
        switch orientation {
        case .portrait: return CGPoint(x: point.y, y: 1 - point.x)
        case .portraitUpsideDown: return CGPoint(x: 1 - point.y, y: point.x)
        case .landscapeRight: return CGPoint(x: 1 - point.x, y: 1 - point.y)
        default: return point
        }
    }

    static func imageOrientation(for interfaceOrientation: UIInterfaceOrientation) -> UIImage.Orientation {
        switch interfaceOrientation {
        case .portrait: return .right
        case .portraitUpsideDown: return .left
        case .landscapeLeft: return .up
        case .landscapeRight: return .down
        default: return .right
        }
    }
}

struct SubjectImageProjection {
    let subject: DetectedSubject
    let imageToViewTransform: CGAffineTransform
    let viewportSize: CGSize
    let orientation: UIInterfaceOrientation

    func contains(rawImagePoint: CGPoint) -> Bool {
        subject.mask.contains(normalizedPoint: ScannerOrientation.orientedPoint(
            fromRaw: rawImagePoint,
            orientation: orientation
        ))
    }

    func contains(screenPoint: CGPoint) -> Bool {
        let determinant = imageToViewTransform.a * imageToViewTransform.d
            - imageToViewTransform.b * imageToViewTransform.c
        guard viewportSize.width > 0, viewportSize.height > 0,
              abs(determinant) > .ulpOfOne else { return false }
        let viewPoint = CGPoint(
            x: screenPoint.x / viewportSize.width,
            y: screenPoint.y / viewportSize.height
        )
        return contains(rawImagePoint: viewPoint.applying(imageToViewTransform.inverted()))
    }

    var screenBounds: CGRect {
        let bounds = subject.normalizedBounds
        let orientedCorners = [
            bounds.origin,
            CGPoint(x: bounds.maxX, y: bounds.minY),
            CGPoint(x: bounds.minX, y: bounds.maxY),
            CGPoint(x: bounds.maxX, y: bounds.maxY)
        ]
        let screenCorners = orientedCorners.map {
            let raw = ScannerOrientation.rawPoint(fromOriented: $0, orientation: orientation)
            let view = raw.applying(imageToViewTransform)
            return CGPoint(x: view.x * viewportSize.width, y: view.y * viewportSize.height)
        }
        let xs = screenCorners.map(\.x)
        let ys = screenCorners.map(\.y)
        return CGRect(
            x: xs.min() ?? 0,
            y: ys.min() ?? 0,
            width: (xs.max() ?? 0) - (xs.min() ?? 0),
            height: (ys.max() ?? 0) - (ys.min() ?? 0)
        ).intersection(CGRect(origin: .zero, size: viewportSize))
    }
}

enum GuidedPointSource: String, Equatable, Sendable {
    case lidarDepth = "LiDAR depth samples"
    case visualFeatures = "AR tracked feature points"
}

struct GuidedScanSnapshot: Equatable, Sendable {
    enum Phase: String, Equatable, Sendable {
        case starting
        case seekingSubject
        case capturing
        case finalizing
        case failed
    }

    var phase: Phase = .starting
    var instruction = "Move slowly until the object is detected."
    var trackingStatus = "starting"
    var subjectBounds: CGRect?
    var points: [CGPoint] = []
    var pointSource: GuidedPointSource?
    var isSubjectLocked = false
    var frameCount = 0
    var recommendedFrameCount = 48
    var isAutoCaptureEnabled = true
    var isFinishing = false
}

struct CapturePose: Equatable {
    let transform: simd_float4x4
    let timestamp: TimeInterval
}

struct FrameQualityMetrics: Equatable {
    let meanLuminance: Double
    let edgeContrast: Double

    var isAcceptable: Bool {
        (0.10...0.92).contains(meanLuminance) && edgeContrast >= 0.018
    }
}

enum CameraFrameQualityAnalyzer {
    static func analyze(_ pixelBuffer: CVPixelBuffer) -> FrameQualityMetrics {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        let isPlanar = CVPixelBufferGetPlaneCount(pixelBuffer) > 0
        let width = isPlanar ? CVPixelBufferGetWidthOfPlane(pixelBuffer, 0) : CVPixelBufferGetWidth(pixelBuffer)
        let height = isPlanar ? CVPixelBufferGetHeightOfPlane(pixelBuffer, 0) : CVPixelBufferGetHeight(pixelBuffer)
        let row = isPlanar ? CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0) : CVPixelBufferGetBytesPerRow(pixelBuffer)
        let address = isPlanar ? CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) : CVPixelBufferGetBaseAddress(pixelBuffer)
        guard width > 2, height > 2, let address else {
            return FrameQualityMetrics(meanLuminance: 0, edgeContrast: 0)
        }
        let bytes = address.assumingMemoryBound(to: UInt8.self)
        let step = max(6, max(width, height) / 48)
        var luminanceTotal = 0
        var differenceTotal = 0
        var count = 0
        for y in Swift.stride(from: step, to: height - step, by: step) {
            for x in Swift.stride(from: step, to: width - step, by: step) {
                let value = Int(bytes[y * row + x])
                luminanceTotal += value
                differenceTotal += abs(value - Int(bytes[y * row + x + step]))
                differenceTotal += abs(value - Int(bytes[(y + step) * row + x]))
                count += 1
            }
        }
        guard count > 0 else { return FrameQualityMetrics(meanLuminance: 0, edgeContrast: 0) }
        return FrameQualityMetrics(
            meanLuminance: Double(luminanceTotal) / Double(count * 255),
            edgeContrast: Double(differenceTotal) / Double(count * 2 * 255)
        )
    }
}

enum CameraMotionGate {
    static func isAcceptable(current: CapturePose, previous: CapturePose?) -> Bool {
        guard let previous else { return true }
        let interval = current.timestamp - previous.timestamp
        guard interval > 0 else { return false }
        let currentPosition = SIMD3<Float>(current.transform.columns.3.x,
                                           current.transform.columns.3.y,
                                           current.transform.columns.3.z)
        let previousPosition = SIMD3<Float>(previous.transform.columns.3.x,
                                            previous.transform.columns.3.y,
                                            previous.transform.columns.3.z)
        let translationSpeed = simd_distance(currentPosition, previousPosition) / Float(interval)
        let first = simd_quatf(current.transform)
        let second = simd_quatf(previous.transform)
        let dot = min(max(abs(simd_dot(first.vector, second.vector)), 0), 1)
        let angularSpeed = (2 * acos(dot)) / Float(interval)
        return translationSpeed <= 1.0 && angularSpeed <= 1.75
    }
}

enum CaptureGateDecision: Equatable {
    case accept
    case reject(String)
}

struct GuidedCaptureGate: Equatable {
    var minimumInterval: TimeInterval = 0.55
    var minimumTranslation: Float = 0.05
    var maximumWriterBacklog = 2

    func evaluate(
        current: CapturePose,
        previous: CapturePose?,
        trackingIsNormal: Bool,
        subjectIsFresh: Bool,
        imageQualityIsAcceptable: Bool = true,
        motionIsAcceptable: Bool = true,
        writerBacklog: Int,
        manual: Bool = false
    ) -> CaptureGateDecision {
        guard trackingIsNormal else { return .reject("tracking") }
        guard imageQualityIsAcceptable else { return .reject("image quality") }
        guard motionIsAcceptable else { return .reject("move slower") }
        guard writerBacklog < maximumWriterBacklog else { return .reject("writer busy") }
        guard manual || subjectIsFresh else { return .reject("subject") }
        guard let previous else { return .accept }
        guard current.timestamp >= previous.timestamp,
              current.timestamp - previous.timestamp >= minimumInterval || manual else {
            return .reject("interval")
        }
        if manual { return .accept }

        let currentPosition = SIMD3<Float>(current.transform.columns.3.x,
                                           current.transform.columns.3.y,
                                           current.transform.columns.3.z)
        let previousPosition = SIMD3<Float>(previous.transform.columns.3.x,
                                            previous.transform.columns.3.y,
                                            previous.transform.columns.3.z)
        let translation = simd_distance(currentPosition, previousPosition)
        guard translation >= minimumTranslation else {
            return .reject("move farther")
        }
        return .accept
    }
}
