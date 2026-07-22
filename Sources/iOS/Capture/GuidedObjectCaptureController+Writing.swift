import ARKit
import UIKit

extension GuidedObjectCaptureController {
    func evaluateAndCapture(_ frame: FrameCandidate, manual: Bool) {
        let group = writerGroup
        let reservation = lock.withLock { () -> Int? in
            guard acceptsFrames, manual || autoCaptureEnabled else { return nil }
            let subjectIsFresh = latestSubject?.isFresh(
                at: frame.pose.timestamp,
                maximumAge: 0.7
            ) ?? false
            guard gate.evaluate(
                current: frame.pose,
                previous: lastAcceptedPose,
                trackingIsNormal: frame.trackingIsNormal,
                subjectIsFresh: subjectIsFresh,
                imageQualityIsAcceptable: frame.quality.isAcceptable,
                motionIsAcceptable: frame.motionIsAcceptable,
                writerBacklog: writerBacklog,
                manual: manual
            ) == .accept else { return nil }
            lastAcceptedPose = frame.pose
            let index = nextFrameIndex
            nextFrameIndex += 1
            writerBacklog += 1
            // Enter while holding the same lock that finish/stop uses to close admission. This
            // prevents notify from observing an empty group after a frame has been reserved.
            group.enter()
            return index
        }
        guard let index = reservation else { return }
        let destination = captureFolder.appendingPathComponent(
            String(format: "frame_%04d.jpg", index)
        )
        writerQueue.async { [weak self] in
            defer { group.leave() }
            guard let self else { return }
            defer { self.lock.withLock { self.writerBacklog = max(0, self.writerBacklog - 1) } }
            autoreleasepool {
                let image = CIImage(cvPixelBuffer: frame.pixelBuffer)
                guard let cgImage = self.ciContext.createCGImage(image, from: image.extent),
                      let data = UIImage(
                        cgImage: cgImage,
                        scale: 1,
                        orientation: ScannerOrientation.imageOrientation(for: frame.orientation)
                      ).jpegData(compressionQuality: 0.92) else {
                    self.logger.error("Could not encode guided scan frame \(index)")
                    return
                }
                do {
                    try data.write(to: destination, options: .atomic)
                    self.publish { $0.frameCount += 1 }
                } catch {
                    self.logger.error("Could not write guided scan frame: \(error.localizedDescription)")
                }
            }
        }
    }
}
