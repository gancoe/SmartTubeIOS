import Foundation
import SmartTubeIOSCore
import os

private let playerLog = CrashlyticsLogger(category: "Player")

// MARK: - Controls Overlay Visibility

extension PlaybackViewModel {

    public func showControls() {
        playerLog.debug("[controls] showControls — isScrubbing=\(self.isScrubbing)")
        controlsVisible = true
        scheduleControlsHide()
    }

    /// Cancels the auto-hide timer without hiding controls.
    /// Call this when an overlay (more menu, picker) opens so the transport
    /// controls remain visible behind the overlay for as long as it is open.
    public func cancelControlsHide() {
        playerLog.debug("[controls] cancelControlsHide — pausing auto-hide timer")
        controlsTimer?.cancel()
        controlsTimer = nil
    }

    func controlsOverlayVisibilityChanged(_ visible: Bool) {
        controlsOverlayVisible = visible
        if visible {
            cancelControlsHide()
        } else if controlsVisible {
            scheduleControlsHide()
        }
    }

    public func hideControls() {
        cancelControlsHide()
        controlsVisible = false
    }

    public func toggleControls() {
        playerLog.notice("[controls] toggleControls — controlsVisible=\(self.controlsVisible)")
        if controlsVisible {
            hideControls()
        } else {
            showControls()
        }
    }

    func scheduleControlsHide() {
        guard !controlsOverlayVisible else { return }
        // UI-testing: when --uitesting-show-controls is active, controls must never
        // auto-hide so XCUITest can always click player.nextBtn. Any call that restarts
        // the timer (e.g. from readyToPlay → showControls()) is suppressed here.
        #if !os(iOS)
        if ProcessInfo.processInfo.arguments.contains("--uitesting-show-controls") { return }
        #endif
        // Fix #125: in landscape (fullscreen), give the user 50% more time before controls
        // disappear. The default timeout (from AppSettings) is 4 s → 6 s in landscape.
        #if os(tvOS)
        let timeout = Double(settings.controlsHideTimeout)
        #else
        let timeout =
            isLandscape
            ? Double(settings.controlsHideTimeout) * 1.5
            : Double(settings.controlsHideTimeout)
        #endif
        playerLog.debug(
            "[controls] scheduleControlsHide — resetting \(timeout)s timer (landscape=\(self.isLandscape)), isScrubbing=\(self.isScrubbing)"
        )
        controlsTimer?.cancel()
        let sleep = controlsHideSleep
        controlsTimer = Task { [weak self] in
            try? await sleep(.seconds(timeout))
            guard let self else { return }
            playerLog.debug("[controls] timer fired — isCancelled=\(Task.isCancelled) isScrubbing=\(self.isScrubbing)")
            guard !Task.isCancelled else {
                playerLog.debug("[controls] hide suppressed (cancelled)")
                return
            }
            if !self.isScrubbing {
                playerLog.debug("[controls] hiding controls")
                self.controlsVisible = false
            } else {
                // Still scrubbing — commitScrub will call showControls when the user
                // lifts their finger, but reschedule as a safety net for edge cases.
                playerLog.debug("[controls] hide suppressed (still scrubbing) — rescheduling")
                self.scheduleControlsHide()
            }
        }
    }
}
