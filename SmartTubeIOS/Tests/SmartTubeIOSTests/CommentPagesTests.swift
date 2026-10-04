import Foundation
import Testing

@testable import SmartTubeIOSCore

private class CommentPagesURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responses: [Data] = []
    nonisolated(unsafe) static var requestBodies: [Data] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let body = request.httpBody {
            Self.requestBodies.append(body)
        } else if let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read > 0 { data.append(buffer, count: read) } else { break }
            }
            stream.close()
            Self.requestBodies.append(data)
        }
        let body = Self.responses.isEmpty ? Data("{}".utf8) : Self.responses.removeFirst()
        guard let url = request.url,
            let response = HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("Comment pages and replies", .serialized)
struct CommentPagesTests {

    private func makeAPI(responses: [[String: Any]]) -> InnerTubeAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CommentPagesURLProtocol.self]
        CommentPagesURLProtocol.responses = responses.compactMap { try? JSONSerialization.data(withJSONObject: $0) }
        CommentPagesURLProtocol.requestBodies = []
        return InnerTubeAPI(authToken: nil, session: URLSession(configuration: configuration))
    }

    @Test("entity pages keep parent order, attach inline replies, and separate continuations")
    func entityPagePreservesThreads() async throws {
        let api = makeAPI(responses: [bootstrapFixture(), entityPageFixture()])

        let page = try await api.fetchCommentsPage(videoId: "video")

        #expect(page.comments.map(\.id) == ["parent-1", "parent-2"])
        #expect(page.continuation == "page-next")
        #expect(page.comments[0].replyCount == 2)
        #expect(page.comments[0].repliesContinuation == "replies-next")
        #expect(page.comments[0].inlineReplies.map(\.id) == ["reply-1"])
        #expect(page.comments[0].inlineReplies.first?.author == "Reply author")
        #expect(page.comments.contains { $0.id == "orphan" } == false)
        #expect(CommentPagesURLProtocol.requestBodies.count == 2)
    }

    @Test("reply-only entity page returns direct comments and its own page continuation")
    func replyPageLoadsDirectComments() async throws {
        let api = makeAPI(responses: [replyPageFixture()])

        let page = try await api.fetchCommentReplies(continuation: "replies-next")

        #expect(page.comments.map(\.id) == ["reply-2", "reply-3"])
        #expect(page.continuation == "replies-page-next")
        #expect(page.comments.allSatisfy { $0.inlineReplies.isEmpty })
    }

    @Test("legacy pages retain nested replies and do not confuse reply token with page token")
    func legacyPageParsesNestedReplies() async throws {
        let api = makeAPI(responses: [legacyPageFixture()])

        let page = try await api.fetchCommentReplies(continuation: "legacy")

        #expect(page.comments.map(\.id) == ["legacy-parent", "legacy-parent-2"])
        #expect(page.comments[0].inlineReplies.map(\.id) == ["legacy-reply", "legacy-subreply"])
        #expect(page.comments[0].repliesContinuation == "legacy-replies-next")
        #expect(page.continuation == "legacy-page-next")
    }

    @Test("missing bootstrap comments token returns an empty page")
    func missingBootstrapTokenReturnsEmptyPage() async throws {
        let api = makeAPI(responses: [
            ["engagementPanels": [["engagementPanelSectionListRenderer": ["panelIdentifier": "watch7b"]]]]
        ])

        let page = try await api.fetchCommentsPage(videoId: "video")

        #expect(page.comments.isEmpty)
        #expect(page.continuation == nil)
        #expect(CommentPagesURLProtocol.requestBodies.count == 1)
    }

    @Test("legacy fetchComments delegates to the first page comments")
    func legacyFetchCommentsDelegatesToPage() async throws {
        let api = makeAPI(responses: [bootstrapFixture(), legacyPageFixture()])

        let comments = try await api.fetchComments(videoId: "video")

        #expect(comments.map(\.id) == ["legacy-parent", "legacy-parent-2"])
    }
}

private func bootstrapFixture() -> [String: Any] {
    [
        "engagementPanels": [
            [
                "engagementPanelSectionListRenderer": [
                    "panelIdentifier": "commentary",
                    "content": [
                        "itemSectionRenderer": [
                            "contents": [
                                [
                                    "continuationItemRenderer": [
                                        "continuationEndpoint": ["continuationCommand": ["token": "comments-start"]]
                                    ]
                                ]
                            ]
                        ]
                    ],
                ]
            ]
        ]
    ]
}

