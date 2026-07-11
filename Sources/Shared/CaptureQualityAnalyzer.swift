import CoreGraphics
import Foundation
import ImageIO

/// A measured exposure and sharpness sample for one decoded capture frame. Values are normalized
/// to 0...1 so the aggregation rules can be tested independently from image decoding.
public struct CaptureFrameMetrics: Equatable, Sendable {
    public let meanLuma: Double
    public let edgeContrast: Double

    public init(meanLuma: Double, edgeContrast: Double) {
        self.meanLuma = min(max(meanLuma, 0), 1)
        self.edgeContrast = max(edgeContrast, 0)
    }
}

/// Persistable quality facts from a bounded sample of a captured image archive. This report does
/// not claim subject coverage or reconstruction quality; it only records decoded frame evidence.
public struct CaptureQualityReport: Codable, Equatable, Sendable {
    public let totalFrameCount: Int
    public let analyzedFrameCount: Int
    public let usableFrameCount: Int
    public let darkFrameCount: Int
    public let brightFrameCount: Int
    public let blurryFrameCount: Int

    public init(totalFrameCount: Int,
                analyzedFrameCount: Int,
                usableFrameCount: Int,
                darkFrameCount: Int,
                brightFrameCount: Int,
                blurryFrameCount: Int) {
        self.totalFrameCount = max(0, totalFrameCount)
        self.analyzedFrameCount = max(0, analyzedFrameCount)
        self.usableFrameCount = max(0, usableFrameCount)
        self.darkFrameCount = max(0, darkFrameCount)
        self.brightFrameCount = max(0, brightFrameCount)
        self.blurryFrameCount = max(0, blurryFrameCount)
    }

    public var warningCount: Int { darkFrameCount + brightFrameCount + blurryFrameCount }

    public var usablePercent: Int {
        guard analyzedFrameCount > 0 else { return 0 }
        return Int((Double(usableFrameCount) / Double(analyzedFrameCount) * 100).rounded())
    }

    public var summary: String {
        guard analyzedFrameCount > 0 else { return "No decodable capture frames" }
        guard warningCount > 0 else { return "\(usableFrameCount) sampled frames passed exposure and sharpness checks" }
        return "\(warningCount) sampled frames need attention"
    }
}

/// Decodes a bounded, evenly-spaced image sample and classifies simple exposure and edge-detail
/// evidence. It intentionally leaves coverage and scene completeness to future capture engines.
public enum CaptureQualityAnalyzer {
    public static let darkLumaThreshold = 0.12
    public static let brightLumaThreshold = 0.90
    public static let minimumEdgeContrast = 0.025

    public static func analyze(archive: URL, maximumFrames: Int = 80) -> CaptureQualityReport {
        let frameURLs = imageFrameURLs(in: archive)
        let samples = sampledURLs(frameURLs, maximumFrames: maximumFrames)
        let metrics = samples.compactMap(frameMetrics(from:))
        return report(from: metrics, totalFrameCount: frameURLs.count)
    }

    public static func report(from metrics: [CaptureFrameMetrics], totalFrameCount: Int? = nil) -> CaptureQualityReport {
        var usable = 0
        var dark = 0
        var bright = 0
        var blurry = 0

        for metric in metrics {
            switch classification(for: metric) {
            case .usable: usable += 1
            case .dark: dark += 1
            case .bright: bright += 1
            case .blurry: blurry += 1
            }
        }

        return CaptureQualityReport(
            totalFrameCount: totalFrameCount ?? metrics.count,
            analyzedFrameCount: metrics.count,
            usableFrameCount: usable,
            darkFrameCount: dark,
            brightFrameCount: bright,
            blurryFrameCount: blurry
        )
    }

    private enum Classification {
        case usable
        case dark
        case bright
        case blurry
    }

    private static func classification(for metric: CaptureFrameMetrics) -> Classification {
        if metric.meanLuma < darkLumaThreshold { return .dark }
        if metric.meanLuma > brightLumaThreshold { return .bright }
        if metric.edgeContrast < minimumEdgeContrast { return .blurry }
        return .usable
    }

    private static func imageFrameURLs(in archive: URL) -> [URL] {
        let imageExtensions: Set<String> = ["jpg", "jpeg", "heic", "png"]
        guard let files = FileManager.default.enumerator(at: archive, includingPropertiesForKeys: nil) else { return [] }
        return files.compactMap { $0 as? URL }
            .filter { imageExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.path < $1.path }
    }

    private static func sampledURLs(_ urls: [URL], maximumFrames: Int) -> [URL] {
        guard !urls.isEmpty, maximumFrames > 0 else { return [] }
        guard urls.count > maximumFrames else { return urls }
        if maximumFrames == 1 { return [urls[urls.count / 2]] }
        let stride = Double(urls.count - 1) / Double(maximumFrames - 1)
        return (0..<maximumFrames).map { index in
            urls[Int((Double(index) * stride).rounded())]
        }
    }

    private static func frameMetrics(from url: URL) -> CaptureFrameMetrics? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }

        let maximumDimension = 160
        let scale = min(1, Double(maximumDimension) / Double(max(image.width, image.height)))
        let width = max(2, Int((Double(image.width) * scale).rounded()))
        let height = max(2, Int((Double(image.height) * scale).rounded()))
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return nil }

        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var luma = [Double](repeating: 0, count: width * height)
        var totalLuma = 0.0
        for index in 0..<(width * height) {
            let offset = index * 4
            let value = (0.2126 * Double(pixels[offset])
                + 0.7152 * Double(pixels[offset + 1])
                + 0.0722 * Double(pixels[offset + 2])) / 255
            luma[index] = value
            totalLuma += value
        }

        var edgeTotal = 0.0
        var edgeCount = 0
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                if x + 1 < width {
                    edgeTotal += abs(luma[index] - luma[index + 1])
                    edgeCount += 1
                }
                if y + 1 < height {
                    edgeTotal += abs(luma[index] - luma[index + width])
                    edgeCount += 1
                }
            }
        }

        return CaptureFrameMetrics(
            meanLuma: totalLuma / Double(luma.count),
            edgeContrast: edgeCount > 0 ? edgeTotal / Double(edgeCount) : 0
        )
    }
}
