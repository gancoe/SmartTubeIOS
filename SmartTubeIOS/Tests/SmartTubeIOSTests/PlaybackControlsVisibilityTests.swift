import Foundation
import Testing

@testable import SmartTubeIOS

@Suite("Playback controls visibility")
@MainActor
struct PlaybackControlsVisibilityTests {
    @Test("Closing a picker restarts the configured hide timer")
    func closingPickerRestartsHideTimer() async {
        let clock = ControlsHideClock()
        let vm = PlaybackViewModel()
        vm.settings.controlsHideTimeout = 2
        vm.controlsHideSleep = clock.sleep
        vm.showControls()
        #expect(await clock.nextSleep() == .seconds(2))
        let originalTimer = vm.controlsTimer
        vm.controlsOverlayVisibilityChanged(true)
        clock.advance()
        await originalTimer?.value
        #expect(vm.controlsVisible)

        vm.controlsOverlayVisibilityChanged(false)
        #expect(vm.controlsTimer != nil)
        guard let restartedTimer = vm.controlsTimer else { return }
        #expect(await clock.nextSleep() == .seconds(2))
        clock.advance()
        await restartedTimer.value
        #expect(!vm.controlsVisible)
    }

    @Test("Playback controls stay visible while a picker is open")
    func showingControlsDoesNotStartTimerBehindPicker() async {
        let clock = ControlsHideClock()
        let vm = PlaybackViewModel()
        vm.controlsHideSleep = clock.sleep
        vm.controlsOverlayVisibilityChanged(true)
        vm.showControls()
        #expect(vm.controlsVisible)
        #expect(vm.controlsTimer == nil)
        vm.controlsOverlayVisibilityChanged(false)
        let timer = vm.controlsTimer
        _ = await clock.nextSleep()
        clock.advance()
        await timer?.value
        #expect(!vm.controlsVisible)
    }

    @Test("An old timer cannot hide newly shown controls")
    func canceledTimerCannotHideNewControls() async {
        let clock = ControlsHideClock()
        let vm = PlaybackViewModel()
        vm.controlsHideSleep = clock.sleep
        vm.showControls()
        _ = await clock.nextSleep()
        let oldTimer = vm.controlsTimer
        vm.hideControls()
        vm.showControls()
        let newTimer = vm.controlsTimer
        clock.advance()
        await oldTimer?.value
        #expect(vm.controlsVisible)
        _ = await clock.nextSleep()
        clock.advance()
        await newTimer?.value
        #expect(!vm.controlsVisible)
    }
}

@MainActor
private final class ControlsHideClock {
    private var pending: [CheckedContinuation<Void, Never>] = []
    private var durations: [Duration] = []
    private var waiter: CheckedContinuation<Duration, Never>?

    func sleep(_ duration: Duration) async throws {
        await withCheckedContinuation { continuation in
            pending.append(continuation)
            if let waiter {
                self.waiter = nil
                waiter.resume(returning: duration)
            } else {
                durations.append(duration)
            }
        }
    }

    func nextSleep() async -> Duration {
        if !durations.isEmpty { return durations.removeFirst() }
        return await withCheckedContinuation { waiter = $0 }
    }

    func advance() {
        let continuations = pending
        pending.removeAll()
        for continuation in continuations { continuation.resume() }
    }
}