private func entityPageFixture() -> [String: Any] {
    let mutations: [[String: Any]] = [
        entityMutation(key: "comment-1", id: "parent-1", author: "Parent author", text: "Parent one"),
        entityMutation(key: "toolbar-1", toolbar: ["likeCountA11y": "12", "likeState": "LIKE_STATE_LIKED"]),
        entityMutation(key: "comment-reply-1", id: "reply-1", author: "Reply author", text: "Reply one"),
        entityMutation(key: "comment-2", id: "parent-2", author: "Second author", text: "Parent two"),
        entityMutation(key: "orphan-key", id: "orphan", author: "Orphan", text: "Do not include"),
    ]
    let parent1: [String: Any] = [
        "commentViewModel": [
            "commentViewModel": ["commentKey": "comment-1", "toolbarStateKey": "toolbar-1", "replyCount": 2]
        ],
        "replies": [
            "commentRepliesRenderer": [
                "contents": [["commentViewModel": ["commentKey": "comment-reply-1"]]],
                "subThreads": [
                    [
                        "continuationItemRenderer": [
                            "continuationEndpoint": ["continuationCommand": ["token": "replies-next"]]
                        ]
                    ]
                ],
            ]
        ],
    ]
    let parent2: [String: Any] = [
        "commentViewModel": ["commentViewModel": ["commentKey": "comment-2", "toolbarStateKey": "missing-toolbar"]]
    ]
    return [
        "frameworkUpdates": ["entityBatchUpdate": ["mutations": mutations]],
        "onResponseReceivedEndpoints": [
            [
                "appendContinuationItemsAction": [
                    "continuationItems": [
                        ["commentThreadRenderer": parent1],
                        ["commentThreadRenderer": parent2],
                        [
                            "continuationItemRenderer": [
                                "continuationEndpoint": ["continuationCommand": ["token": "page-next"]]
                            ]
                        ],
                    ]
                ]
            ]
        ],
    ]
}

private func replyPageFixture() -> [String: Any] {
    [
        "frameworkUpdates": [
            "entityBatchUpdate": [
                "mutations": [
                    entityMutation(key: "reply-2-key", id: "reply-2", author: "Reply two", text: "Two"),
                    entityMutation(key: "reply-3-key", id: "reply-3", author: "Reply three", text: "Three"),
                ]
            ]
        ],
        "onResponseReceivedEndpoints": [
            [
                "appendContinuationItemsAction": [
                    "continuationItems": [
                        ["commentViewModel": ["commentKey": "reply-2-key"]],
                        ["commentViewModel": ["commentKey": "reply-3-key"]],
                        [
                            "continuationItemRenderer": [
                                "continuationEndpoint": ["continuationCommand": ["token": "replies-page-next"]]
                            ]
                        ],
                    ]
                ]
            ]
        ],
    ]
}

private func legacyPageFixture() -> [String: Any] {
    [
        "onResponseReceivedEndpoints": [
            [
                "appendContinuationItemsAction": [
                    "continuationItems": [
                        [
                            "commentThreadRenderer": [
                                "commentRenderer": legacyComment(id: "legacy-parent", text: "Parent"),
                                "replies": [
                                    "commentRepliesRenderer": [
                                        "contents": [
                                            [
                                                "replyRenderer": [
                                                    "comment": [
                                                        "commentRenderer": legacyComment(
                                                            id: "legacy-reply", text: "Reply")
                                                    ]
                                                ]
                                            ]
                                        ],
                                        "subThreads": [
                                            [
                                                "commentThreadRenderer": [
                                                    "commentRenderer": legacyComment(
                                                        id: "legacy-subreply", text: "Subreply")
                                                ]
                                            ]
                                        ],
                                        "continuationItemRenderer": [
                                            "continuationEndpoint": [
                                                "continuationCommand": ["token": "legacy-replies-next"]
                                            ]
                                        ],
                                    ]
                                ],
                            ]
                        ],
                        [
                            "commentThreadRenderer": [
                                "comment": ["commentRenderer": legacyComment(id: "legacy-parent-2", text: "Second")]
                            ]
                        ],
                        [
                            "continuationItemRenderer": [
                                "continuationEndpoint": ["continuationCommand": ["token": "legacy-page-next"]]
                            ]
                        ],
                    ]
                ]
            ]
        ]
    ]
}

private func entityMutation(
    key: String,
    id: String? = nil,
    author: String? = nil,
    text: String? = nil,
    toolbar: [String: Any]? = nil
) -> [String: Any] {
    var payload: [String: Any] = [:]
    if let id {
        payload["commentEntityPayload"] = [
            "properties": ["commentId": id, "content": ["content": text ?? ""]],
            "author": ["displayName": author ?? ""],
        ]
    }
    if let toolbar { payload["engagementToolbarStateEntityPayload"] = toolbar }
    return ["entityKey": key, "payload": payload]
}

private func legacyComment(id: String, text: String) -> [String: Any] {
    [
        "commentId": id,
        "authorText": ["simpleText": "Legacy author"],
        "contentText": ["simpleText": text],
        "voteCount": ["simpleText": "3"],
        "publishedTimeText": ["simpleText": "1 day ago"],
    ]
}
