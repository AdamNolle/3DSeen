import Foundation
import OSLog
import ZIPFoundation

/// Manages local queueing, disk I/O, and thermal state throttling for the on-device compute option.
public final class LocalQueueManager: ObservableObject {
    private let logger = Logger(subsystem: "com.adamnolle.3DSeen.Shared", category: "Queue")
    private var thermalStateObserver: NSObjectProtocol?
    
    @Published public var isThrottled: Bool = false
    
    public init() {
        startMonitoringThermalState()
    }
    
    deinit {
        if let observer = thermalStateObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    private func startMonitoringThermalState() {
        thermalStateObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleThermalStateChange()
        }
        
        // Initial check
        handleThermalStateChange()
    }
    
    private func handleThermalStateChange() {
        let state = ProcessInfo.processInfo.thermalState
        logger.debug("Thermal state changed to: \(state.rawValue)")
        
        DispatchQueue.main.async {
            switch state {
            case .nominal, .fair:
                self.isThrottled = false
            case .serious, .critical:
                self.isThrottled = true
                self.logger.warning("Thermal throttling active. Pausing compute queue.")
            @unknown default:
                break
            }
        }
    }
    
    /// Packages raw image and depth map sequences into a ZIP archive using ZIPFoundation.
    public func packageScan(sourceURL: URL) async throws -> URL {
        logger.debug("Packaging scan at \(sourceURL)...")
        
        let fileManager = FileManager.default
        let destinationURL = sourceURL.appendingPathExtension("zip")
        
        // Remove existing zip if it exists
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        
        // This is a heavy operation, so we run it on a background task
        return try await Task.detached(priority: .userInitiated) {
            try fileManager.zipItem(at: sourceURL, to: destinationURL)
            return destinationURL
        }.value
    }
}
