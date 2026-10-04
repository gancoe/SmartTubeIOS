import Foundation
import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

private actor CommentControllerRecorder {
    private(set) var topContinuations: [String?] = []
    private(set) var replyContinuations: [String] = []

    func recordTop(_ continuation: String?) {
        topContinuations.append(continuation)
    }

    func recordReply(_ continuation: String) {
        replyContinuations.append(continuation)
    }
}

private actor CommentControllerGate {
    private var startedWaiters: [CheckedContinuation<Void, Never>] = []
    private var pageWaiters: [CheckedContinuation<CommentPage, Never>] = []

    func waitForStart() async {
        await withCheckedContinuation { continuation in
            startedWaiters.append(continuation)
        }
    }

    func waitForPage() async -> CommentPage {
        await withCheckedContinuation { continuation in
            pageWaiters.append(continuation)
        }
    }

    func markStarted() {
        startedWaiters.forEach { $0.resume() }
        startedWaiters.removeAll()
    }

    func resolve(_ page: CommentPage) {
        pageWaiters.forEach { $0.resume(returning: page) }
        pageWaiters.removeAll()
    }
}

@Suite("CommentsController")
struct CommentsControllerTests {

    @Test("pages and reply threads preserve order and remove duplicate IDs")
    @MainActor
    func pagesAndRepliesAreDeduplicated() async {
        let recorder = CommentControllerRecorder()
        let parent = Comment(
            id: "parent",
            author: "Author",
            text: "Parent",
            repliesContinuation: "replies-1",
            inlineReplies: [comment("reply-1")]
        )
        let controller = CommentsController(
            api: InnerTubeAPI(),
            loadPageOperation: { _, continuation in
                await recorder.recordTop(continuation)
                if continuation == nil {
                    return CommentPage(comments: [parent, comment("second")], continuation: "top-2")
                }
                return CommentPage(comments: [comment("second"), comment("third")])
            },
            loadRepliesOperation: { continuation in
                await recorder.recordReply(continuation)
                if continuation == "replies-1" {
                    return CommentPage(
                        comments: [comment("reply-1"), comment("reply-2")],
                        continuation: "replies-2"
                    )
                }
                return CommentPage(comments: [comment("reply-2"), comment("reply-3")])
            }
        )

        if let task = controller.load(videoId: "video") { await task.value }
        if let task = controller.loadMore() { await task.value }
        #expect(controller.comments.map { $0.id } == ["parent", "second", "third"])
        #expect(await recorder.topContinuations == [nil, "top-2"])

        if let task = controller.loadReplies(for: parent) { await task.value }
        if let task = controller.loadReplies(for: parent, loadMore: true) { await task.value }
        #expect(controller.replies["parent"]?.comments.map { $0.id } == ["reply-1", "reply-2", "reply-3"])
        #expect(controller.replies["parent"]?.continuation == nil)
        #expect(await recorder.replyContinuations == ["replies-1", "replies-2"])
    }

    @Test("failed page retains comments and token so retry can continue")
    @MainActor
    func failedPageCanRetry() async {
        let recorder = CommentControllerRecorder()
        let controller = CommentsController(
            api: InnerTubeAPI(),
            loadPageOperation: { _, continuation in
                await recorder.recordTop(continuation)
                if continuation == nil {
                    return CommentPage(comments: [comment("first")], continuation: "top-2")
                }
                if await recorder.topContinuations.filter({ $0 == "top-2" }).count == 1 {
                    throw TestError.failed
                }
                return CommentPage(comments: [comment("second")])
            }
        )

        if let task = controller.load(videoId: "video") { await task.value }
        if let task = controller.loadMore() { await task.value }
        #expect(controller.comments.map { $0.id } == ["first"])
        #expect(controller.continuation == "top-2")
        #expect(controller.errorMessage != nil)

        if let task = controller.loadMore() { await task.value }
        #expect(controller.comments.map { $0.id } == ["first", "second"])
        #expect(controller.continuation == nil)
        #expect(controller.errorMessage == nil)
    }

