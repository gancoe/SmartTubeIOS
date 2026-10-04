import Foundation

// MARK: - Comment response parsing

extension InnerTubeAPI {
    /// Finds the comments continuation token inside the `engagementPanels` of a
    /// `/next` response — looks for the panel whose `panelIdentifier` or header title
    /// contains "comment".
    func parseCommentsContinuationToken(from json: [String: Any]) -> String? {
        guard let panels = json["engagementPanels"] as? [[String: Any]] else { return nil }
        for panel in panels {
            guard let pslr = panel["engagementPanelSectionListRenderer"] as? [String: Any] else { continue }
            let panelId = pslr["panelIdentifier"] as? String ?? ""
            let headerTitle: String = {
                let header = pslr["header"] as? [String: Any]
                let thr = header?["engagementPanelTitleHeaderRenderer"] as? [String: Any]
                return (thr?["title"] as? [String: Any]).flatMap { extractText($0) } ?? ""
            }()
            guard panelId.lowercased().contains("comment") || headerTitle.lowercased().contains("comment") else {
                continue
            }
            var found: String?
            func findToken(_ value: Any, depth: Int = 0) {
                guard found == nil else { return }
                guard depth < 50 else { return }
                if let dictionary = value as? [String: Any] {
                    if let continuationItem = dictionary["continuationItemRenderer"] as? [String: Any],
                        let endpoint = continuationItem["continuationEndpoint"] as? [String: Any],
                        let command = endpoint["continuationCommand"] as? [String: Any],
                        let token = command["token"] as? String
                    {
                        found = token
                        return
                    }
                    for child in dictionary.values { findToken(child, depth: depth + 1) }
                } else if let array = value as? [Any] {
                    for child in array { findToken(child, depth: depth + 1) }
                }
            }
            findToken(pslr["content"] as Any)
            if let token = found { return token }
        }
        return nil
    }

    private struct CommentEntityStore {
        let payloads: [String: [String: Any]]

        init(json: [String: Any]) {
            var payloads: [String: [String: Any]] = [:]
            let mutations =
                (((json["frameworkUpdates"] as? [String: Any])?["entityBatchUpdate"] as? [String: Any])?["mutations"]
                    as? [[String: Any]]) ?? []
            for mutation in mutations {
                guard let key = mutation["entityKey"] as? String,
                    let payload = mutation["payload"] as? [String: Any]
                else { continue }
                payloads[key] = payload
            }
            self.payloads = payloads
        }

        func commentPayload(for keys: [String]) -> [String: Any]? {
            for key in keys {
                guard let payload = payloads[key], payload["commentEntityPayload"] is [String: Any] else { continue }
                return payload
            }
            return nil
        }

        func toolbarPayload(for key: String?) -> [String: Any]? {
            guard let key, let payload = payloads[key] else { return nil }
            return payload["engagementToolbarStateEntityPayload"] as? [String: Any]
        }
    }

    func parseCommentPage(from json: [String: Any]) -> CommentPage {
        let entities = CommentEntityStore(json: json)
        var comments: [Comment] = []
        var continuation: String?

        for items in topLevelContinuationItems(from: json) {
            for item in items {
                if let thread = item["commentThreadRenderer"] as? [String: Any],
                    let comment = parseThread(thread, entities: entities)
                {
                    comments.append(comment)
                } else if let comment = parseCommentItem(item, entities: entities) {
                    comments.append(comment)
                } else if item["continuationItemRenderer"] != nil {
                    continuation = continuation ?? continuationToken(from: item)
                }
            }
        }
        return CommentPage(comments: comments, continuation: continuation)
    }

    private func topLevelContinuationItems(from json: [String: Any]) -> [[[String: Any]]] {
        var result: [[[String: Any]]] = []
        let endpoints = ["onResponseReceivedEndpoints", "onResponseReceivedActions"].compactMap {
            json[$0] as? [[String: Any]]
        }.flatMap { $0 }
        for endpoint in endpoints {
            if let action = endpoint["appendContinuationItemsAction"] as? [String: Any],
                let items = action["continuationItems"] as? [[String: Any]]
            {
                result.append(items)
            }
            if let action = endpoint["reloadContinuationItemsCommand"] as? [String: Any],
                let items = action["continuationItems"] as? [[String: Any]]
            {
                result.append(items)
            }
        }
        if result.isEmpty, let items = json["continuationItems"] as? [[String: Any]] { result.append(items) }
        return result
    }

    private func parseThread(_ thread: [String: Any], entities: CommentEntityStore) -> Comment? {
        let viewModel =
            ((thread["commentViewModel"] as? [String: Any])?["commentViewModel"] as? [String: Any])
            ?? (thread["commentViewModel"] as? [String: Any])
        guard let comment = parseCommentItem(viewModel ?? thread, entities: entities) else { return nil }

        let repliesRenderer = ((thread["replies"] as? [String: Any])?["commentRepliesRenderer"] as? [String: Any])
        var inlineReplies: [Comment] = []
        var repliesContinuation: String?
        if let repliesRenderer {
            let replyItems =
                ((repliesRenderer["contents"] as? [[String: Any]]) ?? [])
                + ((repliesRenderer["subThreads"] as? [[String: Any]]) ?? [])
            for item in replyItems {
                if let nestedThread = item["commentThreadRenderer"] as? [String: Any],
                    let reply = parseThread(nestedThread, entities: entities)
                {
                    inlineReplies.append(reply)
                } else if let reply = parseCommentItem(item, entities: entities) {
                    inlineReplies.append(reply)
                } else if item["continuationItemRenderer"] != nil {
                    repliesContinuation = repliesContinuation ?? continuationToken(from: item)
                }
            }
            repliesContinuation = repliesContinuation ?? firstContinuationToken(in: repliesRenderer)
        }

        let replyCount =
            viewModel.flatMap { intValue($0["replyCount"]) ?? intValue($0["replyCountA11y"]) }
            ?? intValue(thread["replyCount"])
            ?? intValue(thread["replyCountA11y"])
        return Comment(
            id: comment.id,
            author: comment.author,
            authorAvatarURL: comment.authorAvatarURL,
            text: comment.text,
            likeCount: comment.likeCount,
            publishedTime: comment.publishedTime,
            isLiked: comment.isLiked,
            replyCount: replyCount,
            repliesContinuation: repliesContinuation,
            inlineReplies: inlineReplies)
    }

