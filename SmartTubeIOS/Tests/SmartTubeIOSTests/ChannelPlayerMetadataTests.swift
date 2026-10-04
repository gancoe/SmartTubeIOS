import Testing

@testable import SmartTubeIOSCore

private func makePlayerResponse(videoDetails: [String: Any]) -> [String: Any] {
    [
        "videoDetails": videoDetails,
        "streamingData": [
            "hlsManifestUrl": "https://example.com/video.m3u8"
        ],
    ]
}

@Suite("Player channel metadata")
struct ChannelPlayerMetadataTests {

    @Test("preserves videoDetails channel ID on PlayerInfo.video")
    func preservesChannelID() async throws {
        let response = makePlayerResponse(videoDetails: [
            "title": "Test video",
            "author": "Test channel",
            "channelId": "UCcreator123",
        ])

        let info = try await InnerTubeAPI().parsePlayerInfo(from: response, videoId: "video123")

        #expect(info.video.channelId == "UCcreator123")
    }

    @Test("leaves video channel ID nil when videoDetails omits it")
    func missingChannelIDRemainsNil() async throws {
        let response = makePlayerResponse(videoDetails: [
            "title": "Test video",
            "author": "Test channel",
        ])

        let info = try await InnerTubeAPI().parsePlayerInfo(from: response, videoId: "video123")

        #expect(info.video.channelId == nil)
    }

    @Test("leaves video channel ID nil when videoDetails contains only whitespace")
    func blankChannelIDRemainsNil() async throws {
        let response = makePlayerResponse(videoDetails: [
            "title": "Test video",
            "author": "Test channel",
            "channelId": " \n\t",
        ])

        let info = try await InnerTubeAPI().parsePlayerInfo(from: response, videoId: "video123")

        #expect(info.video.channelId == nil)
    }
}
