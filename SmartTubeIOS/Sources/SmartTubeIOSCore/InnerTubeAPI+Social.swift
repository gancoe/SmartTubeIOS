import Foundation
import os

private let tubeLog = Logger(subsystem: appSubsystem, category: "InnerTube")

// MARK: - Social interaction endpoints (like/dislike, next, comments)

extension InnerTubeAPI {

    // MARK: - Like / Dislike

    /// Sends a like for the given video (requires authentication).
    /// Mirrors Android's `LikeDislikePresenter` → `PostVideoAction.LIKE`.
    public func like(videoId: String) async throws {
        var body = makeBody(client: tvClientContext)
        body["target"] = ["videoId": videoId]
        _ = try await postTV(endpoint: "like/like", body: body)
    }

    /// Sends a dislike for the given video (requires authentication).
    /// Mirrors Android's `LikeDislikePresenter` → `PostVideoAction.DISLIKE`.
    public func dislike(videoId: String) async throws {
        var body = makeBody(client: tvClientContext)
        body["target"] = ["videoId": videoId]
        _ = try await postTV(endpoint: "like/dislike", body: body)
    }

    /// Removes any existing like or dislike for the given video (requires authentication).
    /// Mirrors Android's `LikeDislikePresenter` → `PostVideoAction.REMOVE_LIKE`.
    public func removeLike(videoId: String) async throws {
        var body = makeBody(client: tvClientContext)
        body["target"] = ["videoId": videoId]
        _ = try await postTV(endpoint: "like/removelike", body: body)
    }

    /// Adds a video to the authenticated user's Watch Later playlist (id "WL").
    /// Uses the TVHTML5 client's `browse_edit_playlist` endpoint with ACTION_ADD_VIDEO,
    /// mirroring the Android SmartTube `PlaylistPresenter` → `ACTION_ADD_VIDEO` flow.
    /// Requires authentication.
    public func addToWatchLater(videoId: String) async throws {
        var body = makeBody(client: tvClientContext)
        body["playlistId"] = "WL"
        body["actions"] = [["addedVideoId": videoId, "action": "ACTION_ADD_VIDEO"]]
        _ = try await postTV(endpoint: "browse/edit_playlist", body: body)
        tubeLog.notice("addToWatchLater videoId=\(videoId, privacy: .public)")
    }

    /// Removes a video from the authenticated user's Watch Later playlist (id \"WL\").
    ///
    /// Unlike `addToWatchLater` (which only needs the video ID), removal is keyed by
    /// `setVideoId` — the playlist-entry token from that video's `playlistVideoRenderer`
    /// (see `parsePlaylistVideoRenderer` in InnerTubeAPI+VideoRenderers.swift). A playlist
    /// can hold the same video more than once, so InnerTube's `ACTION_REMOVE_VIDEO` removes
    /// a specific *entry*, not "any entry with this video ID" — sending the raw video ID
    /// under a `removedVideoId` key (the previous behavior, #122) is not a field this action
    /// recognizes and the removal silently fails.
    /// Requires authentication.
    public func removeFromWatchLater(setVideoId: String) async throws {
        var body = makeBody(client: tvClientContext)
        body["playlistId"] = "WL"
        body["actions"] = [["setVideoId": setVideoId, "action": "ACTION_REMOVE_VIDEO"]]
        _ = try await postTV(endpoint: "browse/edit_playlist", body: body)
        tubeLog.notice("removeFromWatchLater setVideoId=\(setVideoId, privacy: .public)")
    }

    /// Adds a video to an arbitrary user playlist (#8). Same mechanics as `addToWatchLater`,
    /// generalized to any `playlistId` from `fetchUserPlaylists()`.
    /// Requires authentication.
    public func addToPlaylist(playlistId: String, videoId: String) async throws {
        var body = makeBody(client: tvClientContext)
        body["playlistId"] = playlistId
        body["actions"] = [["addedVideoId": videoId, "action": "ACTION_ADD_VIDEO"]]
        _ = try await postTV(endpoint: "browse/edit_playlist", body: body)
        tubeLog.notice("addToPlaylist playlistId=\(playlistId, privacy: .public) videoId=\(videoId, privacy: .public)")
    }

