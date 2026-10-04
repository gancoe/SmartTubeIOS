import AVFoundation
import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

@Suite("Playback prefetch")
@MainActor
struct PlaybackPrefetchTests {
    @Test("HLS does not start progressive prefetch with or without adaptive audio", arguments: [false, true])
    func hlsDoesNotStartProgressivePrefetch(hasAdaptiveAudio: Bool) {
        let viewModel = makeViewModel()
        defer { viewModel.stop() }
        let info = makeInfo(hls: true, hasAdaptiveAudio: hasAdaptiveAudio)

        viewModel.launchPhase2(video: info.video, info: info, isHLSPlayback: true)

        #expect(viewModel.prefetchTask == nil)
        #expect(viewModel.phase2Task != nil)
    }

    @Test("starting HLS cancels and releases an older prefetch task")
    func hlsCancelsOlderPrefetch() {
        let viewModel = makeViewModel()
        defer { viewModel.stop() }
        let oldTask = Task<Void, Never> {}
        viewModel.prefetchTask = oldTask
        let info = makeInfo(hls: true, hasAdaptiveAudio: true)

        viewModel.launchPhase2(video: info.video, info: info, isHLSPlayback: true)

        #expect(oldTask.isCancelled)
        #expect(viewModel.prefetchTask == nil)
    }

    @Test("a progressive route still schedules track prefetch", arguments: [false, true])
    func nonHLSStillPrefetches(hasAdaptiveAudio: Bool) {
        let viewModel = makeViewModel()
        defer { viewModel.stop() }
        let info = makeInfo(hls: false, hasAdaptiveAudio: hasAdaptiveAudio)

        viewModel.launchPhase2(video: info.video, info: info)

        #expect(viewModel.prefetchTask != nil)
    }

    @Test("a progressive fallback still schedules prefetch when its metadata also includes HLS")
    func progressiveFallbackStillSchedulesPrefetch() {
        let viewModel = makeViewModel()
        defer { viewModel.stop() }
        let info = makeInfo(hls: true, hasAdaptiveAudio: true)

        viewModel.launchPhase2(video: info.video, info: info, isHLSPlayback: false)

        #expect(viewModel.prefetchTask != nil)
    }

    private func makeViewModel() -> PlaybackViewModel {
        var settings = AppSettings()
        settings.preferredQuality = .q1080
        return PlaybackViewModel(settings: settings)
    }

    private func makeInfo(hls: Bool, hasAdaptiveAudio: Bool) -> PlayerInfo {
        let video = Video(id: "prefetch-test", title: "Test", channelTitle: "Test")
        let audio = VideoFormat(
            label: "Audio", width: 0, height: 0, fps: 0,
            mimeType: "audio/mp4", url: URL(fileURLWithPath: "/dev/null"))
        let videoFormat = VideoFormat(
            label: "1080p", width: 1920, height: 1080, fps: 30,
            mimeType: "video/mp4", url: URL(fileURLWithPath: "/dev/null"))
        return PlayerInfo(
            video: video, formats: hasAdaptiveAudio ? [audio, videoFormat] : [],
            hlsURL: hls ? URL(fileURLWithPath: "/test.m3u8") : nil,
            dashURL: nil, captionTracks: [], trackingURLs: nil, endCards: [])
    }
}
