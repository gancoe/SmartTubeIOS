import SmartTubeIOSCore
import SwiftUI

enum PlayerCommentsAccessibility {
    static let retry = "player.comments.retry"
    static let close = "player.comments.close"
    static let loadMore = "player.comments.loadMore"
    static let loadMoreReplies = "player.comments.loadMoreReplies"
    static func comment(_ id: String) -> String { "player.comments.comment.\(id)" }
}

struct CommentsOverlayView: View {
    let comments: [Comment]
    let isLoading: Bool
    let onDismiss: () -> Void
    #if os(tvOS)
    var focusNamespace: Namespace.ID
    var navigation: CommentsPanelNavigation?
    @FocusState private var closeFocused: Bool
    @FocusState private var focusedCommentID: String?
    #endif
    var accessibilityId: String?
    var continuation: String?
    var errorMessage: String?
    var replies: [String: CommentRepliesState] = [:]
    var onLoadMore: (() -> Void)?
    var onLoadReplies: ((Comment, Bool) -> Void)?
    var onRetry: (() -> Void)?
    @State private var nativeThread: Comment?
    @State private var returnCommentID: String?

    private var selectedThread: Comment? {
        #if os(tvOS)
        if let navigation { return navigation.selectedThread }
        #endif
        return nativeThread
    }

