import AVFoundation
import SmartTubeIOSCore

private let playerLog = CrashlyticsLogger(category: "Player")

extension PlaybackViewModel {
    func hlsPhase2(video: Video, info: PlayerInfo, cached: CachedVideoData? = nil) {
        launchPhase2(video: video, info: info, cached: cached, isHLSPlayback: true)
    }

    func launchPhase2(
        video: Video, info: PlayerInfo, cached: CachedVideoData? = nil, isHLSPlayback: Bool = false
    ) {
        phase2Task?.cancel()
        phase2Task = Task(priority: .utility) { [weak self] in
            // Use the caller-supplied cached data when available so Phase 2 can use
            // already-consumed nextInfo/endCards/sponsorSegments instead of re-fetching.
            // Falls back to empty (full network fetch) when no cached data is passed
            // (e.g. from the 3-attempt retry loop which doesn't have the original cached struct).
            let p2Cached =
                cached
                ?? CachedVideoData(
                    playerInfo: nil, trackingURLs: nil, nextInfo: nil,
                    endCards: nil, sponsorSegments: nil, deArrowBranding: nil,
                    staleFields: []
                )
            await self?.loadAsyncPhase2(
                video: video, cached: p2Cached, info: info,
                cachedTrackingURLs: cached?.trackingURLs ?? nil, authTrackingTask: nil,
                sponsorCached: cached?.sponsorSegments != nil
            )
        }
        // Background pre-warming runs alongside phase2:
        //  • muxed fallback → fetch AndroidVR playerInfo so quality-tap skips 403 recovery
        //  • adaptive playing → pre-warm tracks for the user's preferred quality tier
        prefetchTask?.cancel()
        prefetchTask = nil
        if !isHLSPlayback && info.bestAdaptiveAudioURL == nil {
            prefetchTask = Task(priority: .utility) { [weak self] in
                await self?.fetchAndCacheAdaptivePlayerInfo(video: video, muxedInfo: info)
            }
        } else if !isHLSPlayback && settings.preferredQuality != .auto {
            prefetchTask = Task(priority: .utility) { [weak self] in
                await self?.prefetchPreferredQualityTracks(info: info)
            }
        }
    }

    /// Called from `launchPhase2` when muxed 360p is the only available stream
    /// (`info.bestAdaptiveAudioURL == nil`).  Fetches AndroidVR player info in the
    /// background and upgrades `self.playerInfo` so that the first quality-tap skips
    /// the 17-second 403-recovery cycle.
    private func fetchAndCacheAdaptivePlayerInfo(video: Video, muxedInfo: PlayerInfo) async {
        playerLog.notice("[prefetch] muxed fallback — fetching AndroidVR playerInfo in background")
        do {
            let vrInfo = try await api.fetchPlayerInfoAndroidVR(videoId: video.id)
            guard !Task.isCancelled else { return }
            guard vrInfo.bestAdaptiveAudioURL != nil else {
                playerLog.notice("[prefetch] AndroidVR returned no adaptive audio — playerInfo not upgraded")
                return
            }
            guard currentVideo?.id == video.id, playerInfo?.bestAdaptiveAudioURL == nil else {
                playerLog.notice("[prefetch] playerInfo already upgraded or video changed — discarding prefetch result")
                return
            }
            playerInfo = vrInfo
            let vrFormats = Self.deduplicatedVideoFormats(vrInfo.formats)
            let maxCurrentH = availableFormats.map(\.height).max() ?? 0
            let maxVRH = vrFormats.map(\.height).max() ?? 0
            // Only update availableFormats (quality-picker options) when at least one format
            // is rqh-free. rqh=1 formats are immediately reverted by reloadDASHItem's rqh guard
            // and should not appear in the picker.
            let hasRqhFreeFormat = vrFormats.contains { fmt in
                guard let url = fmt.url else { return false }
                return !PlaybackQualityManager.urlHasRqhEnforcement(url)
            }
            if hasRqhFreeFormat && (vrFormats.count > availableFormats.count || maxVRH > maxCurrentH) {
                availableFormats = vrFormats
            }
            playerLog.notice(
                "⚡ [prefetch] playerInfo upgraded to AndroidVR (\(vrFormats.count) formats) — quality switches skip 403 recovery"
            )
            await prefetchPreferredQualityTracks(info: vrInfo)
        } catch {
            playerLog.notice("[prefetch] background AndroidVR fetch failed: \(error)")
        }
    }

    /// Pre-loads `AVAssetTrack` arrays for `settings.preferredQuality` into
    /// `AVAssetTrackCache` so that the first quality-tap after initial playback
    /// is a cache hit rather than a CDN round-trip.
    private func prefetchPreferredQualityTracks(info: PlayerInfo) async {
        guard settings.preferredQuality != .auto,
            let maxH = settings.preferredQuality.maxHeight
        else { return }
        guard
            let videoURL = PlaybackQualityManager.selectBestVideoFormat(
                from: info.formats, preferredMaxHeight: maxH,
                preferH264: settings.preferH264
            )?.url,
            let audioURL = info.bestAdaptiveAudioURL
        else { return }
        if AVAssetTrackCache.shared.videoTracks(for: videoURL) != nil { return }
        let itag =
            URLComponents(url: videoURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "itag" })?.value ?? "?"
        let ua = InnerTubeClients.iOS.userAgent
        let videoAsset = AVURLAsset(url: videoURL, options: ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": ua]])
        let audioAsset = AVURLAsset(url: audioURL, options: ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": ua]])
        playerLog.notice("[prefetch] pre-warming tracks for preferredQuality=\(maxH)p (itag=\(itag))")
        struct PrefetchTrackBox: @unchecked Sendable {
            let video: [AVAssetTrack]
            let audio: [AVAssetTrack]
        }
        let (stream, cont) = AsyncStream<PrefetchTrackBox?>.makeStream()
        Task.detached {
            let box: PrefetchTrackBox? = try? await { () async throws -> PrefetchTrackBox in
                async let videoTracks = videoAsset.loadTracks(withMediaType: .video)
                async let audioTracks = audioAsset.loadTracks(withMediaType: .audio)
                let (vv, aa) = try await (videoTracks, audioTracks)
                return PrefetchTrackBox(video: vv, audio: aa)
            }()
            cont.yield(box)
            cont.finish()
        }
        Task.detached {
            try? await Task.sleep(for: .seconds(60))
            cont.yield(nil)
            cont.finish()
        }
        if let result = await stream.first(where: { @Sendable _ in true }),
            let box = result, !box.video.isEmpty, !box.audio.isEmpty
        {
            AVAssetTrackCache.shared.store(
                videoTracks: box.video, audioTracks: box.audio,
                videoURL: videoURL, audioURL: audioURL)
            playerLog.notice("⚡ [prefetch] tracks cached for preferredQuality=\(maxH)p (itag=\(itag))")
        } else {
            playerLog.notice("[prefetch] track prefetch timed out/failed for preferredQuality=\(maxH)p")
        }
    }
}