    private func parseCommentItem(_ item: [String: Any], entities: CommentEntityStore) -> Comment? {
        if item["commentKey"] is String {
            let keys = [item["commentKey"], item["toolbarStateKey"]].compactMap { $0 as? String }
            return parseEntityComment(viewModel: item, keys: keys, entities: entities)
        }
        if let viewModel = item["commentViewModel"] as? [String: Any] {
            let nested = (viewModel["commentViewModel"] as? [String: Any]) ?? viewModel
            let keys = [nested["commentKey"], nested["toolbarStateKey"]].compactMap { $0 as? String }
            return parseEntityComment(viewModel: nested, keys: keys, entities: entities)
        }
        if let renderer = item["commentRenderer"] as? [String: Any] { return parseLegacyComment(renderer) }
        if let renderer = (item["comment"] as? [String: Any])?["commentRenderer"] as? [String: Any] {
            return parseLegacyComment(renderer)
        }
        if let renderer = item["replyRenderer"] as? [String: Any] {
            if let comment = renderer["commentRenderer"] as? [String: Any] { return parseLegacyComment(comment) }
            if let comment = (renderer["comment"] as? [String: Any])?["commentRenderer"] as? [String: Any] {
                return parseLegacyComment(comment)
            }
            for key in ["contents", "subThreads"] {
                if let children = renderer[key] as? [[String: Any]] {
                    for child in children {
                        if let comment = parseCommentItem(child, entities: entities) { return comment }
                    }
                }
            }
            return parseLegacyComment(renderer)
        }
        return nil
    }

    private func parseEntityComment(
        viewModel: [String: Any], keys: [String], entities: CommentEntityStore
    ) -> Comment? {
        guard let payload = entities.commentPayload(for: keys),
            let entity = payload["commentEntityPayload"] as? [String: Any],
            let properties = entity["properties"] as? [String: Any],
            let id = properties["commentId"] as? String
        else { return nil }
        let author = entity["author"] as? [String: Any]
        let toolbar =
            entity["toolbar"] as? [String: Any]
            ?? entities.toolbarPayload(for: viewModel["toolbarStateKey"] as? String)
        let likeCount =
            stringValue(toolbar?["likeCountA11y"])
            ?? stringValue(toolbar?["likeCountNotliked"])
            ?? stringValue(toolbar?["likeCount"])
            ?? ""
        let content = (properties["content"] as? [String: Any]).flatMap { $0["content"] as? String } ?? ""
        return Comment(
            id: id,
            author: author?["displayName"] as? String ?? "",
            authorAvatarURL: (author?["avatarThumbnailUrl"] as? String).flatMap(URL.init(string:)),
            text: content,
            likeCount: likeCount,
            publishedTime: properties["publishedTime"] as? String ?? "",
            isLiked: stringValue(toolbar?["likeState"]) == "LIKE_STATE_LIKED")
    }

    private func parseLegacyComment(_ renderer: [String: Any]) -> Comment? {
        guard let id = renderer["commentId"] as? String else { return nil }
        let avatarURL = ((renderer["authorThumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]])?
            .last.flatMap { ($0["url"] as? String).flatMap(URL.init(string:)) }
        return Comment(
            id: id,
            author: (renderer["authorText"] as? [String: Any]).flatMap(extractText) ?? "",
            authorAvatarURL: avatarURL,
            text: (renderer["contentText"] as? [String: Any]).flatMap(extractText) ?? "",
            likeCount: (renderer["voteCount"] as? [String: Any]).flatMap(extractText) ?? "",
            publishedTime: (renderer["publishedTimeText"] as? [String: Any]).flatMap(extractText) ?? "",
            isLiked: renderer["isLiked"] as? Bool ?? false)
    }

    private func firstContinuationToken(in object: Any) -> String? {
        if let dict = object as? [String: Any] {
            if dict["continuationItemRenderer"] != nil, let token = continuationToken(from: dict) { return token }
            for value in dict.values {
                if let token = firstContinuationToken(in: value) { return token }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let token = firstContinuationToken(in: value) { return token }
            }
        }
        return nil
    }

    private func continuationToken(from item: [String: Any]) -> String? {
        func walk(_ value: Any, depth: Int = 0) -> String? {
            guard depth < 12 else { return nil }
            if let dict = value as? [String: Any] {
                if let token = dict["token"] as? String { return token }
                for child in dict.values {
                    if let token = walk(child, depth: depth + 1) { return token }
                }
            } else if let array = value as? [Any] {
                for child in array {
                    if let token = walk(child, depth: depth + 1) { return token }
                }
            }
            return nil
        }
        return walk(item)
    }

    private func stringValue(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        guard let value = value as? String else { return nil }
        return Int(value.filter(\.isNumber))
    }

}