    private var highlightedCommentID: String? {
        #if os(tvOS)
        if let navigation {
            if case .comment(let id) = navigation.selection { return id }
            return nil
        }
        return focusedCommentID
        #else
        return nil
        #endif
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { goBack() }
            VStack(spacing: 0) {
                header
                Divider()
                if let thread = selectedThread {
                    threadContents(thread)
                } else if comments.isEmpty {
                    if isLoading {
                        ProgressView().padding(40)
                    } else if let errorMessage {
                        retryPrompt(errorMessage, action: onRetry)
                    } else {
                        Text("No comments available.")
                            .foregroundStyle(.secondary)
                            .padding(40)
                    }
                } else {
                    commentList
                }
            }
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            #if os(tvOS)
            .focusScope(focusNamespace)
            .defaultFocus($closeFocused, navigation == nil)
            .onExitCommand { goBack() }
            .task(id: selectedThread?.id) {
                guard navigation == nil else { return }
                try? await Task.sleep(for: TVPlayerFocus.settleDelay)
                guard !Task.isCancelled else { return }
                if selectedThread == nil, let id = returnCommentID {
                    closeFocused = false
                    focusedCommentID = id
                    returnCommentID = nil
                } else {
                    focusedCommentID = nil
                    closeFocused = true
                }
            }
            .onDisappear { closeFocused = false }
            #endif
            .padding(.horizontal, 8)
            .safeAreaPadding(.horizontal)
            .padding(.bottom, 8)
        }
        .ignoresSafeArea()
        .accessibilityIdentifier(accessibilityId)
    }

    private var header: some View {
        HStack {
            Button {
                goBack()
            } label: {
                Image(systemName: selectedThread == nil ? AppSymbol.xmark : AppSymbol.chevronLeft)
                    .font(.system(size: 16, weight: .semibold))
                    .padding(12)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(PlayerCommentsAccessibility.close)
            .accessibilityLabel(selectedThread == nil ? "Close comments" : "Back to comments")
            #if os(tvOS)
            .focused($closeFocused)
            .focusable(navigation == nil)
            .prefersDefaultFocus(navigation == nil, in: focusNamespace)
            .accessibilityValue(navigation?.selection == .close ? "Selected" : "")
            .modifier(CommentsSelectionHighlight(selected: navigation?.selection == .close))
            .onMoveCommand { direction in
                if direction == .down, let first = selectedThread ?? comments.first {
                    closeFocused = false
                    focusedCommentID = first.id
                }
            }
            #endif
            Spacer()
            Text(selectedThread == nil ? "Comments" : "Replies").fontWeight(.semibold)
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 4)
    }

    private var commentList: some View {
        scrollingComments {
            ForEach(comments) { comment in
                commentRow(comment, opensThread: onLoadReplies != nil)
            }
            if isLoading {
                ProgressView().padding()
            } else if let errorMessage {
                retryPrompt(errorMessage, action: onLoadMore)
            } else if continuation != nil, let onLoadMore {
                Button("Load more comments", action: onLoadMore)
                    .accessibilityIdentifier(PlayerCommentsAccessibility.loadMore)
                    .id(PlayerCommentsAccessibility.loadMore)
                    #if os(tvOS)
                .focusable(navigation == nil)
                .accessibilityValue(navigation?.selection == .loadMore ? "Selected" : "")
                .modifier(CommentsSelectionHighlight(selected: navigation?.selection == .loadMore))
                    #endif
            }
        }
    }

    private func threadContents(_ thread: Comment) -> some View {
        let state = replies[thread.id]
        return scrollingComments {
            commentRow(thread, opensThread: false)
            Divider()
            ForEach(state?.comments ?? thread.inlineReplies) { reply in
                commentRow(reply, opensThread: false)
            }
            if state?.isLoading == true {
                ProgressView().padding()
            } else if let error = state?.errorMessage {
                retryPrompt(error) { onLoadReplies?(thread, false) }
            } else if state?.continuation != nil {
                Button("Load more replies") { onLoadReplies?(thread, true) }
                    .accessibilityIdentifier(PlayerCommentsAccessibility.loadMoreReplies)
                    .id(PlayerCommentsAccessibility.loadMoreReplies)
                    #if os(tvOS)
                .focusable(navigation == nil)
                .accessibilityValue(navigation?.selection == .loadMore ? "Selected" : "")
                .modifier(CommentsSelectionHighlight(selected: navigation?.selection == .loadMore))
                    #endif
            } else if (state?.comments ?? thread.inlineReplies).isEmpty {
                Text("No replies available.").foregroundStyle(.secondary).padding()
            }
        }
    }

    private func scrollingComments<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12, content: content)
                    .padding()
            }
            #if os(tvOS)
            .focusSection()
            .onChange(of: highlightedCommentID) { _, id in
                if let id { proxy.scrollTo(id, anchor: .center) }
            }
            .onChange(of: navigation?.selection) { _, selection in
                if selection == .loadMore {
                    proxy.scrollTo(
                        selectedThread == nil
                            ? PlayerCommentsAccessibility.loadMore
                            : PlayerCommentsAccessibility.loadMoreReplies, anchor: .center)
                } else if selection == .retry {
                    proxy.scrollTo(PlayerCommentsAccessibility.retry, anchor: .center)
                }
            }
            #endif
        }
        .frame(maxHeight: 400)
    }

    private func commentRow(_ comment: Comment, opensThread: Bool) -> some View {
        Button {
            guard opensThread else { return }
            returnCommentID = comment.id
            #if os(tvOS)
            if let navigation { navigation.selectComment(comment) } else { nativeThread = comment }
            #else
            nativeThread = comment
            #endif
            onLoadReplies?(comment, false)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                CommentRowView(comment: comment)
                if opensThread {
                    Text(comment.replyCount.map { "\($0) replies" } ?? "Open thread")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            #if os(tvOS)
            .modifier(CommentsSelectionHighlight(selected: highlightedCommentID == comment.id))
            #endif
        }
        .buttonStyle(.plain)
        #if os(tvOS)
        .focusable(navigation == nil)
        .focused($focusedCommentID, equals: comment.id)
        .accessibilityValue(navigation?.selection == .comment(comment.id) ? "Selected" : "")
        #endif
        .accessibilityIdentifier(PlayerCommentsAccessibility.comment(comment.id))
        .id(comment.id)
    }

    private func retryPrompt(_ message: String, action: (() -> Void)?) -> some View {
        VStack(spacing: 12) {
            Text(message).foregroundStyle(.secondary)
            if let action {
                Button("Try again", action: action)
                    .accessibilityIdentifier(PlayerCommentsAccessibility.retry)
                    .id(PlayerCommentsAccessibility.retry)
                    #if os(tvOS)
                .focusable(navigation == nil)
                .accessibilityValue(navigation?.selection == .retry ? "Selected" : "")
                .modifier(CommentsSelectionHighlight(selected: navigation?.selection == .retry))
                    #endif
            }
        }
        .padding()
    }

    private func goBack() {
        #if os(tvOS)
        if let navigation {
            if navigation.back() { onDismiss() }
            return
        }
        #endif
        if nativeThread != nil {
            nativeThread = nil
        } else {
            onDismiss()
        }
    }
}

private extension View {
    @ViewBuilder
    func accessibilityIdentifier(_ id: String?) -> some View {
        if let id {
            self.accessibilityIdentifier(id)
        } else {
            self
        }
    }
}

private struct CommentsSelectionHighlight: ViewModifier {
    let selected: Bool

    func body(content: Content) -> some View {
        content
            .background(selected ? Color.white.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12).stroke(selected ? Color.white : .clear, lineWidth: 2)
            }
    }
}
