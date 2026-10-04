#if os(tvOS)
import SwiftUI

extension PlayerView {
    private var activeCommentReplies: CommentRepliesState? {
        commentsNavigation.selectedThread.flatMap { vm.comments.replies[$0.id] }
    }

    func moveComments(_ direction: MoveCommandDirection) {
        guard direction == .up || direction == .down else { return }
        commentsNavigation.move(
            offset: direction == .down ? 1 : -1,
            comments: vm.comments.comments,
            replies: activeCommentReplies,
            pagination: CommentsPaginationState(
                continuation: vm.comments.continuation,
                errorMessage: vm.comments.errorMessage,
                isLoading: vm.comments.isLoading
            )
        )
    }

    func selectCommentPanelItem() {
        switch commentsNavigation.selection {
        case .close:
            if commentsNavigation.back() { showCommentsSheet = false }
        case .comment(let id):
            guard commentsNavigation.selectedThread == nil,
                let comment = vm.comments.comments.first(where: { $0.id == id })
            else { return }
            commentsNavigation.selectComment(comment)
            vm.comments.loadReplies(for: comment)
        case .loadMore:
            if let thread = commentsNavigation.selectedThread {
                commentsNavigation.selection = .comment(activeCommentReplies?.comments.last?.id ?? thread.id)
                vm.comments.loadReplies(for: thread, loadMore: true)
            } else {
                commentsNavigation.selection = vm.comments.comments.last.map { .comment($0.id) } ?? .close
                vm.comments.loadMore()
            }
        case .retry:
            commentsNavigation.selection = .close
            if let thread = commentsNavigation.selectedThread {
                vm.comments.loadReplies(for: thread)
            } else if vm.comments.comments.isEmpty {
                loadComments()
            } else {
                vm.comments.loadMore()
            }
        }
    }
}
#endif
