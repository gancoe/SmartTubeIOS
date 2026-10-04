import Foundation

struct PlaybackDiagnosticsSampler {
    struct Decision {
        let emitSnapshot: Bool
        let errorIndices: Range<Int>
    }

    static let interval: Duration = .seconds(2)
    static let heartbeatSeconds: TimeInterval = 15
    private var previousItem: ObjectIdentifier?
    private var previousErrorCount = 0
    private var previousState: String?
    private var lastSnapshotDate: Date?

    mutating func sample(itemID: ObjectIdentifier, errorCount: Int, state: String, at now: Date) -> Decision {
        if previousItem != itemID || errorCount < previousErrorCount {
            previousItem = itemID
            previousErrorCount = 0
            previousState = nil
            lastSnapshotDate = nil
        }
        let count = max(0, errorCount)
        let newErrors = previousErrorCount..<count
        let emitSnapshot =
            previousState != state
            || lastSnapshotDate.map { now.timeIntervalSince($0) >= Self.heartbeatSeconds } != false
        previousErrorCount = count
        previousState = state
        if emitSnapshot { lastSnapshotDate = now }
        return Decision(emitSnapshot: emitSnapshot, errorIndices: newErrors)
    }
}
