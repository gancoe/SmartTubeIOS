import Observation
import SmartTubeIOSCore

enum CommentsPanelSelection: Equatable {
    case close
    case comment(String)
    case loadMore
    case retry
}

struct CommentsPaginationState {
    var continuation: String?
    var errorMessage: String?
    var isLoading: Bool
}

@MainActor
@Observable
final class CommentsPanelNavigation {
    var selection: CommentsPanelSelection = .close
    private(set) var selectedThread: Comment?
    private var returnParentID: String?

    func reset() {
        selection = .close
        selectedThread = nil
        returnParentID = nil
    }

    func move(
        offset: Int,
        comments: [Comment],
        replies: CommentRepliesState?,
        pagination: CommentsPaginationState
    ) {
        let choices = choices(
            comments: comments,
            replies: replies,
            continuation: pagination.continuation,
            errorMessage: pagination.errorMessage,
            isLoading: pagination.isLoading
        )
        guard let currentIndex = choices.firstIndex(of: selection) else {
            selection = choices.first ?? .close
            return
        }
        let nextIndex = min(max(currentIndex + offset, 0), choices.count - 1)
        selection = choices[nextIndex]
    }

    func selectComment(_ comment: Comment) {
        returnParentID = comment.id
        selectedThread = comment
        selection = .close
    }

    func back() -> Bool {
        guard selectedThread != nil else { return true }
        let parentID = returnParentID
        selectedThread = nil
        returnParentID = nil
        if let parentID {
            selection = .comment(parentID)
        } else {
            selection = .close
        }
        return false
    }

    func choices(
        comments: [Comment],
        replies: CommentRepliesState?,
        continuation: String?,
        errorMessage: String?,
        isLoading: Bool
    ) -> [CommentsPanelSelection] {
        var result: [CommentsPanelSelection] = [.close]
        if let selectedThread {
            result.append(.comment(selectedThread.id))
            let cachedReplies = replies?.comments ?? selectedThread.inlineReplies
            result.append(contentsOf: cachedReplies.map { .comment($0.id) })
        } else {
            result.append(contentsOf: comments.map { .comment($0.id) })
        }
        let footerError = selectedThread == nil ? errorMessage : replies?.errorMessage
        let footerContinuation = selectedThread == nil ? continuation : replies?.continuation
        let footerIsLoading = selectedThread == nil ? isLoading : (replies?.isLoading ?? false)
        if footerError != nil {
            result.append(.retry)
        } else if footerContinuation != nil, !footerIsLoading {
            result.append(.loadMore)
        }
        return result
    }
}
