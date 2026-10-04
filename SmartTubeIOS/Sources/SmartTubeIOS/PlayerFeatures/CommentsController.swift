import Foundation
import Observation
import SmartTubeIOSCore

struct CommentRepliesState: Sendable {
    var comments: [Comment]
    var continuation: String?
    var isLoading: Bool = false
    var errorMessage: String?
}

// MARK: - Comments

/// Fetches and caches paged top-level comments and individual reply threads.
@MainActor
@Observable
final class CommentsController {

    private(set) var comments: [Comment] = []
    private(set) var isLoading = false
    private(set) var continuation: String?
    private(set) var errorMessage: String?
    private(set) var replies: [String: CommentRepliesState] = [:]

    @ObservationIgnored private let api: InnerTubeAPI
    @ObservationIgnored private let logError: (String) -> Void
    @ObservationIgnored private let loadPageOperation: @Sendable (String, String?) async throws -> CommentPage
    @ObservationIgnored private let loadRepliesOperation: @Sendable (String) async throws -> CommentPage
    @ObservationIgnored private var currentVideoID: String?
    @ObservationIgnored private var hasLoadedInitialPage = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var topTask: Task<Void, Never>?
    @ObservationIgnored private var replyTasks: [String: Task<Void, Never>] = [:]

    init(
        api: InnerTubeAPI,
        logError: @escaping (String) -> Void = { _ in },
        loadPageOperation: (@Sendable (String, String?) async throws -> CommentPage)? = nil,
        loadRepliesOperation: (@Sendable (String) async throws -> CommentPage)? = nil
    ) {
        self.api = api
        self.logError = logError
        self.loadPageOperation =
            loadPageOperation ?? { videoID, continuation in
                try await api.fetchCommentsPage(videoId: videoID, continuation: continuation)
            }
        self.loadRepliesOperation =
            loadRepliesOperation ?? { continuation in
                try await api.fetchCommentReplies(continuation: continuation)
            }
    }

    @discardableResult
    func load(videoId: String) -> Task<Void, Never>? {
        if currentVideoID != videoId {
            reset(for: videoId)
        } else if hasLoadedInitialPage || isLoading {
            return nil
        }

        let requestGeneration = generation
        isLoading = true
        errorMessage = nil
        let operation = loadPageOperation
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let page = try await operation(videoId, nil)
                guard self.isCurrent(requestGeneration), !Task.isCancelled else {
                    if self.isCurrent(requestGeneration) {
                        self.isLoading = false
                        self.topTask = nil
                    }
                    return
                }
                self.comments = self.mergedComments(self.comments, page.comments)
                self.continuation = page.continuation
                self.hasLoadedInitialPage = true
                self.errorMessage = nil
                self.isLoading = false
                self.topTask = nil
            } catch {
                guard self.isCurrent(requestGeneration) else { return }
                self.isLoading = false
                self.topTask = nil
                guard !Task.isCancelled else { return }
                self.errorMessage = "Unable to load comments. Try again."
                self.logError("comments load failed")
            }
        }
        topTask = task
        return task
    }

    @discardableResult
    func loadMore() -> Task<Void, Never>? {
        guard let videoID = currentVideoID,
            let continuation,
            !isLoading
        else { return nil }

        let requestGeneration = generation
        isLoading = true
        errorMessage = nil
        let operation = loadPageOperation
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let page = try await operation(videoID, continuation)
                guard self.isCurrent(requestGeneration), !Task.isCancelled else {
                    if self.isCurrent(requestGeneration) {
                        self.isLoading = false
                        self.topTask = nil
                    }
                    return
                }
                self.comments = self.mergedComments(self.comments, page.comments)
                self.continuation = page.continuation
                self.errorMessage = nil
                self.isLoading = false
                self.topTask = nil
            } catch {
                guard self.isCurrent(requestGeneration) else { return }
                self.isLoading = false
                self.topTask = nil
                guard !Task.isCancelled else { return }
                self.errorMessage = "Unable to load more comments. Try again."
                self.logError("more comments load failed")
            }
        }
        topTask = task
        return task
    }

    @discardableResult
    func loadReplies(for comment: Comment, loadMore: Bool = false) -> Task<Void, Never>? {
        let commentID = comment.id
        guard replyTasks[commentID] == nil else { return nil }

        if loadMore {
            if replies[commentID] == nil {
                replies[commentID] = CommentRepliesState(
                    comments: mergedComments([], comment.inlineReplies),
                    continuation: comment.repliesContinuation
                )
            }
            guard let state = replies[commentID], let continuation = state.continuation else {
                return nil
            }
            return startReplyLoad(commentID: commentID, continuation: continuation)
        }

        if let state = replies[commentID] {
            guard state.errorMessage != nil, let continuation = state.continuation else {
                return nil
            }
            return startReplyLoad(commentID: commentID, continuation: continuation)
        }

        let inlineReplies = mergedComments([], comment.inlineReplies)
        guard let continuation = comment.repliesContinuation else {
            replies[commentID] = CommentRepliesState(comments: inlineReplies, continuation: nil)
            return nil
        }
        replies[commentID] = CommentRepliesState(
            comments: inlineReplies,
            continuation: continuation
        )
        return startReplyLoad(commentID: commentID, continuation: continuation)
    }

    private func reset(for videoID: String) {
        topTask?.cancel()
        topTask = nil
        replyTasks.values.forEach { $0.cancel() }
        replyTasks.removeAll()
        generation += 1
        currentVideoID = videoID
        hasLoadedInitialPage = false
        comments = []
        continuation = nil
        errorMessage = nil
        isLoading = false
        replies = [:]
    }

    private func startReplyLoad(commentID: String, continuation: String) -> Task<Void, Never>? {
        guard var state = replies[commentID], !state.isLoading else { return nil }
        state.isLoading = true
        state.errorMessage = nil
        replies[commentID] = state

        let requestGeneration = generation
        let operation = loadRepliesOperation
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let page = try await operation(continuation)
                guard self.isCurrent(requestGeneration), !Task.isCancelled else {
                    if self.isCurrent(requestGeneration) {
                        self.finishReplyLoad(commentID: commentID)
                    }
                    return
                }
                if var state = self.replies[commentID] {
                    state.comments = self.mergedComments(state.comments, page.comments)
                    state.continuation = page.continuation
                    state.isLoading = false
                    state.errorMessage = nil
                    self.replies[commentID] = state
                }
                self.replyTasks[commentID] = nil
            } catch {
                guard self.isCurrent(requestGeneration) else { return }
                self.finishReplyLoad(commentID: commentID)
                guard !Task.isCancelled else { return }
                if var state = self.replies[commentID] {
                    state.errorMessage = "Unable to load replies. Try again."
                    self.replies[commentID] = state
                }
                self.logError("comment replies load failed")
            }
        }
        replyTasks[commentID] = task
        return task
    }

    private func finishReplyLoad(commentID: String) {
        if var state = replies[commentID] {
            state.isLoading = false
            replies[commentID] = state
        }
        replyTasks[commentID] = nil
    }

    private func isCurrent(_ requestGeneration: Int) -> Bool {
        generation == requestGeneration
    }

    private func mergedComments(_ existing: [Comment], _ new: [Comment]) -> [Comment] {
        var seen = Set<String>()
        return (existing + new).filter { seen.insert($0.id).inserted }
    }
}
