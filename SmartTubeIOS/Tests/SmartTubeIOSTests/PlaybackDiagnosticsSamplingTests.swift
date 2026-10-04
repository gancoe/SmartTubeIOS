import Foundation
import Testing

@testable import SmartTubeIOS

@Suite("Playback diagnostics sampling")
struct PlaybackDiagnosticsSamplingTests {
    @Test("hidden-overlay sampling records state changes and a bounded heartbeat")
    func samplesChangesAndHeartbeat() {
        let item = NSObject()
        let start = Date(timeIntervalSince1970: 1_000)
        var sampler = PlaybackDiagnosticsSampler()
        let first = sampler.sample(itemID: ObjectIdentifier(item), errorCount: 0, state: "4K|1.5|playing", at: start)
        #expect(first.emitSnapshot)
        #expect(first.errorIndices.isEmpty)
        #expect(
            !sampler.sample(
                itemID: ObjectIdentifier(item), errorCount: 0, state: "4K|1.5|playing", at: start.addingTimeInterval(2)
            ).emitSnapshot)
        #expect(
            sampler.sample(
                itemID: ObjectIdentifier(item), errorCount: 0, state: "480p|1.5|playing",
                at: start.addingTimeInterval(4)
            ).emitSnapshot)
        #expect(
            sampler.sample(
                itemID: ObjectIdentifier(item), errorCount: 0, state: "480p|1.5|playing",
                at: start.addingTimeInterval(19)
            ).emitSnapshot)
    }

    @Test("all new native errors are captured once, including when the item changes on the same video")
    func samplesEveryNewError() {
        let firstItem = NSObject()
        let nextItem = NSObject()
        let now = Date(timeIntervalSince1970: 1_000)
        var sampler = PlaybackDiagnosticsSampler()
        _ = sampler.sample(itemID: ObjectIdentifier(firstItem), errorCount: 0, state: "playing", at: now)
        #expect(
            sampler.sample(itemID: ObjectIdentifier(firstItem), errorCount: 3, state: "playing", at: now).errorIndices
                == 0..<3)
        #expect(
            sampler.sample(itemID: ObjectIdentifier(firstItem), errorCount: 3, state: "playing", at: now).errorIndices
                .isEmpty)
        #expect(
            sampler.sample(itemID: ObjectIdentifier(firstItem), errorCount: 4, state: "playing", at: now).errorIndices
                == 3..<4)
        #expect(
            sampler.sample(itemID: ObjectIdentifier(nextItem), errorCount: 2, state: "playing", at: now).errorIndices
                == 0..<2)
    }
}
