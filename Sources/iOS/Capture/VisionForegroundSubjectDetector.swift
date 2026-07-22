import CoreVideo
import Foundation
import ImageIO
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
            )
        )
    }
}
