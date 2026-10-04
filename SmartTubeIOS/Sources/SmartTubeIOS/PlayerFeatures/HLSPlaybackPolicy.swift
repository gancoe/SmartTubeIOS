import SmartTubeIOSCore

/// Client-specific HLS settings used for both initial playback and quality changes.
struct HLSPlaybackPolicy: Equatable, Sendable {
    let userAgent: String
    let maximumHeight: Int?
    let filtersManifest: Bool
    let allowedVideoCodecs: [String]?

    var requiresH264: Bool { allowedVideoCodecs == ["avc1"] }

    static func resolve(label: String, isHLS: Bool) -> Self {
        guard isHLS else {
            return Self(
                userAgent: "com.google.ios.youtube/19.45.4 (iPhone16,2; U; CPU iOS 18_1_0 like Mac OS X)",
                maximumHeight: nil,
                filtersManifest: false,
                allowedVideoCodecs: nil
            )
        }
        if label.contains("VisionOS/Native4K") {
            return Self(
                userAgent: InnerTubeClients.VisionOS.userAgent,
                maximumHeight: 2160,
                filtersManifest: true,
                allowedVideoCodecs: ["avc1", "vp09.00"]
            )
        }
        if label.localizedCaseInsensitiveContains("visionos") {
            return Self(
                userAgent: InnerTubeClients.VisionOS.userAgent,
                maximumHeight: InnerTubeClients.VisionOS.maximumHLSHeight,
                filtersManifest: true,
                allowedVideoCodecs: ["avc1"]
            )
        }
        if label.contains("WebSafari") {
            return Self(
                userAgent: InnerTubeClients.WebSafari.userAgent,
                maximumHeight: nil,
                filtersManifest: false,
                allowedVideoCodecs: nil
            )
        }
        return Self(
            userAgent: "com.google.ios.youtube/19.45.4 (iPhone16,2; U; CPU iOS 18_1_0 like Mac OS X)",
            maximumHeight: nil,
            filtersManifest: false,
            allowedVideoCodecs: nil
        )
    }

    func cappedHeight(requested: Int?) -> Int? {
        guard let maximumHeight else { return requested }
        return min(requested ?? maximumHeight, maximumHeight)
    }

    func allowsFormat(height: Int, mimeType: String) -> Bool {
        if let maximumHeight, height > maximumHeight { return false }
        if let allowedVideoCodecs,
            !allowedVideoCodecs.contains(where: { mimeType.localizedCaseInsensitiveContains($0) })
                && !(allowedVideoCodecs.contains("vp09.00")
                    && mimeType.localizedCaseInsensitiveContains("codecs=\"vp9\""))
        {
            return false
        }
        return true
    }
}

extension HLSPlaybackPolicy {
    func cacheKey(videoId: String) -> String {
        guard let allowedVideoCodecs else { return videoId }
        return "\(videoId)|\(maximumHeight ?? 0)|\(allowedVideoCodecs.joined(separator: ","))"
    }

    func formatsForHLS(
        _ formats: [SmartTubeIOSCore.VideoFormat], variantHeights: Set<Int>
    ) -> [SmartTubeIOSCore.VideoFormat] {
        formats.filter {
            variantHeights.contains($0.height) && allowsFormat(height: $0.height, mimeType: $0.mimeType)
        }.sorted {
            if $0.height != $1.height { return $0.height > $1.height }
            if $0.fps != $1.fps { return $0.fps > $1.fps }
            let firstIsH264 = $0.mimeType.contains("avc1")
            let secondIsH264 = $1.mimeType.contains("avc1")
            if firstIsH264 != secondIsH264 { return firstIsH264 }
            return ($0.bitrate ?? 0) > ($1.bitrate ?? 0)
        }
    }
}