    /// Removes a video from an arbitrary user playlist (#8). Same mechanics as
    /// `removeFromWatchLater` — keyed by `setVideoId`, not the raw video ID (see that
    /// function's doc comment for why).
    /// Requires authentication.
    public func removeFromPlaylist(playlistId: String, setVideoId: String) async throws {
        var body = makeBody(client: tvClientContext)
        body["playlistId"] = playlistId
        body["actions"] = [["setVideoId": setVideoId, "action": "ACTION_REMOVE_VIDEO"]]
        _ = try await postTV(endpoint: "browse/edit_playlist", body: body)
        tubeLog.notice(
            "removeFromPlaylist playlistId=\(playlistId, privacy: .public) setVideoId=\(setVideoId, privacy: .public)"
        )
    }

    /// Sends a feed feedback signal to YouTube.
    /// Used for "Not interested", "Don't like this video", and "Don't recommend channel" —
    /// all three actions share this endpoint and differ only in their `feedbackToken`.
    /// Tokens are parsed from `videoRenderer.menu.menuRenderer.items` in the feed response.
    /// Requires authentication.
    public func sendFeedback(token: String) async throws {
        var body = makeBody(client: tvClientContext)
        body["feedbackTokens"] = [token]
        _ = try await postTV(endpoint: "feedback", body: body)
        tubeLog.notice("sendFeedback token=\(token.prefix(20), privacy: .public)…")
    }

    /// Sends a feed feedback signal when no pre-fetched token is available.
    ///
    /// The TV client home feed omits per-video feedback menu items, so
    /// `Video.notInterestedToken` / `dontLikeToken` / `hideChannelToken` are `nil`
    /// for authenticated home-feed results. This method fetches the token on-demand
    /// via a WEB client `/next` request for the given video, then calls `sendFeedback`.
    ///
    /// - Parameters:
    ///   - videoId: The YouTube video ID to act on.
    ///   - iconType: The InnerTube icon type string identifying the action:
    ///     `"NOT_INTERESTED"`, `"DISLIKE"`, or `"BLOCK_CHANNEL"`.
    ///
    /// If YouTube's response does not include a matching token, the method returns
    /// silently (it logs a warning but does not throw) so the caller's hide-from-feed
    /// notification can still be posted.
    public func sendFeedbackForVideo(videoId: String, iconType: String) async throws {
        var body = makeBody(client: webClientContext)
        body["videoId"] = videoId
        let nextData = try await post(endpoint: "next", body: body)
        guard let token = parseFeedbackToken(iconType: iconType, from: nextData) else {
            tubeLog.warning(
                "sendFeedbackForVideo: no \(iconType, privacy: .public) token in /next for videoId=\(videoId, privacy: .public)"
            )
            return
        }
        try await sendFeedback(token: token)
    }

    /// Walks a `/next` (WEB) response and returns the first `feedbackEndpoint` token
    /// whose `menuServiceItemRenderer.icon.iconType` matches `iconType`.
    private func parseFeedbackToken(iconType: String, from json: [String: Any]) -> String? {
        var found: String? = nil
        func walk(_ obj: Any, depth: Int = 0) {
            guard found == nil, depth < 50 else { return }
            if let dict = obj as? [String: Any] {
                if let svc = dict["menuServiceItemRenderer"] as? [String: Any],
                    let endpoint = svc["serviceEndpoint"] as? [String: Any],
                    let token = (endpoint["feedbackEndpoint"] as? [String: Any])?["feedbackToken"] as? String,
                    let type = (svc["icon"] as? [String: Any])?["iconType"] as? String,
                    type == iconType
                {
                    found = token
                    return
                }
                for value in dict.values { walk(value, depth: depth + 1) }
            } else if let arr = obj as? [Any] {
                for item in arr { walk(item, depth: depth + 1) }
            }
        }
        walk(json)
        return found
    }

    // MARK: - Next (related videos / SuggestionsController equivalent)

