import Foundation

struct PlaybackEngineTrialSource: Equatable {
    let url: URL
    let headers: [String: String]
    let isHLS: Bool

    func matches(activeURL: URL?) -> Bool {
        isHLS && url == activeURL && url.scheme == "https"
    }
}
