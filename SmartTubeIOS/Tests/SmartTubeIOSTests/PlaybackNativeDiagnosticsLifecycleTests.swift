import AVFoundation
import Foundation
import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

@Suite("Native diagnostic owner", .serialized)
@MainActor
struct PlaybackNativeDiagnosticsLifecycleTests {
    @Test func duplicateStartAndCancelledCallbackCannotReattach() throws {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, *) else { return }
        let fixture = try Fixture()
        defer { fixture.finish() }
        let vm = fixture.vm
        vm.startPlaybackDiagnosticsNativeMetrics(
            for: fixture.item, reporter: fixture.reporter,
            captureID: fixture.session.captureID, ownerToken: fixture.owner)
        let generation = try #require(vm.playbackDiagnosticsItemGenerationID)
        #expect(vm.playbackDiagnosticsMetricTasks.count == 2)
        vm.startPlaybackDiagnosticsNativeMetrics(
            for: fixture.item, reporter: fixture.reporter,
            captureID: fixture.session.captureID, ownerToken: fixture.owner)
        #expect(vm.playbackDiagnosticsItemGenerationID == generation)
        let tasks = vm.playbackDiagnosticsMetricTasks
        vm.endPlaybackDiagnosticsOwner(ownerToken: fixture.owner)
        let cancelled = tasks.allSatisfy { $0.isCancelled }
        #expect(cancelled)
        vm.startPlaybackDiagnosticsNativeMetrics(
            for: fixture.item, reporter: fixture.reporter,
            captureID: fixture.session.captureID, ownerToken: fixture.owner)
        #expect(vm.playbackDiagnosticsMetricTasks.isEmpty)
    }

    @Test func staleErrorCannotShortenCaptureAndNativeChronologyIsPreserved() throws {
        let fixture = try Fixture()
        defer { fixture.finish() }
        let vm = fixture.vm
        let generation = try #require(
            vm.playbackDiagnosticsMetricGate.bind(
                ownerToken: fixture.owner, player: vm.player, item: fixture.item, eligible: true))
        let timestamp = fixture.session.startedAt.addingTimeInterval(3)
        let mediaTime = CMTime(seconds: 47, preferredTimescale: 600)
        let event = try #require(
            vm.nativePlaybackDiagnosticsEvent(
                ownerToken: fixture.owner, generation: generation, source: (vm.player, fixture.item),
                timestamp: timestamp, mediaTime: mediaTime))
        #expect(event.timestamp == timestamp)
        #expect(event.playbackPositionSeconds == 47)
        #expect(event.itemGenerationID == generation)
        #expect(event.videoID == "native-test")
        let deadline = fixture.session.endsAt
        let stale = AVPlayerItem(url: URL(fileURLWithPath: "/dev/null"))
        #expect(
            vm.nativePlaybackDiagnosticsEvent(
                ownerToken: fixture.owner, generation: generation, source: (vm.player, stale), timestamp: timestamp,
                mediaTime: mediaTime,
                errorDomain: "CoreMediaErrorDomain", errorCode: -12_889) == nil)
        #expect(fixture.session.endsAt == deadline)
        #expect(fixture.session.state == .active)
    }

    @Test func stopBlocksMetricRestartAndPlayerReplacementCancelsOldTasks() throws {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, *) else { return }
        let fixture = try Fixture()
        defer { fixture.finish() }
        let vm = fixture.vm
        vm.startPlaybackDiagnosticsNativeMetrics(
            for: fixture.item, reporter: fixture.reporter,
            captureID: fixture.session.captureID, ownerToken: fixture.owner)
        let tasks = vm.playbackDiagnosticsMetricTasks
        vm.player = AVPlayer()
        let cancelled = tasks.allSatisfy { $0.isCancelled }
        #expect(cancelled)
        #expect(vm.playbackDiagnosticsItemGenerationID == nil)
        let parkedItem = ReadyDiagnosticItem(url: URL(fileURLWithPath: "/dev/null"))
        vm.player.replaceCurrentItem(with: parkedItem)
        vm.stop()
        #expect(vm.player.currentItem === parkedItem)
        vm.startPlaybackDiagnosticsNativeMetrics(
            for: parkedItem, reporter: fixture.reporter,
            captureID: fixture.session.captureID, ownerToken: fixture.owner)
        #expect(vm.playbackDiagnosticsMetricTasks.isEmpty)
    }

    @Test func expiryCancelsSubscriptionsWhileDeliveryIsBlocked() async throws {
        let transport = BlockedDiagnosticTransport()
        let fixture = try Fixture(transport: transport)
        defer { fixture.finish() }
        let vm = fixture.vm
        let generation = try #require(
            vm.playbackDiagnosticsMetricGate.bind(
                ownerToken: fixture.owner, player: vm.player, item: fixture.item, eligible: true))
        let metricTask = Task<Void, Never> {}
        vm.playbackDiagnosticsMetricTasks = [metricTask]
        let event = try #require(
            vm.nativePlaybackDiagnosticsEvent(
                ownerToken: fixture.owner, generation: generation, source: (vm.player, fixture.item), timestamp: Date(),
                mediaTime: .zero))
        let delivery = Task {
            await fixture.reporter.enqueue([event])
            await fixture.reporter.flush()
        }
        await transport.waitUntilStarted()
        vm.expirePlaybackDiagnosticsCapture(ownerToken: fixture.owner, at: fixture.session.endsAt)
        #expect(metricTask.isCancelled)
        #expect(vm.playbackDiagnosticsMetricGate.ownerToken == nil)
        #expect(vm.playbackDiagnosticsMetricTasks.isEmpty)
        #expect(fixture.session.state == .ended)
        await transport.release()
        await delivery.value
    }

    @Test func monitorCancellationStopsSubscriptionsBeforeBlockedDeliveryResumes() async throws {
        let transport = BlockedDiagnosticTransport()
        let fixture = try Fixture(transport: transport)
        defer { fixture.finish() }
        let configuration = await fixture.reporter.configuration
        let monitor = Task {
            await fixture.vm.monitorPlaybackDiagnostics(
                configuration: configuration, cache: fixture.root, stateRoot: fixture.root)
        }
        await transport.waitUntilStarted()
        let tasks = fixture.vm.playbackDiagnosticsMetricTasks
        #expect(tasks.count == 2)
        monitor.cancel()
        for _ in 0..<100 {
            if fixture.vm.playbackDiagnosticsMetricGate.ownerToken == nil { break }
            await Task.yield()
        }
        #expect(fixture.vm.playbackDiagnosticsMetricGate.ownerToken == nil)
        #expect(fixture.vm.playbackDiagnosticsMetricTasks.isEmpty)
        let cancelled = tasks.allSatisfy { $0.isCancelled }
        #expect(cancelled)
        await transport.release()
        await monitor.value
    }

    @MainActor
    private struct Fixture {
        let root: URL
        let vm: PlaybackViewModel
        let item: AVPlayerItem
        let session: PlaybackDiagnosticsCaptureSession
        let reporter: PlaybackDiagnosticsReporter
        let owner: UUID

        init(transport: any PlaybackDiagnosticsTransport = BlockedDiagnosticTransport()) throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            item = AVPlayerItem(url: URL(fileURLWithPath: "/dev/null"))
            vm = PlaybackViewModel(player: AVPlayer(playerItem: item))
            vm.currentVideo = Video(id: "native-test", title: "Test", channelTitle: "Test")
            session = PlaybackDiagnosticsCaptureSession(
                captureID: UUID(), stateURL: root.appendingPathComponent("capture.json"))
            let configuration = try #require(
                PlaybackDiagnosticsConfiguration(
                    endpoint: URL(string: "http://127.0.0.1:8765/v1/events")!,
                    token: String(repeating: "T", count: 32), captureID: session.captureID))
            reporter = PlaybackDiagnosticsReporter(
                configuration: configuration, storeURL: root.appendingPathComponent("pending.json"),
                transport: transport)
            vm.playbackDiagnosticsReporter = reporter
            vm.playbackDiagnosticsCaptureSession = session
            owner = vm.playbackDiagnosticsMetricGate.activate()
        }

        func finish() {
            vm.endPlaybackDiagnosticsOwner(ownerToken: owner)
            vm.stop()
            try? FileManager.default.removeItem(at: root)
        }
    }
}

private final class ReadyDiagnosticItem: AVPlayerItem {
    override var status: AVPlayerItem.Status { .readyToPlay }
}

private actor BlockedDiagnosticTransport: PlaybackDiagnosticsTransport {
    private var started = false
    private var released = false
    private var waiter: CheckedContinuation<Void, Never>?
    private var response: CheckedContinuation<PlaybackDiagnosticsTransportResponse, Never>?

    func send(_ request: URLRequest) async throws -> PlaybackDiagnosticsTransportResponse {
        if released { return PlaybackDiagnosticsTransportResponse(statusCode: 200) }
        started = true
        waiter?.resume()
        waiter = nil
        return await withCheckedContinuation { response = $0 }
    }

    func waitUntilStarted() async {
        if !started { await withCheckedContinuation { waiter = $0 } }
    }

    func release() {
        released = true
        response?.resume(returning: PlaybackDiagnosticsTransportResponse(statusCode: 200))
        response = nil
    }
}
