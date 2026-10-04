#if DEBUG && os(tvOS)
import Foundation
import SmartTubeIOSCore

private actor ChannelUITestAPI: InnerTubeAPIProtocol {
    private static let channelId = "UCNativePlayerTest"
    private static let channelTitle = "Test Creator"

    private static let channel = Channel(
        id: channelId,
        title: channelTitle
    )

    private static let videos = (1...8).map { index in
        Video(
            id: "native-channel-video-\(index)",
            title: "Creator video \(index)",
            channelTitle: channelTitle,
            channelId: channelId
        )
    }

    func setAuthToken(_ token: String?) {}

    func setSAPISID(_ value: String?) {}

    func fetchHome(continuationToken: String?) throws -> VideoGroup {
        VideoGroup()
    }

    func fetchHomeRows(continuationToken: String?) throws -> [VideoGroup] {
        []
    }

    func fetchSubscriptions(continuationToken: String?) throws -> VideoGroup {
        VideoGroup()
    }

    func fetchHistory(continuationToken: String?) throws -> VideoGroup {
        VideoGroup()
    }

    func fetchShorts() throws -> VideoGroup {
        VideoGroup()
    }

    func fetchShortsMore(continuationToken: String) throws -> VideoGroup {
        VideoGroup()
    }

    func fetchMusic() throws -> VideoGroup {
        VideoGroup()
    }

    func fetchGaming() throws -> VideoGroup {
        VideoGroup()
    }

    func fetchNews() throws -> VideoGroup {
        VideoGroup()
    }

    func fetchLive() throws -> VideoGroup {
        VideoGroup()
    }

    func fetchSports() throws -> VideoGroup {
        VideoGroup()
    }

    func fetchUserPlaylists() throws -> [PlaylistInfo] {
        []
    }

    func fetchSubscribedChannels() throws -> [Channel] {
        []
    }

    func fetchChannelThumbnailURL(channelId: String) throws -> URL? {
        nil
    }

    func fetchChannel(channelId: String) throws -> (channel: Channel, videos: VideoGroup) {
        (Self.channel, VideoGroup(title: Self.channelTitle, videos: Self.videos))
    }

    func fetchChannelVideos(channelId: String, continuationToken: String?) throws -> VideoGroup {
        VideoGroup()
    }

    func search(query: String, continuationToken: String?, filter: SearchFilter) throws -> VideoGroup {
        VideoGroup()
    }

    func fetchSearchSuggestions(query: String) throws -> [String] {
        []
    }

    func fetchPlaylistVideos(playlistId: String, continuationToken: String?) throws -> VideoGroup {
        VideoGroup()
    }

    func addToWatchLater(videoId: String) throws {}

    func removeFromWatchLater(setVideoId: String) throws {}

    func addToPlaylist(playlistId: String, videoId: String) throws {}

    func removeFromPlaylist(playlistId: String, setVideoId: String) throws {}

    func sendFeedback(token: String) throws {}

    func sendFeedbackForVideo(videoId: String, iconType: String) throws {}
}

extension ChannelView {
    static func uiTestAPIIfRequested() -> (any InnerTubeAPIProtocol)? {
        guard ProcessInfo.processInfo.arguments.contains("--uitesting-channel-content") else { return nil }
        return ChannelUITestAPI()
    }
}
#endif
