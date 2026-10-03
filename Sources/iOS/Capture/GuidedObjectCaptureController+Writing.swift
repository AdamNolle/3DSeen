import ARKit
import CoreImage
import Foundation
import UIKit

extension GuidedObjectCaptureController {
    func evaluateAndCapture(_ frame: FrameCandidate, manual: Bool) {
        let group = writerGroup
        let reservation = lock.withLock { () -> (index: Int, folder: URL, generation: Int)? in
            guard acceptsFrames,
                  frame.sessionGeneration == sessionGeneration,
                  manual || autoCaptureEnabled
            else { return nil }
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
            // Enter while holding the same lock that finish/stop uses to close admission.
            // This prevents notify from observing an empty group after a frame is reserved.
            group.enter()
            return (index, captureFolder, sessionGeneration)
        }
        guard let reservation else { return }
        let destination = reservation.folder.appendingPathComponent(
            String(format: "frame_%04d.jpg", reservation.index)
        )
        let surfaceFramesFolder = reservation.folder.appendingPathComponent("surface-frames", isDirectory: true)
        let frameProcessingQueue = self.frameProcessingQueue
        writerQueue.async { [weak self] in
            // Leave even if the controller has gone away. Teardown may be waiting on this group.
            defer { group.leave() }
            guard let self else { return }
            var savedTextureFrame: LiDARTextureFrame?
            defer {
                frameProcessingQueue.async {
                    let belongsToCurrentSession = self.lock.withLock {
                        self.sessionGeneration == reservation.generation
                    }
                    if belongsToCurrentSession, let savedTextureFrame {
                        self.textureFrames.append(savedTextureFrame)
                        self.scheduleLiveMeshPreview()
                    }
                    self.lock.withLock { self.writerBacklog = max(0, self.writerBacklog - 1) }
                }
            }
            autoreleasepool {
                let image = CIImage(cvPixelBuffer: frame.pixelBuffer)
                guard let cgImage = self.ciContext.createCGImage(image, from: image.extent),
                      let data = UIImage(
                        cgImage: cgImage,
                        scale: 1,
                        orientation: ScannerOrientation.imageOrientation(for: frame.orientation)
                      ).jpegData(compressionQuality: 0.92)
                else {
                    self.logger.error("Could not encode guided scan frame")
                    return
                }
                do {
                    try data.write(to: destination, options: .atomic)
                    self.publish { snapshot in
                        guard self.lock.withLock({ self.sessionGeneration == reservation.generation }) else { return }
                        snapshot.frameCount += 1
                    }
                    do {
                        savedTextureFrame = try LiDARCaptureFrames.save(
                            frame.frame,
                            index: reservation.index,
                            folder: surfaceFramesFolder,
                            context: self.ciContext,
                            surfaceMask: frame.surfaceMask
                        )
                    } catch {
                        self.logger.error("Could not save depth-aligned object texture frame: \(error.localizedDescription)")
                    }
                } catch {
                    self.logger.error("Could not write guided scan frame: \(error.localizedDescription)")
                }
            }
        }
    }

    func finalizeObjectBundle(
        meshes: [LiDARSurfaceMesh],
        frames: [LiDARTextureFrame],
        in folder: URL
    ) -> Bool {
        let textureDirectory = folder.appendingPathComponent("surface-frames", isDirectory: true)
        let modelURL = folder.appendingPathComponent(LiDARCaptureBundle.objectModelName)
        let reportURL = folder.appendingPathComponent(LiDARCaptureBundle.reportName)
        let archiveDirectory = folder.appendingPathComponent(LiDARCaptureBundle.framesName, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: textureDirectory) }
        guard !meshes.isEmpty, frames.contains(where: { $0.surfaceMask != nil }) else { return false }

        do {
            let result = try LiDARTextureExporter.export(
                meshes: meshes,
                frames: frames,
                to: modelURL,
                requireForegroundMask: true
            )
            try FileManager.default.createDirectory(at: archiveDirectory, withIntermediateDirectories: true)
            let photoURLs = try FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: nil
            )
            .filter { $0.lastPathComponent.hasPrefix("frame_") && $0.pathExtension.lowercased() == "jpg" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            for photoURL in photoURLs {
                let destination = archiveDirectory.appendingPathComponent(photoURL.lastPathComponent)
                try FileManager.default.copyItem(at: photoURL, to: destination)
            }
            let report = LiDARCaptureReport(
                schemaVersion: 2,
                triangleCount: result.triangleCount,
                texturedTriangleCount: result.texturedTriangleCount,
                textureFrameCount: frames.count,
                textureSnapshotCount: 0,
                surfaceCounts: result.surfaceCounts,
                modelFileName: LiDARCaptureBundle.objectModelName
            )
            try JSONEncoder().encode(report).write(to: reportURL, options: .atomic)
            // The source photos remain intact until the mesh, archive copy, and report are committed.
            for photoURL in photoURLs {
                try? FileManager.default.removeItem(at: photoURL)
            }
            return true
        } catch {
            logger.error("Object USDZ export failed: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: modelURL)
            try? FileManager.default.removeItem(at: reportURL)
            try? FileManager.default.removeItem(at: archiveDirectory)
            return false
        }
    }
}
