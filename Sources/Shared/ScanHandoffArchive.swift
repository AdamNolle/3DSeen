import Foundation
import ZIPFoundation

/// Creates a file resource suitable for `MCSession.sendResource`. Image captures are directories
/// on iOS, but Multipeer handoff and macOS reconstruction both operate on a ZIP archive.
public enum ScanHandoffArchive {
    private static let captureQualityReportFileName = "3dseen-capture-quality.json"
    private static let maximumCaptureQualityReportBytes = 16 * 1_024

    public enum ArchiveError: LocalizedError {
        case missingCapture(URL)

        public var errorDescription: String? {
            switch self {
            case .missingCapture(let url):
                return "The capture archive at \(url.lastPathComponent) is no longer available."
            }
        }
    }

    public static func package(_ captureURL: URL, captureQualityReport: CaptureQualityReport? = nil) throws -> URL {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: captureURL.path, isDirectory: &isDirectory) else {
            throw ArchiveError.missingCapture(captureURL)
        }
        guard isDirectory.boolValue else { return captureURL }

        let packageURL = captureURL.deletingLastPathComponent()
            .appendingPathComponent("\(captureURL.lastPathComponent).zip")
        if fileManager.fileExists(atPath: packageURL.path) {
            try fileManager.removeItem(at: packageURL)
        }
        try fileManager.zipItem(at: captureURL, to: packageURL, shouldKeepParent: false)
        if let captureQualityReport {
            try append(captureQualityReport, to: packageURL)
        }
        return packageURL
    }

    /// Reads the optional image-quality sidecar from an extracted capture package. Older packages
    /// and RoomPlan USDZ handoffs intentionally return `nil`.
    public static func captureQualityReport(in extractedArchive: URL) -> CaptureQualityReport? {
        let url = extractedArchive.appendingPathComponent(captureQualityReportFileName)
        guard let data = try? BoundedArchiveExtractor.readMetadataFile(
            at: url,
            maximumByteCount: maximumCaptureQualityReportBytes
        ),
        let report = try? JSONDecoder().decode(CaptureQualityReport.self, from: data),
        report.isWithinTransferLimits else { return nil }
        return report
    }

    private static func append(_ report: CaptureQualityReport, to packageURL: URL) throws {
        let data = try JSONEncoder().encode(report)
        let archive = try Archive(url: packageURL, accessMode: .update)
        try archive.addEntry(
            with: captureQualityReportFileName,
            type: .file,
            uncompressedSize: Int64(data.count),
            compressionMethod: .deflate
        ) { position, size in
            let start = Int(position)
            let end = min(start + size, data.count)
            return start < end ? data.subdata(in: start..<end) : Data()
        }
    }
}
