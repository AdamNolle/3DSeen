import Foundation
import simd

/// The headerless, 32-byte antimatter15 .splat format: little-endian position/scale,
/// RGBA bytes, and a quantized quaternion in w,x,y,z order.
struct CompactSplatFile {
    static let maximumPointCount = 500_000
    static let maximumFileByteCount = maximumPointCount * 32

    struct Point {
        let position: SIMD3<Float>
        let scale: SIMD3<Float>
        let rgba: SIMD4<UInt8>
        let rotation: SIMD4<Float>

        var logScale: SIMD3<Float> { SIMD3(log(scale.x), log(scale.y), log(scale.z)) }
        var opacityLogit: Float {
            if rgba.w == 0 { return -20 }
            if rgba.w == 255 { return 20 }
            let alpha = Float(rgba.w)
            return log(alpha / (255 - alpha))
        }
    }

    enum ReadError: LocalizedError, Equatable {
        case incomplete, invalidPoint, invalidIndex, tooManyPoints, fileSizeUnavailable

        var errorDescription: String? {
            switch self {
            case .incomplete: return "The compact splat file is empty or has an incomplete 32-byte record."
            case .invalidPoint: return "The splat file contains invalid coordinates, scales, or rotation."
            case .invalidIndex: return "The requested splat is outside the file."
            case .tooManyPoints:
                return "This device can preview .splat files with up to \(CompactSplatFile.maximumPointCount.formatted()) points."
            case .fileSizeUnavailable: return "The splat file size could not be checked safely."
            }
        }
    }

    private let bytes: Data
    let count: Int

    init(contentsOf url: URL) throws {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = values.fileSize,
              fileSize >= 0 else {
            throw ReadError.fileSizeUnavailable
        }
        guard fileSize <= Self.maximumFileByteCount else { throw ReadError.tooManyPoints }
        try self.init(data: Data(contentsOf: url, options: .mappedIfSafe))
    }

    init(data: Data) throws {
        guard !data.isEmpty, data.count.isMultiple(of: 32) else { throw ReadError.incomplete }
        guard data.count <= Self.maximumFileByteCount else { throw ReadError.tooManyPoints }
        bytes = data
        count = data.count / 32
        // Reject the complete file before reserving GPU buffers or displaying a partial model.
        for index in 0..<count { _ = try point(at: index) }
    }

    func point(at index: Int) throws -> Point {
        guard (0..<count).contains(index) else { throw ReadError.invalidIndex }
        let offset = bytes.startIndex + index * 32
        let position = SIMD3(float(at: offset), float(at: offset + 4), float(at: offset + 8))
        let scale = SIMD3(float(at: offset + 12), float(at: offset + 16), float(at: offset + 20))
        let rgba = SIMD4(bytes[offset + 24], bytes[offset + 25], bytes[offset + 26], bytes[offset + 27])
        let rotation = SIMD4<Float>(
            (Float(bytes[offset + 28]) - 128) / 128,
            (Float(bytes[offset + 29]) - 128) / 128,
            (Float(bytes[offset + 30]) - 128) / 128,
            (Float(bytes[offset + 31]) - 128) / 128
        )
        guard position.x.isFinite, position.y.isFinite, position.z.isFinite,
              scale.x.isFinite, scale.y.isFinite, scale.z.isFinite,
              scale.x > 0, scale.y > 0, scale.z > 0,
              simd_length_squared(rotation) > 0 else { throw ReadError.invalidPoint }
        return Point(position: position, scale: scale, rgba: rgba, rotation: simd_normalize(rotation))
    }

    private func float(at offset: Int) -> Float {
        let bits = UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
        return Float(bitPattern: bits)
    }
}