    /// Fetches related/suggested videos and the current like status for a video.
    /// When authenticated, uses TVHTML5 on youtubei.googleapis.com so the Bearer
    /// token is accepted and the response includes the user's current like state.
    /// Without auth, falls back to the WEB client (like status will be .none).
    /// Mirrors Android's SuggestionsController + LikeDislikePresenter.
    public func fetchNextInfo(videoId: String) async throws -> NextInfo {
        let isAuth = authToken != nil
        var tvBody = makeBody(client: isAuth ? tvClientContext : webClientContext)
        tvBody["videoId"] = videoId

        if isAuth {
            // TV client (/next) returns like status + related but omits
            // engagementPanels (where chapters live). Make a second sequential
            // WEB /next call to extract chapters — no auth needed.
            // (async let cannot be used here: [String:Any] is not Sendable in Swift 6.)
            var webBody = makeBody(client: webClientContext)
            webBody["videoId"] = videoId
            let tvData = try await postTV(endpoint: "next", body: tvBody)
            let webData = try await post(endpoint: "next", body: webBody)
            let videos = parseRelatedVideos(from: webData)  // WEB client has compactVideoRenderer; TV client does not
            let status = parseLikeStatus(from: tvData)
            let chapters = parseChapters(from: webData)
            tubeLog.notice(
                "fetchNextInfo (auth) → related=\(videos.count, privacy: .public) chapters=\(chapters.count, privacy: .public)"
            )
            return NextInfo(relatedVideos: videos, likeStatus: status, chapters: chapters)
        } else {
            let data = try await post(endpoint: "next", body: tvBody)
            let videos = parseRelatedVideos(from: data)
            let chapters = parseChapters(from: data)
            tubeLog.notice(
                "fetchNextInfo (anon) → related=\(videos.count, privacy: .public) chapters=\(chapters.count, privacy: .public)"
            )
            return NextInfo(relatedVideos: videos, likeStatus: .none, chapters: chapters)
        }
    }

    // MARK: - Comments

    /// Fetches a page of top-level comments for a video.
    /// The initial call bootstraps the comments continuation from `/next`; subsequent
    /// calls use exactly one `/next` request with the supplied continuation.
    public func fetchCommentsPage(videoId: String, continuation: String? = nil) async throws -> CommentPage {
        if let continuation {
            let data = try await post(
                endpoint: "next",
                body: makeBody(client: webClientContext, continuationToken: continuation))
            return parseCommentPage(from: data)
        }

        var body = makeBody(client: webClientContext)
        body["videoId"] = videoId
        let bootstrapData = try await post(endpoint: "next", body: body)
        guard let commentsToken = parseCommentsContinuationToken(from: bootstrapData) else {
            return CommentPage(comments: [])
        }
        let data = try await post(
            endpoint: "next",
            body: makeBody(client: webClientContext, continuationToken: commentsToken))
        return parseCommentPage(from: data)
    }

    /// Fetches one page of replies from a reply continuation.
    public func fetchCommentReplies(continuation: String) async throws -> CommentPage {
        let data = try await post(
            endpoint: "next",
            body: makeBody(client: webClientContext, continuationToken: continuation))
        return parseCommentPage(from: data)
    }

    /// Preserves the original comments API while using the paged parser.
    public func fetchComments(videoId: String) async throws -> [Comment] {
        try await fetchCommentsPage(videoId: videoId).comments
    }

    // MARK: - Private social parsers

    /// Parses the user's current like/dislike state from a `/next` response.
    ///
    /// Handles two layouts:
    /// - WEB client: `videoPrimaryInfoRenderer.likeStatus` → string "LIKE" / "DISLIKE" / "INDIFFERENT"
    /// - TV/WEB client: `segmentedLikeDislikeButtonRenderer.{like,dislike}Button.toggleButtonRenderer.isToggled`
    private func parseLikeStatus(from json: [String: Any]) -> LikeStatus {
        var found: LikeStatus? = nil
        func walk(_ obj: Any, depth: Int = 0) {
            guard found == nil else { return }
            guard depth < 50 else { return }
            if let dict = obj as? [String: Any] {
                // Strategy 1: direct likeStatus string (videoPrimaryInfoRenderer on WEB)
                if let statusStr = dict["likeStatus"] as? String {
                    switch statusStr {
                    case "LIKE": found = .like
                    case "DISLIKE": found = .dislike
                    default: found = LikeStatus.none
                    }
                    return
                }
                // Strategy 2: segmentedLikeDislikeButtonRenderer (WEB + TV clients)
                if let seg = dict["segmentedLikeDislikeButtonRenderer"] as? [String: Any] {
                    let liked =
                        (seg["likeButton"] as? [String: Any])
                        .flatMap { $0["toggleButtonRenderer"] as? [String: Any] }
                        .flatMap { $0["isToggled"] as? Bool } ?? false
                    let disliked =
                        (seg["dislikeButton"] as? [String: Any])
                        .flatMap { $0["toggleButtonRenderer"] as? [String: Any] }
                        .flatMap { $0["isToggled"] as? Bool } ?? false
                    found = liked ? .like : disliked ? .dislike : LikeStatus.none
                    return
                }
                for value in dict.values { walk(value, depth: depth + 1) }
            } else if let arr = obj as? [Any] {
                for item in arr { walk(item, depth: depth + 1) }
            }
        }
        walk(json)
        tubeLog.notice("parseLikeStatus → \(String(describing: found ?? .none), privacy: .public)")
        return found ?? .none
    }

