import ARKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers

/// Copies depth and camera data while the ARFrame is valid; no ARFrames are retained.
enum LiDARCaptureFrames {
    static func save(_ frame: ARFrame, index: Int, folder: URL, context: CIContext) throws -> LiDARTextureFrame {
        guard let depth = frame.smoothedSceneDepth ?? frame.sceneDepth else { throw LiDARSurfaceError.noTextures }
        let depthMap = depth.depthMap
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        guard [kCVPixelFormatType_DepthFloat32, kCVPixelFormatType_OneComponent32Float].contains(CVPixelBufferGetPixelFormatType(depthMap)),
              let base = CVPixelBufferGetBaseAddress(depthMap) else { throw LiDARSurfaceError.noTextures }
        let confidence = depth.confidenceMap
        if let confidence {
            guard CVPixelBufferGetWidth(confidence) == width, CVPixelBufferGetHeight(confidence) == height else {
                throw LiDARSurfaceError.noTextures
            }
        }
        if let confidence { CVPixelBufferLockBaseAddress(confidence, .readOnly) }
        defer { if let confidence { CVPixelBufferUnlockBaseAddress(confidence, .readOnly) } }
        let confidenceBase = confidence.flatMap(CVPixelBufferGetBaseAddress)
        let confidenceStride = confidence.map(CVPixelBufferGetBytesPerRow) ?? 0
        let stride = CVPixelBufferGetBytesPerRow(depthMap)
        var values = [Float](repeating: 0, count: width * height)
        for row in 0..<height {
            for column in 0..<width {
                let value = base.loadUnaligned(fromByteOffset: row * stride + column * 4, as: Float.self)
                let isConfident = confidenceBase.map {
                    $0.load(fromByteOffset: row * confidenceStride + column, as: UInt8.self) > 0
                } ?? true
                values[row * width + column] = value.isFinite && value > 0 && isConfident ? value : 0
            }
        }
        let url = folder.appendingPathComponent(String(format: "frame_%04d.jpg", index))
        let image = CIImage(cvPixelBuffer: frame.capturedImage)
        let scale = min(1, 2048 / max(image.extent.width, image.extent.height))
        let resized = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        try write(resized, to: url, type: UTType.jpeg, context: context)
        let camera = LiDARTextureCamera(
            worldToCamera: frame.camera.transform.inverse,
            intrinsics: frame.camera.intrinsics,
            imageWidth: CVPixelBufferGetWidth(frame.capturedImage),
            imageHeight: CVPixelBufferGetHeight(frame.capturedImage),
            depthWidth: width, depthHeight: height, depths: values
        )
        try values.withUnsafeBytes { try Data($0).write(to: url.appendingPathExtension("depth.f32"), options: .atomic) }
        return LiDARTextureFrame(imageURL: url, camera: camera)
    }

    static func saveTexture(_ frame: ARFrame, index: Int, folder: URL, context: CIContext) throws {
        let source = CIImage(cvPixelBuffer: frame.capturedImage)
        let side = min(source.extent.width, source.extent.height) * 0.55
        let rect = CGRect(x: source.extent.midX - side / 2, y: source.extent.midY - side / 2, width: side, height: side)
        let cropped = source.cropped(to: rect)
            .transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
        let url = folder.appendingPathComponent(String(format: "texture_%03d.png", index))
        try write(cropped, to: url, type: UTType.png, context: context)
    }

    private static func write(_ image: CIImage, to url: URL, type: UTType, context: CIContext) throws {
        guard let cgImage = context.createCGImage(image, from: image.extent),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw LiDARSurfaceError.noTextures
        }
        CGImageDestinationAddImage(destination, cgImage, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw LiDARSurfaceError.noTextures }
    }

    static func mesh(_ anchor: ARMeshAnchor) throws -> LiDARSurfaceMesh {
        let source = anchor.geometry.vertices
        let faces = anchor.geometry.faces
        guard source.format == .float3, source.stride >= 12, source.count >= 1,
              faces.indexCountPerPrimitive == 3, [2, 4].contains(faces.bytesPerIndex),
              source.offset + (source.count - 1) * source.stride + 12 <= source.buffer.length,
              faces.count * 3 * faces.bytesPerIndex <= faces.buffer.length else {
            throw LiDARSurfaceError.invalidGeometry
        }
        let base = source.buffer.contents()
        let vertices = (0..<source.count).map { index in
            let offset = source.offset + index * source.stride
            let local = SIMD4<Float>(base.loadUnaligned(fromByteOffset: offset, as: Float.self),
                                     base.loadUnaligned(fromByteOffset: offset + 4, as: Float.self),
                                     base.loadUnaligned(fromByteOffset: offset + 8, as: Float.self), 1)
            let world = anchor.transform * local
            return SIMD3(world.x, world.y, world.z)
        }
        let indices = (0..<(faces.count * 3)).map { index -> UInt32 in
            let offset = index * faces.bytesPerIndex
            if faces.bytesPerIndex == 2 {
                return UInt32(faces.buffer.contents().loadUnaligned(fromByteOffset: offset, as: UInt16.self))
            }
            return faces.buffer.contents().loadUnaligned(fromByteOffset: offset, as: UInt32.self)
        }
        let classifications: [UInt8]
        if let source = anchor.geometry.classification,
           source.count == faces.count,
           source.format == .uchar,
           source.componentsPerVector == 1,
           source.offset >= 0,
           source.stride >= 1,
           source.offset + (source.count - 1) * source.stride + 1 <= source.buffer.length {
            let classificationBase = source.buffer.contents()
            classifications = (0..<source.count).map { index in
                classificationBase.load(fromByteOffset: source.offset + index * source.stride, as: UInt8.self)
            }
        } else {
            classifications = []
        }
        let mesh = LiDARSurfaceMesh(vertices: vertices, indices: indices, classifications: classifications)
        try mesh.validate()
        return mesh
    }
}
