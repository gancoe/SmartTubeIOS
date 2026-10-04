#if os(tvOS)
import SmartTubeIOSCore
import SwiftUI

struct TVAutoplayOverlay: View {
    let video: Video
    let seconds: Int
    let onPlay: () -> Void
    let onCancel: () -> Void
    let onBrowse: () -> Void
    @FocusState private var playFocused: Bool?
    @Namespace private var focusNamespace

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(alignment: .leading, spacing: 18) {
                    Text("Up next in \(seconds)s").font(.headline)
                    Text(video.title).font(.title3).lineLimit(2)
                    Text(video.channelTitle).font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 28) {
                        Button("Play now", action: onPlay)
                            .focused($playFocused, equals: true)
                            .prefersDefaultFocus(in: focusNamespace)
                        Button("Cancel", action: onCancel)
                            .focused($playFocused, equals: false)
                    }
                    Text("Press Down to browse recommendations").font(.caption).foregroundStyle(.secondary)
                }
                .padding(32)
                .frame(width: 620, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            }
            .padding(50)
        }
        .focusScope(focusNamespace)
        .defaultFocus($playFocused, true)
        .task {
            try? await Task.sleep(for: TVPlayerFocus.settleDelay)
            guard !Task.isCancelled else { return }
            playFocused = true
        }
        .onMoveCommand { direction in
            switch direction {
            case .left: playFocused = true
            case .right: playFocused = false
            case .down: onBrowse()
            case .up: onCancel()
            @unknown default: break
            }
        }
        .onExitCommand(perform: onCancel)
        .onPlayPauseCommand(perform: onPlay)
    }
}
#endif