    /// Parses related / suggested videos from a `/next` response.
    /// Related videos appear as `compactVideoRenderer` in `secondaryResults`.
    private func parseRelatedVideos(from json: [String: Any]) -> [Video] {
        var videos: [Video] = []
        var rendererKeysFound: Set<String> = []
        func walk(_ obj: Any, depth: Int = 0) {
            guard depth < 50 else { return }
            if let dict = obj as? [String: Any] {
                // Collect any *Renderer keys for diagnostics
                for k in dict.keys where k.hasSuffix("Renderer") { rendererKeysFound.insert(k) }
                if let r = dict["compactVideoRenderer"] as? [String: Any],
                    let v = parseVideoRenderer(r)
                {
                    videos.append(v)
                } else {
                    for value in dict.values { walk(value, depth: depth + 1) }
                }
            } else if let arr = obj as? [Any] {
                for item in arr { walk(item, depth: depth + 1) }
            }
        }
        walk(json)
        tubeLog.notice(
            "[parseRelatedVideos] found=\(videos.count, privacy: .public) rendererKeys=\(rendererKeysFound.sorted().joined(separator: ","), privacy: .public)"
        )
        return Array(videos.prefix(25))
    }

    /// Parses video chapters from a `/next` response.
    /// Chapters live in `engagementPanels[].engagementPanelSectionListRenderer
    ///   .content.macroMarkersListRenderer.contents[].macroMarkersListItemRenderer`.
    /// Each item carries a `title` text object and either
    ///   - `onTap.watchEndpoint.startTimeSeconds` (Int) — preferred, or
    ///   - `timeDescription` text object — fallback (parsed via `parseDuration`).
    private func parseChapters(from json: [String: Any]) -> [Chapter] {
        var chapters: [Chapter] = []
        func walk(_ obj: Any, depth: Int = 0) {
            guard depth < 50 else { return }
            if let dict = obj as? [String: Any] {
                if let renderer = dict["macroMarkersListItemRenderer"] as? [String: Any] {
                    let title = (renderer["title"] as? [String: Any]).flatMap { extractText($0) } ?? ""
                    // startTimeSeconds arrives as Int, Double, or NSNumber depending on
                    // how JSONSerialization bridges the JSON number — handle all three.
                    let startTime: TimeInterval? = {
                        if let watchEndpoint = (renderer["onTap"] as? [String: Any])
                            .flatMap({ $0["watchEndpoint"] as? [String: Any] })
                        {
                            let raw = watchEndpoint["startTimeSeconds"]
                            if let n = raw as? Int { return TimeInterval(n) }
                            if let n = raw as? Double { return n }
                            if let n = raw as? NSNumber { return n.doubleValue }
                            if let s = raw as? String { return TimeInterval(s) }
                        }
                        // Fallback: parse the visible time description (e.g. "1:23")
                        return (renderer["timeDescription"] as? [String: Any])
                            .flatMap { extractText($0) }
                            .flatMap { parseDuration($0) }
                    }()
                    if let t = startTime {
                        chapters.append(Chapter(title: title, startTime: t))
                    }
                    return
                }
                for value in dict.values { walk(value, depth: depth + 1) }
            } else if let arr = obj as? [Any] {
                for item in arr { walk(item, depth: depth + 1) }
            }
        }
        walk(json)
        return chapters.sorted { $0.startTime < $1.startTime }
    }

    // MARK: - Private: parseVideoRenderer passthrough
    // Social parsers (parseRelatedVideos) call parseVideoRenderer which lives in
    // InnerTubeAPI+VideoRenderers.swift. Because both files declare extensions on the
    // same actor, Swift resolves the call correctly at compile time.
}
