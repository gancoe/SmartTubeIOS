import AVFoundation
import Foundation
import SmartTubeIOSCore
import Testing

@testable import SmartTubeIOS

@Suite("Experimental player source handoff")
struct PlaybackEngineTrialSourceTests {
    @Test func acceptsOnlyTheActiveHLSSource() throws {
        let url = try #require(URL(string: "https://manifest.example.test/master.m3u8?session=current"))
        let source = PlaybackEngineTrialSource(url: url, headers: ["User-Agent": "test"], isHLS: true)
        #expect(source.matches(activeURL: url))
        #expect(!source.matches(activeURL: URL(string: "https://manifest.example.test/master.m3u8?session=old")))
        #expect(!source.matches(activeURL: nil))
    }

    @Test func rejectsCompositionAndNonHLSSources() throws {
        let url = try #require(URL(string: "https://media.example.test/video.mp4"))
        let source = PlaybackEngineTrialSource(url: url, headers: [:], isHLS: false)
        #expect(!source.matches(activeURL: url))
    }

    @Test func rejectsLocalAndInsecureSources() throws {
        for text in ["file:///tmp/video.m3u8", "http://media.example.test/master.m3u8"] {
            let url = try #require(URL(string: text))
            #expect(!PlaybackEngineTrialSource(url: url, headers: [:], isHLS: true).matches(activeURL: url))
        }
    }

    @Test @MainActor func engineHandoffReleasesAVItemAndCancelsPendingLoads() throws {
        let player = EngineTrialTestPlayer()
        let vm = PlaybackViewModel(player: player)
        let url = try #require(URL(string: "https://manifest.example.test/master.m3u8"))
        player.replaceCurrentItem(with: AVPlayerItem(asset: AVURLAsset(url: url)))
        vm.playbackEngineTrialSource = PlaybackEngineTrialSource(url: url, headers: ["User-Agent": "test"], isHLS: true)
        vm.isPlaying = true
        let pending = Task<Void, Never> {}
        vm.phase2Task = pending
        vm.parkedVideoId = "previous"
        #expect(vm.availableEngineTrialSource != nil)
        let proxyURL = try #require(url.proxyURL)
        player.replaceCurrentItem(with: AVPlayerItem(asset: AVURLAsset(url: proxyURL)))
        #expect(vm.availableEngineTrialSource?.url == url)

        vm.suspendForEngineTrial()

        #expect(player.currentItem == nil)
        #expect(!vm.isPlaying)
        #expect(pending.isCancelled)
        #expect(vm.phase2Task == nil)
        #expect(vm.parkedVideoId == nil)
        #expect(vm.availableEngineTrialSource == nil)
    }
}

private final class EngineTrialTestPlayer: AVPlayer {
    private var item: AVPlayerItem?
    override var currentItem: AVPlayerItem? { item }
    override func replaceCurrentItem(with item: AVPlayerItem?) { self.item = item }
    override func pause() {}
}