    @Test("failed reply fetch retains inline replies and retries the same token")
    @MainActor
    func failedReplyCanRetryWithoutDuplicates() async {
        let script = ReplyFetchScript()
        let parent = Comment(
            id: "parent",
            author: "Author",
            text: "Parent",
            repliesContinuation: "reply-token",
            inlineReplies: [comment("inline-reply")]
        )
        let controller = CommentsController(
            api: InnerTubeAPI(),
            loadRepliesOperation: { continuation in
                try await script.fetch(continuation: continuation)
            }
        )

        if let task = controller.loadReplies(for: parent) { await task.value }
        #expect(controller.replies["parent"]?.comments.map { $0.id } == ["inline-reply"])
        #expect(controller.replies["parent"]?.continuation == "reply-token")
        #expect(controller.replies["parent"]?.errorMessage != nil)

        if let task = controller.loadReplies(for: parent) { await task.value }
        #expect(controller.replies["parent"]?.comments.map { $0.id } == ["inline-reply", "second-reply"])
        #expect(controller.replies["parent"]?.continuation == nil)
        #expect(controller.replies["parent"]?.errorMessage == nil)
        #expect(await script.continuations == ["reply-token", "reply-token"])
    }

    @Test("switching videos ignores a canceled operation that later completes")
    @MainActor
    func staleCompletionDoesNotReplaceNewVideo() async {
        let oldGate = CommentControllerGate()
        let controller = CommentsController(
            api: InnerTubeAPI(),
            loadPageOperation: { videoID, _ in
                if videoID == "old-video" {
                    await oldGate.markStarted()
                    return await oldGate.waitForPage()
                }
                return CommentPage(comments: [comment("new-video-comment")])
            }
        )

        let oldTask = controller.load(videoId: "old-video")
        await oldGate.waitForStart()
        if let task = controller.load(videoId: "new-video") { await task.value }
        #expect(controller.comments.map { $0.id } == ["new-video-comment"])

        await oldGate.resolve(CommentPage(comments: [comment("old-video-comment")]))
        if let oldTask { await oldTask.value }
        #expect(controller.comments.map { $0.id } == ["new-video-comment"])
    }

    @Test("switching videos ignores a late reply completion")
    @MainActor
    func staleReplyCompletionDoesNotRepopulateNewVideo() async {
        let replyGate = CommentControllerGate()
        let parent = Comment(
            id: "old-parent",
            author: "Author",
            text: "Parent",
            repliesContinuation: "old-replies"
        )
        let controller = CommentsController(
            api: InnerTubeAPI(),
            loadPageOperation: { videoID, _ in
                if videoID == "old-video" {
                    return CommentPage(comments: [parent])
                }
                return CommentPage(comments: [comment("new-video-comment")])
            },
            loadRepliesOperation: { continuation in
                if continuation == "old-replies" {
                    await replyGate.markStarted()
                    return await replyGate.waitForPage()
                }
                return CommentPage(comments: [])
            }
        )

        if let task = controller.load(videoId: "old-video") { await task.value }
        let oldReplyTask = controller.loadReplies(for: parent)
        await replyGate.waitForStart()
        if let task = controller.load(videoId: "new-video") { await task.value }
        await replyGate.resolve(CommentPage(comments: [comment("late-reply")]))
        if let oldReplyTask { await oldReplyTask.value }

        #expect(controller.comments.map { $0.id } == ["new-video-comment"])
        #expect(controller.replies.isEmpty)
    }
}

private enum TestError: Error {
    case failed
}

private actor ReplyFetchScript {
    private(set) var continuations: [String] = []

    func fetch(continuation: String) throws -> CommentPage {
        continuations.append(continuation)
        if continuations.count == 1 {
            throw TestError.failed
        }
        return CommentPage(comments: [comment("inline-reply"), comment("second-reply")])
    }
}

private func comment(_ id: String) -> SmartTubeIOSCore.Comment {
    SmartTubeIOSCore.Comment(id: id, author: id, text: id)
}
