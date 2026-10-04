import Foundation

@MainActor
final class PlaybackDiagnosticsMetricGate {
    private(set) var ownerToken: UUID?
    private(set) var generation: UUID?
    private var playerID: ObjectIdentifier?
    private var itemID: ObjectIdentifier?
    private(set) var suspended = false

    func activate() -> UUID {
        let token = UUID()
        ownerToken = token
        invalidateItem()
        return token
    }

    func deactivate(ownerToken token: UUID) {
        guard ownerToken == token else { return }
        ownerToken = nil
        invalidateItem()
    }

    func suspend() {
        suspended = true
        invalidateItem()
    }

    func resume() { suspended = false }

    func invalidateItem() {
        playerID = nil
        itemID = nil
        generation = nil
    }

    func bind(ownerToken token: UUID, player: AnyObject, item: AnyObject, eligible: Bool) -> UUID? {
        guard ownerToken == token, !suspended, eligible else { return nil }
        let playerIdentity = ObjectIdentifier(player)
        let itemIdentity = ObjectIdentifier(item)
        if playerID == playerIdentity, itemID == itemIdentity { return generation }
        playerID = playerIdentity
        itemID = itemIdentity
        generation = UUID()
        return generation
    }

    func accepts(
        ownerToken token: UUID, generation value: UUID, player: AnyObject, item: AnyObject, eligible: Bool
    ) -> Bool {
        ownerToken == token && generation == value && !suspended && eligible
            && playerID == ObjectIdentifier(player) && itemID == ObjectIdentifier(item)
    }
}
