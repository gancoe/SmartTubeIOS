import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

@Suite("CommentsPanelNavigation")
struct CommentsPanelNavigationTests {

    @Test("moves in order and clamps at both ends")
    @MainActor
    func directionalMovementClamps() {
        let navigation = CommentsPanelNavigation()
        let comments = [comment("first"), comment("second")]

        navigation.move(
            offset: 1,
            comments: comments,
            replies: nil,
            pagination: CommentsPaginationState(continuation: nil, errorMessage: nil, isLoading: false)
        )
        #expect(navigation.selection == .comment("first"))

        navigation.move(
            offset: 20,
            comments: comments,
            replies: nil,
            pagination: CommentsPaginationState(continuation: nil, errorMessage: nil, isLoading: false)
        )
        #expect(navigation.selection == .comment("second"))

        navigation.move(
            offset: -20,
            comments: comments,
            replies: nil,
            pagination: CommentsPaginationState(continuation: nil, errorMessage: nil, isLoading: false)
        )
        #expect(navigation.selection == .close)
    }

    @Test("enters a thread and restores its parent selection on back")
    @MainActor
    func threadBackRestoresParent() {
        let navigation = CommentsPanelNavigation()
        let parent = comment("parent")
        let replies = CommentRepliesState(
            comments: [comment("reply-1"), comment("reply-2")],
            continuation: nil
        )

        navigation.selectComment(parent)
        #expect(navigation.selectedThread?.id == "parent")
        #expect(navigation.selection == .close)

        navigation.move(
            offset: 1,
            comments: [],
            replies: replies,
            pagination: CommentsPaginationState(continuation: nil, errorMessage: nil, isLoading: false)
        )
        #expect(navigation.selection == .comment("parent"))

        #expect(navigation.back() == false)
        #expect(navigation.selectedThread == nil)
        #expect(navigation.selection == .comment("parent"))
        #expect(navigation.back() == true)
    }

    @Test("parent continuation adds a load-more choice")
    @MainActor
    func parentLoadMoreChoice() {
        let navigation = CommentsPanelNavigation()
        let comments = [comment("parent")]
        let pagination = CommentsPaginationState(continuation: "next", errorMessage: nil, isLoading: false)

        #expect(
            navigation.choices(
                comments: comments,
                replies: nil,
                continuation: pagination.continuation,
                errorMessage: pagination.errorMessage,
                isLoading: pagination.isLoading
            ) == [.close, .comment("parent"), .loadMore]
        )
        navigation.move(offset: 1, comments: comments, replies: nil, pagination: pagination)
        navigation.move(offset: 1, comments: comments, replies: nil, pagination: pagination)
        #expect(navigation.selection == .loadMore)
    }

    @Test("parent error adds a retry choice")
    @MainActor
    func parentRetryChoice() {
        let navigation = CommentsPanelNavigation()
        let comments = [comment("parent")]
        let pagination = CommentsPaginationState(continuation: "next", errorMessage: "failed", isLoading: false)

        #expect(
            navigation.choices(
                comments: comments,
                replies: nil,
                continuation: pagination.continuation,
                errorMessage: pagination.errorMessage,
                isLoading: pagination.isLoading
            ) == [.close, .comment("parent"), .retry]
        )
        navigation.move(offset: 1, comments: comments, replies: nil, pagination: pagination)
        navigation.move(offset: 1, comments: comments, replies: nil, pagination: pagination)
        #expect(navigation.selection == .retry)
    }

    @Test("parent loading suppresses the footer")
    @MainActor
    func parentLoadingOmitsFooter() {
        let navigation = CommentsPanelNavigation()
        let comments = [comment("parent")]
        let pagination = CommentsPaginationState(continuation: "next", errorMessage: nil, isLoading: true)

        #expect(
            navigation.choices(
                comments: comments,
                replies: nil,
                continuation: pagination.continuation,
                errorMessage: pagination.errorMessage,
                isLoading: pagination.isLoading
            ) == [.close, .comment("parent")]
        )
        navigation.move(offset: 1, comments: comments, replies: nil, pagination: pagination)
        navigation.move(offset: 1, comments: comments, replies: nil, pagination: pagination)
        #expect(navigation.selection == .comment("parent"))
    }

    @Test("thread footer uses reply state instead of parent state")
    @MainActor
    func threadFooterUsesReplyState() {
        let navigation = CommentsPanelNavigation()
        let parent = comment("parent")
        navigation.selectComment(parent)

        let failedReplies = CommentRepliesState(
            comments: [comment("reply")],
            continuation: nil,
            errorMessage: "failed"
        )
        #expect(
            navigation.choices(
                comments: [parent],
                replies: failedReplies,
                continuation: "parent-next",
                errorMessage: nil,
                isLoading: false
            ) == [.close, .comment("parent"), .comment("reply"), .retry]
        )

        let loadingReplies = CommentRepliesState(
            comments: [comment("reply")],
            continuation: "reply-next",
            isLoading: true
        )
        #expect(
            navigation.choices(
                comments: [parent],
                replies: loadingReplies,
                continuation: "parent-next",
                errorMessage: nil,
                isLoading: false
            ) == [.close, .comment("parent"), .comment("reply")]
        )
    }
}

private func comment(_ id: String) -> SmartTubeIOSCore.Comment {
    SmartTubeIOSCore.Comment(id: id, author: id, text: id)
}
