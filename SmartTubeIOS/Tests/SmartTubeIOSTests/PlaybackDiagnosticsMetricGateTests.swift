import Foundation
import Testing

@testable import SmartTubeIOS

@Suite("Native diagnostic lifecycle")
@MainActor
struct PlaybackDiagnosticsMetricGateTests {
    @Test func duplicateAttachmentKeepsGeneration() throws {
        let gate = PlaybackDiagnosticsMetricGate()
        let owner = gate.activate()
        let player = NSObject(), item = NSObject()
        let first = try #require(gate.bind(ownerToken: owner, player: player, item: item, eligible: true))
        #expect(gate.bind(ownerToken: owner, player: player, item: item, eligible: true) == first)
    }

    @Test func replacementAndNilRejectOldEvents() throws {
        let gate = PlaybackDiagnosticsMetricGate()
        let owner = gate.activate()
        let player = NSObject(), oldItem = NSObject(), newItem = NSObject()
        let old = try #require(gate.bind(ownerToken: owner, player: player, item: oldItem, eligible: true))
        let new = try #require(gate.bind(ownerToken: owner, player: player, item: newItem, eligible: true))
        #expect(old != new)
        #expect(!gate.accepts(ownerToken: owner, generation: old, player: player, item: oldItem, eligible: true))
        gate.invalidateItem()
        #expect(!gate.accepts(ownerToken: owner, generation: new, player: player, item: newItem, eligible: true))
    }

    @Test func stoppedPlaybackCannotReattachParkedItem() {
        let gate = PlaybackDiagnosticsMetricGate()
        let owner = gate.activate()
        let player = NSObject(), item = NSObject()
        _ = gate.bind(ownerToken: owner, player: player, item: item, eligible: true)
        gate.suspend()
        #expect(gate.bind(ownerToken: owner, player: player, item: item, eligible: true) == nil)
        gate.resume()
        #expect(gate.bind(ownerToken: owner, player: player, item: item, eligible: true) != nil)
    }

    @Test func queuedCallbackCannotReviveCancelledOwner() {
        let gate = PlaybackDiagnosticsMetricGate()
        let oldOwner = gate.activate()
        gate.deactivate(ownerToken: oldOwner)
        let newOwner = gate.activate()
        let player = NSObject(), item = NSObject()
        #expect(gate.bind(ownerToken: oldOwner, player: player, item: item, eligible: true) == nil)
        gate.deactivate(ownerToken: oldOwner)
        #expect(gate.ownerToken == newOwner)
        #expect(gate.bind(ownerToken: newOwner, player: player, item: item, eligible: true) != nil)
    }

    @Test func playerReplacementRequiresNewGeneration() throws {
        let gate = PlaybackDiagnosticsMetricGate()
        let owner = gate.activate()
        let oldPlayer = NSObject(), newPlayer = NSObject(), item = NSObject()
        let old = try #require(gate.bind(ownerToken: owner, player: oldPlayer, item: item, eligible: true))
        let new = try #require(gate.bind(ownerToken: owner, player: newPlayer, item: item, eligible: true))
        #expect(old != new)
        #expect(!gate.accepts(ownerToken: owner, generation: old, player: oldPlayer, item: item, eligible: true))
    }

    @Test func expiredCaptureRejectsEventsWithoutWaitingForDelivery() throws {
        let gate = PlaybackDiagnosticsMetricGate()
        let owner = gate.activate()
        let player = NSObject(), item = NSObject()
        let generation = try #require(gate.bind(ownerToken: owner, player: player, item: item, eligible: true))
        #expect(!gate.accepts(ownerToken: owner, generation: generation, player: player, item: item, eligible: false))
        #expect(gate.bind(ownerToken: owner, player: player, item: item, eligible: false) == nil)
    }
}
