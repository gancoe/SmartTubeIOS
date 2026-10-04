import Foundation
import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

@Suite("Playback idle timer")
@MainActor
struct PlaybackIdleTimerTests {
    @Test("isPlaying transitions update the idle timer seam")
    func playingStateUpdatesIdleTimer() {
        let viewModel = PlaybackViewModel()
        viewModel.idleTimerLeaseEnabled = true
        var states: [Bool] = []
        viewModel.idleTimerSetter = { states.append($0) }

        viewModel.isPlaying = true
        viewModel.isPlaying = false

        #expect(states == [true, false])
    }

    @Test("natural playback end disables the idle timer")
    func playbackEndDisablesIdleTimer() {
        let viewModel = PlaybackViewModel()
        viewModel.idleTimerLeaseEnabled = true
        var states: [Bool] = []
        viewModel.idleTimerSetter = { states.append($0) }
        viewModel.settings.autoplayEnabled = false
        viewModel.isPlaying = true

        viewModel.handlePlaybackEnd()

        #expect(!viewModel.isPlaying)
        #expect(states == [true, false])
    }

    @Test("looping playback restores the idle timer after the end transition")
    func loopingPlaybackRestoresIdleTimer() {
        let viewModel = PlaybackViewModel()
        viewModel.idleTimerLeaseEnabled = true
        var states: [Bool] = []
        viewModel.idleTimerSetter = { states.append($0) }
        viewModel.settings.loopEnabled = true
        viewModel.isPlaying = true

        viewModel.handlePlaybackEnd()

        #expect(viewModel.isPlaying)
        #expect(states == [true, false, true])
    }

    @Test("an old playback owner cannot disable a replacement owner's idle timer")
    func replacementOwnerKeepsLease() {
        let first = PlaybackViewModel()
        let second = PlaybackViewModel()
        first.idleTimerLeaseEnabled = true
        second.idleTimerLeaseEnabled = true
        var firstStates: [Bool] = []
        var secondStates: [Bool] = []
        first.idleTimerSetter = { firstStates.append($0) }
        second.idleTimerSetter = { secondStates.append($0) }

        first.setPlaybackIdleTimerDisabled(true)
        second.setPlaybackIdleTimerDisabled(true)
        first.setPlaybackIdleTimerDisabled(false)
        second.setPlaybackIdleTimerDisabled(false)

        #expect(firstStates == [true])
        #expect(secondStates == [true, false])
    }

    @Test("lease release ignores stale tokens and clears the current owner")
    func releaseLeaseChecksToken() {
        let owner = PlaybackViewModel()
        owner.idleTimerLeaseEnabled = true
        owner.setPlaybackIdleTimerDisabled(true)
        let currentToken = owner.idleTimerOwnerToken
        let staleToken = UUID()

        PlaybackViewModel.releaseIdleTimerLease(for: staleToken)
        #expect(PlaybackViewModel.activeIdleTimerOwnerToken == currentToken)

        PlaybackViewModel.releaseIdleTimerLease(for: currentToken)
        #expect(PlaybackViewModel.activeIdleTimerOwnerToken == nil)
    }
}
