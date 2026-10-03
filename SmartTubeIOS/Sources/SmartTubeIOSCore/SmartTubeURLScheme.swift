import Foundation

// MARK: - SmartTubeURLScheme (#84)
//
// Parses the app's own `smarttube://` URL scheme, used by the Share Extension
// (`smarttube://video/VIDEO_ID`) and by hand-built links from Shortcuts/browser address
// bars using YouTube's own watch-URL query param shape (`smarttube://watch?v=VIDEO_ID`).
// Pulled out of AppEntry.swift's handleOpenURL (a different module, not covered by
// `swift test`) so this parsing has real unit coverage.

public enum SmartTubeURLScheme {
    /// Returns the video ID encoded in `url`, or `nil` if `url` isn't a recognized
    /// `smarttube://` video link.
    public static func videoID(from url: URL) -> String? {
        guard url.scheme?.lowercased() == "smarttube" else { return nil }
        let videoID: String?
        switch url.host?.lowercased() {
        case "video":
            videoID = url.pathComponents.filter { $0 != "/" }.first
        case "watch":
            videoID =
                URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "v" })?.value
        default:
            videoID = nil
        }
        guard let videoID, !videoID.isEmpty else { return nil }
        return videoID
    }
}
