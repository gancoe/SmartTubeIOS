#if os(tvOS)
import SmartTubeIOSCore
import SwiftUI

struct MPVTrialReturnState {
    let video: Video
    let position: Double
    let rate: Double
    let isPlaying: Bool
}

extension PlayerView {
    var moreMenuEngineRow: some View {
        Button {
            guard let source = vm.availableEngineTrialSource else { return }
            let session = MPVPlaybackSession(
                url: source.url, headers: source.headers,
                position: vm.currentTime, rate: store.settings.playbackSpeed,
                isPlaying: vm.isPlaying
            )
            showMoreMenu = false
            vm.suspendForEngineTrial()
            mpvTrial = session
        } label: {
            HStack {
                Text("Player")
                Spacer()
                Text("AVPlayer → MPV (experimental)").foregroundStyle(.secondary)
            }
            .padding()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(vm.availableEngineTrialSource == nil)
        .background(moreMenuFocusedRow == .engine ? Color.gray.opacity(0.35) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .focused($moreMenuFocusedRow, equals: .engine)
    }

    func finishMPVTrial() {
        guard let session = mpvTrial else { return }
        mpvReturnState = MPVTrialReturnState(
            video: vm.currentVideo ?? video,
            position: session.currentTime, rate: session.rate, isPlaying: session.isPlaying
        )
        session.stop()
        mpvTrial = nil
    }

    func resumeAfterMPVTrial() {
        guard let state = mpvReturnState else { return }
        store.settings.playbackSpeed = state.rate
        vm.reloadAfterEngineTrial(video: state.video, position: state.position, rate: state.rate)
        playerFocused = true
    }
}
#endif
