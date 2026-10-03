import Foundation

final class HandoffInvitationAdmissionLimiter {
    private let lock = NSLock()
    private var gate = HandoffInvitationAdmissionGate()

    func admit(_ installationID: HandoffInstallationID, at time: TimeInterval) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return gate.admit(installationID, at: time)
    }

    func release(_ installationID: HandoffInstallationID) {
        lock.lock()
        gate.release(installationID)
        lock.unlock()
    }
}
