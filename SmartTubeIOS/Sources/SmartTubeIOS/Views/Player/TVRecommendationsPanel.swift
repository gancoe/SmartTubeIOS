#if os(tvOS)
import SmartTubeIOSCore
import SwiftUI

enum PlayerRecommendationsAccessibility {
    static let panel = "player.recommendations"
    static func video(_ id: String) -> String { "player.recommendations.video.\(id)" }
}

enum TVPlayerFocus {
    static let settleDelay = Duration.milliseconds(50)
}

struct TVRecommendationsPanel: View {
    let videos: [Video]
    let onSelect: (Video) -> Void
    let onDismiss: () -> Void
    @FocusState private var focusedVideoID: String?
    @FocusState private var emptyStateFocused: Bool
    @Namespace private var focusNamespace

    var body: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text("Recommended videos").font(.title3.bold())
                    Spacer()
                    Text("Back to return to video").font(.caption).foregroundStyle(.secondary)
                }
                if videos.isEmpty {
                    VStack(alignment: .leading, spacing: 24) {
                        Text("No recommendations available yet.").foregroundStyle(.secondary)
                        Button("Back to video", action: onDismiss)
                            .focused($emptyStateFocused)
                            .prefersDefaultFocus(in: focusNamespace)
                    }
                    .frame(height: 240)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal) {
                            HStack(alignment: .top, spacing: 30) {
                                ForEach(videos) { video in
                                    Button {
                                        onSelect(video)
                                    } label: {
                                        recommendation(video)
                                    }
                                    .buttonStyle(.plain)
                                    .focused($focusedVideoID, equals: video.id)
                                    .prefersDefaultFocus(video.id == videos.first?.id, in: focusNamespace)
                                    .accessibilityIdentifier(PlayerRecommendationsAccessibility.video(video.id))
                                    .id(video.id)
                                }
                            }
                            .padding(12)
                        }
                        .scrollIndicators(.hidden)
                        .defaultFocus($focusedVideoID, videos.first?.id)
                        .onChange(of: focusedVideoID) { _, id in
                            if let id {
                                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .center) }
                            }
                        }
                    }
                }
            }
            .padding(40)
            .background(.ultraThinMaterial)
            .accessibilityIdentifier(PlayerRecommendationsAccessibility.panel)
        }
        .focusScope(focusNamespace)
        .ignoresSafeArea(edges: .bottom)
        .onMoveCommand { direction in
            switch direction {
            case .up: onDismiss()
            case .left: moveFocus(by: -1)
            case .right: moveFocus(by: 1)
            default: break
            }
        }
        .onExitCommand(perform: onDismiss)
        .task {
            try? await Task.sleep(for: TVPlayerFocus.settleDelay)
            guard !Task.isCancelled else { return }
            if videos.isEmpty {
                emptyStateFocused = true
            } else {
                focusedVideoID = videos.first?.id
            }
        }
        .onChange(of: videos.map(\.id)) { _, ids in
            if focusedVideoID == nil || !ids.contains(focusedVideoID ?? "") { focusedVideoID = ids.first }
        }
    }

    private func moveFocus(by offset: Int) {
        guard !videos.isEmpty else { return }
        let current = videos.firstIndex { $0.id == focusedVideoID } ?? 0
        focusedVideoID = videos[min(max(current + offset, 0), videos.count - 1)].id
    }

    private func recommendation(_ video: Video) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            AsyncImage(url: video.thumbnailURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.white.opacity(0.1)
            }
            .frame(width: 330, height: 186)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12))
            Text(video.title).font(.headline).lineLimit(2)
            Text(video.channelTitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            if !video.formattedDuration.isEmpty {
                Text(video.formattedDuration).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(width: 330, alignment: .leading)
        .padding(10)
        .background(focusedVideoID == video.id ? Color.white.opacity(0.15) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(focusedVideoID == video.id ? Color.white : .clear, lineWidth: 3)
        }
    }
}
#endif
