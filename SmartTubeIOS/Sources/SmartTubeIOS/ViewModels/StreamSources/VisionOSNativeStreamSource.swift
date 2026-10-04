import Foundation
import SmartTubeIOSCore

@MainActor
internal struct VisionOSNativeStreamSource {
    static func allowsNativeVP9Attempt(
        requestedQuality: AppSettings.VideoQuality,
        hardwareSupported: Bool,
        supplementalRequested: Bool,
        rejected: Bool
    ) -> Bool {
        requestedQuality == .q2160 && hardwareSupported && supplementalRequested && !rejected
    }

    let supportsNativeVP9: Bool
    private let fetch: @MainActor @Sendable () async throws -> PlayerInfo
    private let attemptHLS: @MainActor @Sendable (PlayerInfo, String) async -> Bool
    private let attemptFallback: @MainActor @Sendable (PlayerInfo, String) async -> Bool

    init(
        supportsNativeVP9: Bool,
        fetch: @escaping @MainActor @Sendable () async throws -> PlayerInfo,
        attemptHLS: @escaping @MainActor @Sendable (PlayerInfo, String) async -> Bool,
        attemptFallback: @escaping @MainActor @Sendable (PlayerInfo, String) async -> Bool
    ) {
        self.supportsNativeVP9 = supportsNativeVP9
        self.fetch = fetch
        self.attemptHLS = attemptHLS
        self.attemptFallback = attemptFallback
    }

    func resolve() async throws -> Bool {
        let info = try await fetch()
        try Task.checkCancellation()

        if supportsNativeVP9, info.hlsURL != nil {
            if await attemptHLS(info, "VisionOS/Native4K/HLS") {
                return true
            }
            try Task.checkCancellation()
        }

        try Task.checkCancellation()
        return await attemptFallback(info, "VisionOS")
    }
}
