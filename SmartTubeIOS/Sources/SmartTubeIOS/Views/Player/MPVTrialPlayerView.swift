#if os(tvOS)
import SmartTubeIOSCore
import SwiftUI
import UIKit

struct MPVTrialPlayerView: View {
    let session: MPVPlaybackSession
    let title: String
    let videoID: String
    let reportID: String
    let segments: [SponsorSegment]
    let settings: AppSettings
    let onReturn: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var resumeAfterBackground = false
    @State private var controlsVisible = true
    @State private var statsVisible = false
    @State private var pendingSponsorTarget: Double?
    @FocusState private var focused: Control?

    private enum Control: Hashable {
        case back, rewind, playPause, forward, speed, stats, skip
    }

    private var sponsorDecision: SponsorSkipDecision {
        SponsorBlockDecisionEngine.decide(
            at: session.currentTime, segments: segments, settings: settings,
            isSkipInProgress: pendingSponsorTarget != nil, duration: session.duration
        )
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            MPVVideoSurface(session: session).ignoresSafeArea()
                .allowsHitTesting(false)
            if session.isBuffering { ProgressView().scaleEffect(2) }
            if let error = session.errorMessage {
                VStack(spacing: 20) {
                    Text("MPV could not play this stream")
                    Text(error).font(.caption)
                    Button("Return to AVPlayer", action: onReturn)
                }
                .padding(40).background(.black.opacity(0.85))
            } else if controlsVisible || session.hasEnded {
                controls
            } else {
                Color.clear
                    .contentShape(Rectangle())
                    .focusable()
                    .onTapGesture { revealControls() }
                    .onMoveCommand { _ in revealControls() }
            }
            if statsVisible {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Player: MPV · same HLS source")
                    Text(
                        String(
                            format: "Resolution: %d×%d @ %.1f fps", session.videoWidth, session.videoHeight, session.fps
                        ))
                    Text("Codec: \(session.codecName ?? "—") · decoder: \(session.decoderName ?? "—")")
                    Text(String(format: "Cache download: %.1f Mbps", session.downloadMbps))
                    Text(String(format: "Speed: %.2f×", session.rate))
                    Text(
                        String(
                            format: "Buffer: %.1f s · viewing: %.1f s", session.bufferSeconds,
                            session.bufferSeconds / max(0.1, session.rate)))
                    Text(session.isBuffering ? "Waiting for media" : "Playing: \(session.isPlaying ? "yes" : "no")")
                    Text("MPV logs are separate from AVPlayer diagnostics")
                }
                .font(.system(.caption, design: .monospaced))
                .padding(24).background(.black.opacity(0.8))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(40)
                .allowsHitTesting(false)
            }
        }
        .onPlayPauseCommand { session.togglePlayback() }
        .task { await session.monitorDiagnostics(videoID: videoID, reportID: reportID) }
        .onExitCommand {
            if statsVisible {
                statsVisible = false
            } else if controlsVisible {
                controlsVisible = false
            } else {
                onReturn()
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = session.isPlaying
            focused = .playPause
        }
        .onChange(of: session.isPlaying) { _, playing in
            UIApplication.shared.isIdleTimerDisabled = playing
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                resumeAfterBackground = session.isPlaying && !settings.backgroundPlaybackEnabled
                if !settings.backgroundPlaybackEnabled { session.setPlaying(false) }
                session.setVideoOutputEnabled(false)
            } else if phase == .active {
                session.setVideoOutputEnabled(true)
                if resumeAfterBackground { session.setPlaying(true) }
                resumeAfterBackground = false
            }
        }
        .onChange(of: session.currentTime) { _, time in
            if let target = pendingSponsorTarget, !session.isSeeking, time >= target {
                pendingSponsorTarget = nil
            }
            if case .skip(let target, _) = sponsorDecision {
                pendingSponsorTarget = target
                session.seek(to: target)
            } else if case .skipToPlaybackEnd = sponsorDecision {
                pendingSponsorTarget = session.duration
                session.seek(to: session.duration)
            }
        }
        .onDisappear {
            session.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private var controls: some View {
        VStack(spacing: 28) {
            HStack {
                Button("Return to AVPlayer", action: onReturn).focused($focused, equals: .back)
                Spacer()
                Text("MPV · Experimental").foregroundStyle(.secondary)
            }
            Text(title).font(.title2).lineLimit(2)
            Spacer()
            if case .showToast(let segment) = sponsorDecision {
                Button("Skip \(segment.category.displayName)") {
                    pendingSponsorTarget = segment.end
                    session.seek(to: segment.end)
                }.focused($focused, equals: .skip)
            }
            HStack(spacing: 40) {
                Button("−10 s") { seekRelative(-10) }.focused($focused, equals: .rewind)
                Button(session.isPlaying ? "Pause" : "Play") { session.togglePlayback() }
                    .focused($focused, equals: .playPause)
                Button("+30 s") { seekRelative(30) }.focused($focused, equals: .forward)
                Menu(String(format: "Speed %.2f×", session.rate)) {
                    ForEach([1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { speed in
                        Button(String(format: "%.2f×", speed)) { session.setRate(speed) }
                    }
                }.focused($focused, equals: .speed)
                Button("Stats") { statsVisible.toggle() }.focused($focused, equals: .stats)
            }
            .disabled(!session.isReady)
            ProgressView(value: min(session.currentTime, max(1, session.duration)), total: max(1, session.duration))
            HStack {
                Text(clock(session.currentTime))
                Spacer()
                Text(clock(session.duration))
            }.font(.caption.monospacedDigit())
            Button("Hide controls") { controlsVisible = false }
            Text("Back hides controls; Back again returns to AVPlayer.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(70)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.65), .clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom))
    }

    private func revealControls() {
        controlsVisible = true
        focused = .playPause
    }

    private func seekRelative(_ delta: Double) {
        pendingSponsorTarget = nil
        session.seek(to: max(0, min(session.duration, session.currentTime + delta)))
    }

    private func clock(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let value = max(0, Int(seconds))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
#endif
