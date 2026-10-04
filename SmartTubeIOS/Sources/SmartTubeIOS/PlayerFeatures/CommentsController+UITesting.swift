#if DEBUG && os(tvOS)
import Foundation
import SmartTubeIOSCore

extension CommentsController {
    static func uiFixtureIfRequested(api: InnerTubeAPI) -> CommentsController? {
        guard ProcessInfo.processInfo.arguments.contains("--uitesting-comments-content") else { return nil }
        let replies = CommentsReplyUITestLoader(
            failFirstLoad: ProcessInfo.processInfo.arguments.contains("--uitesting-comments-reply-error"))
        return CommentsController(
            api: api,
            loadPageOperation: { _, continuation in
                let range = continuation == nil ? 1...20 : 21...25
                return CommentPage(
                    comments: range.map {
                        Comment(
                            id: "native-comment-\($0)", author: "Test author \($0)", text: "Test comment \($0)",
                            replyCount: 3, repliesContinuation: "test-replies-\($0)"
                        )
                    },
                    continuation: continuation == nil ? "test-comments-page-2" : nil
                )
            },
            loadRepliesOperation: { continuation in try await replies.load(continuation: continuation) }
        )
    }
}
private actor CommentsReplyUITestLoader {
    private var failFirstLoad: Bool

    init(failFirstLoad: Bool) { self.failFirstLoad = failFirstLoad }

    func load(continuation: String) throws -> CommentPage {
        if failFirstLoad {
            failFirstLoad = false
            throw URLError(.timedOut)
        }
        let isNextPage = continuation == "test-replies-page-2"
        let range = isNextPage ? 3...3 : 1...2
        return CommentPage(
            comments: range.map {
                Comment(id: "native-reply-\($0)", author: "Reply author \($0)", text: "Test reply \($0)")
            },
            continuation: isNextPage ? nil : "test-replies-page-2"
        )
    }
}
#endif
