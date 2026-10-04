import Foundation

#if canImport(UIKit)
import UIKit
#endif

extension PlaybackViewModel {
    /// Releases the global tvOS lease only when the caller still owns it.
    /// The caller must already be on MainActor so the check and clear are atomic.
    static func releaseIdleTimerLease(for token: UUID) {
        guard activeIdleTimerOwnerToken == token else { return }
        activeIdleTimerOwnerToken = nil
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = false
        #endif
    }

    func updateIdleTimerForPlayback() {
        guard idleTimerLeaseEnabled else { return }
        setPlaybackIdleTimerDisabled(isPlaying)
    }

    func setPlaybackIdleTimerDisabled(_ disabled: Bool) {
        if idleTimerLeaseEnabled {
            if disabled {
                Self.activeIdleTimerOwnerToken = idleTimerOwnerToken
                idleTimerSetter(true)
            } else {
                guard Self.activeIdleTimerOwnerToken == idleTimerOwnerToken else { return }
                Self.activeIdleTimerOwnerToken = nil
                idleTimerSetter(false)
            }
        } else {
            // iOS keeps its existing explicit loading/resume/stop writes.
            idleTimerSetter(disabled)
        }
    }
}
