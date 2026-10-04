import AVFoundation
import Foundation

extension PlaybackViewModel {
    func monitorPlaybackDiagnostics() async {
        guard let configuration = PlaybackDiagnosticsConfiguration(),
            let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return }
        guard let stateRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return }
        await monitorPlaybackDiagnostics(configuration: configuration, cache: cache, stateRoot: stateRoot)
    }

    func monitorPlaybackDiagnostics(
        configuration: PlaybackDiagnosticsConfiguration, cache: URL, stateRoot: URL
    ) async {
        if playbackDiagnosticsReporter == nil {
            playbackDiagnosticsReporter = PlaybackDiagnosticsReporter(
                configuration: configuration,
                storeURL: cache.appendingPathComponent("PlaybackDiagnostics/pending.json"))
        }
        guard let reporter = playbackDiagnosticsReporter else { return }
        if let previousOwner = playbackDiagnosticsMetricGate.ownerToken {
            endPlaybackDiagnosticsOwner(ownerToken: previousOwner)
        }
        let ownerToken = playbackDiagnosticsMetricGate.activate()
        if let captureID = configuration.captureID {
            playbackDiagnosticsCaptureSession = PlaybackDiagnosticsCaptureSession(
                captureID: captureID,
                stateURL: stateRoot.appendingPathComponent("PlaybackDiagnostics/capture-state.json"))
            installPlaybackDiagnosticsItemObserver(ownerToken: ownerToken)
            schedulePlaybackDiagnosticsExpiry(ownerToken: ownerToken)
        }
        defer {
            if playbackDiagnosticsMetricGate.ownerToken == ownerToken {
                endPlaybackDiagnosticsOwner(ownerToken: ownerToken)
                playbackDiagnosticsCaptureSession = nil
            }
        }
        await withTaskCancellationHandler {
            while !Task.isCancelled, playbackDiagnosticsMetricGate.ownerToken == ownerToken {
                playbackDiagnosticsCaptureSession?.refresh()
                if configuration.captureID != nil,
                    playbackDiagnosticsCaptureSession?.isCapturing != true
                {
                    break
                }
                if let item = player.currentItem {
                    if let captureID = configuration.captureID {
                        startPlaybackDiagnosticsNativeMetrics(
                            for: item, reporter: reporter, captureID: captureID, ownerToken: ownerToken)
                    }
                    let events = samplePlaybackDiagnosticsEvents(
                        for: item, configuration: configuration, ownerToken: ownerToken)
                    await reporter.enqueue(events)
                }
                await reporter.flush()
                do { try await Task.sleep(for: PlaybackDiagnosticsSampler.interval) } catch { return }
            }
        } onCancel: { [weak self] in
            Task { @MainActor [weak self] in
                self?.endPlaybackDiagnosticsOwner(ownerToken: ownerToken)
            }
        }
    }

    func samplePlaybackDiagnosticsEvents(
        for item: AVPlayerItem, configuration: PlaybackDiagnosticsConfiguration, ownerToken: UUID
    ) -> [PlaybackDeliveryEvent] {
        updateStatsSnapshot()
        let snapshot = statsSnapshot
        let nativeErrors = item.errorLog()?.events ?? []
        let now = Date()
        let state = [
            snapshot.videoId, snapshot.displayResolution, snapshot.streamType,
            snapshot.itemStatus, snapshot.playerTimeControlStatus, snapshot.waitingReason,
            snapshot.itemError, snapshot.playerError, "\(snapshot.playerRate ?? 0)",
        ].joined(separator: "|")
        let decision = playbackDiagnosticsSampler.sample(
            itemID: ObjectIdentifier(item), errorCount: nativeErrors.count, state: state, at: now)
        let access = item.accessLog()?.events.last
        var events: [PlaybackDeliveryEvent] = []
        if decision.emitSnapshot {
            events.append(
                Self.deliveryEvent(
                    snapshot, advertisedBitrate: access?.indicatedBitrate,
                    observedBitrate: access?.observedBitrate,
                    playbackPosition: item.currentTime().seconds, at: now,
                    captureID: configuration.captureID,
                    itemGenerationID: playbackDiagnosticsItemGenerationID,
                    captureState: playbackDiagnosticsCaptureSession?.state.rawValue))
        }
        for index in decision.errorIndices {
            let nativeError = nativeErrors[index]
            if nativeError.errorDomain == "CoreMediaErrorDomain" {
                playbackDiagnosticsCaptureSession?.note(
                    errorCode: nativeError.errorStatusCode, at: nativeError.date ?? now)
                schedulePlaybackDiagnosticsExpiry(ownerToken: ownerToken)
            }
            var errorSnapshot = snapshot
            errorSnapshot.errorLog = Self.errorLogSummary(nativeError)
            errorSnapshot.errorLogDate = nativeError.date
            errorSnapshot.errorLogEventCount = index + 1
            errorSnapshot.errorLogComment = Self.errorLogCommentSummary(nativeError.errorComment)
            errorSnapshot.errorLogResource = Self.errorResourceSummary(nativeError.uri)
            events.append(
                Self.deliveryEvent(
                    errorSnapshot, advertisedBitrate: access?.indicatedBitrate,
                    observedBitrate: access?.observedBitrate,
                    playbackPosition: item.currentTime().seconds, at: now,
                    captureID: configuration.captureID,
                    itemGenerationID: playbackDiagnosticsItemGenerationID,
                    captureState: playbackDiagnosticsCaptureSession?.state.rawValue))
        }
        return events
    }

    func installPlaybackDiagnosticsItemObserver(ownerToken: UUID) {
        playbackDiagnosticsItemObservation?.invalidate()
        let observedPlayer = player
        playbackDiagnosticsItemObservation = observedPlayer.observe(
            \AVPlayer.currentItem, options: [.initial, .new]
        ) { [weak self] sourcePlayer, _ in
            Task { @MainActor [weak self, weak sourcePlayer] in
                guard let self, let sourcePlayer, self.player === sourcePlayer,
                    self.playbackDiagnosticsMetricGate.ownerToken == ownerToken,
                    !self.playbackDiagnosticsMetricGate.suspended,
                    let session = self.playbackDiagnosticsCaptureSession,
                    let reporter = self.playbackDiagnosticsReporter
                else { return }
                session.refresh()
                guard session.isCapturing else { return }
                guard let item = sourcePlayer.currentItem else {
                    self.cancelPlaybackDiagnosticsNativeMetrics()
                    return
                }
                self.startPlaybackDiagnosticsNativeMetrics(
                    for: item, reporter: reporter, captureID: session.captureID,
                    ownerToken: ownerToken)
            }
        }
    }

    func rebindPlaybackDiagnosticsPlayer() {
        guard let ownerToken = playbackDiagnosticsMetricGate.ownerToken,
            playbackDiagnosticsCaptureSession != nil
        else { return }
        cancelPlaybackDiagnosticsNativeMetrics()
        installPlaybackDiagnosticsItemObserver(ownerToken: ownerToken)
    }

    func startPlaybackDiagnosticsNativeMetrics(
        for item: AVPlayerItem, reporter: PlaybackDiagnosticsReporter,
        captureID: UUID, ownerToken: UUID
    ) {
        guard #available(tvOS 18.0, iOS 18.0, macOS 15.0, *),
            let session = playbackDiagnosticsCaptureSession,
            session.captureID == captureID, player.currentItem === item
        else { return }
        session.refresh()
        let oldGeneration = playbackDiagnosticsMetricGate.generation
        guard
            let generation = playbackDiagnosticsMetricGate.bind(
                ownerToken: ownerToken, player: player, item: item, eligible: session.isCapturing)
        else { return }
        guard generation != oldGeneration else { return }
        playbackDiagnosticsMetricTasks.forEach { $0.cancel() }
        playbackDiagnosticsMetricTasks.removeAll()
        playbackDiagnosticsItemGenerationID = generation
        let sourcePlayer = player
        let segmentTask = Task { @MainActor [weak self, weak item, weak sourcePlayer] in
            guard let item, let sourcePlayer else { return }
            do {
                for try await metric in item.metrics(forType: AVMetricHLSMediaSegmentRequestEvent.self) {
                    guard !Task.isCancelled, let self else { return }
                    let result = PlaybackNativeDiagnosticsMapper.segmentResult(from: metric)
                    guard
                        let base = self.nativePlaybackDiagnosticsEvent(
                            ownerToken: ownerToken, generation: generation, source: (sourcePlayer, item),
                            timestamp: metric.date, mediaTime: metric.mediaTime,
                            errorDomain: result.segment.errorDomain, errorCode: result.segment.errorCode
                        )
                    else { return }
                    self.playbackDiagnosticsDroppedNativeEvents += result.droppedTransactions
                    let event = base.withNativeSegment(result.segment)
                        .withDroppedEvents(self.playbackDiagnosticsDroppedNativeEvents)
                    await reporter.enqueue([event])
                }
            } catch { return }
        }
        let variantTask = Task { @MainActor [weak self, weak item, weak sourcePlayer] in
            guard let item, let sourcePlayer else { return }
            do {
                for try await metric in item.metrics(forType: AVMetricPlayerItemVariantSwitchEvent.self) {
                    guard !Task.isCancelled, let self else { return }
                    guard
                        let base = self.nativePlaybackDiagnosticsEvent(
                            ownerToken: ownerToken, generation: generation, source: (sourcePlayer, item),
                            timestamp: metric.date, mediaTime: metric.mediaTime
                        )
                    else { return }
                    await reporter.enqueue([
                        base.withNativeVariantSwitch(
                            PlaybackNativeDiagnosticsMapper.variantSwitch(from: metric))
                    ])
                }
            } catch { return }
        }
        playbackDiagnosticsMetricTasks = [segmentTask, variantTask]
    }

    func nativePlaybackDiagnosticsEvent(
        ownerToken: UUID, generation: UUID, source: (player: AVPlayer, item: AVPlayerItem),
        timestamp: Date, mediaTime: CMTime,
        errorDomain: String? = nil, errorCode: Int? = nil, now: Date = Date()
    ) -> PlaybackDeliveryEvent? {
        let (sourcePlayer, item) = source
        guard let session = playbackDiagnosticsCaptureSession else { return nil }
        session.refresh(at: now)
        guard player === sourcePlayer, player.currentItem === item,
            playbackDiagnosticsMetricGate.accepts(
                ownerToken: ownerToken, generation: generation, player: sourcePlayer,
                item: item, eligible: session.isCapturing)
        else { return nil }
        if errorDomain == "CoreMediaErrorDomain" {
            session.note(errorCode: errorCode, at: timestamp)
            schedulePlaybackDiagnosticsExpiry(ownerToken: ownerToken)
        }
        guard session.isCapturing else { return nil }
        updateStatsSnapshot()
        let access = item.accessLog()?.events.last
        return Self.deliveryEvent(
            statsSnapshot, advertisedBitrate: access?.indicatedBitrate,
            observedBitrate: access?.observedBitrate,
            playbackPosition: mediaTime.seconds, at: timestamp,
            captureID: session.captureID, itemGenerationID: generation,
            captureState: session.state.rawValue)
    }

    func suspendPlaybackDiagnostics() {
        playbackDiagnosticsMetricGate.suspend()
        cancelPlaybackDiagnosticsNativeMetrics()
    }

    func cancelPlaybackDiagnosticsNativeMetrics() {
        playbackDiagnosticsMetricTasks.forEach { $0.cancel() }
        playbackDiagnosticsMetricTasks.removeAll()
        playbackDiagnosticsItemGenerationID = nil
        playbackDiagnosticsMetricGate.invalidateItem()
    }

    func endPlaybackDiagnosticsOwner(ownerToken: UUID) {
        guard playbackDiagnosticsMetricGate.ownerToken == ownerToken else { return }
        cancelPlaybackDiagnosticsNativeMetrics()
        playbackDiagnosticsMetricGate.deactivate(ownerToken: ownerToken)
        playbackDiagnosticsExpiryTask?.cancel()
        playbackDiagnosticsExpiryTask = nil
        playbackDiagnosticsItemObservation?.invalidate()
        playbackDiagnosticsItemObservation = nil
    }

    func expirePlaybackDiagnosticsCapture(ownerToken: UUID, at now: Date) {
        guard playbackDiagnosticsMetricGate.ownerToken == ownerToken,
            let session = playbackDiagnosticsCaptureSession
        else { return }
        session.refresh(at: now)
        if !session.isCapturing { endPlaybackDiagnosticsOwner(ownerToken: ownerToken) }
    }

    func schedulePlaybackDiagnosticsExpiry(ownerToken: UUID) {
        playbackDiagnosticsExpiryTask?.cancel()
        guard let session = playbackDiagnosticsCaptureSession else { return }
        let delay = max(0, session.endsAt.timeIntervalSinceNow)
        playbackDiagnosticsExpiryTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            self?.expirePlaybackDiagnosticsCapture(ownerToken: ownerToken, at: Date())
        }
    }

    static func deliveryEvent(
        _ snapshot: StatsForNerdsSnapshot, advertisedBitrate: Double?, observedBitrate: Double?,
        playbackPosition: Double? = nil, at now: Date, captureID: UUID? = nil,
        itemGenerationID: UUID? = nil, captureState: String? = nil
    ) -> PlaybackDeliveryEvent {
        func safeText(_ value: String, pattern: String, fallback: String = "unknown") -> String {
            value.range(of: pattern, options: .regularExpression) == value.startIndex..<value.endIndex
                ? value : fallback
        }
        func finiteNonnegative(_ value: Double?) -> Double? {
            guard let value, value.isFinite, value >= 0 else { return nil }
            return value
        }
        let errorParts = snapshot.errorLog.split(separator: "#", maxSplits: 1).map(String.init)
        let domain =
            errorParts.count == 2
            ? safeText(errorParts[0], pattern: #"^[A-Za-z0-9_.-]{1,80}$"#, fallback: "") : ""
        let code = domain.isEmpty ? nil : Int(errorParts[1])
        let rate = snapshot.playerRate.map(Double.init).flatMap { value -> Double? in
            value.isFinite && (0...4).contains(value) ? value : nil
        }
        let resolution = snapshot.displayResolution.replacingOccurrences(of: "×", with: "x")
        return PlaybackDeliveryEvent(
            timestamp: now,
            reportID: safeText(snapshot.reportID, pattern: #"^[A-Za-z0-9_-]{1,64}$"#),
            videoID: safeText(snapshot.videoId, pattern: #"^[A-Za-z0-9_-]{1,64}$"#),
            resolution: safeText(resolution, pattern: #"^[0-9]+x[0-9]+$"#),
            rate: rate,
            bufferMediaSeconds: finiteNonnegative(snapshot.bufferAheadSeconds),
            bufferViewingSeconds: finiteNonnegative(snapshot.bufferViewingSeconds),
            itemStatus: snapshot.itemStatus,
            playbackStatus: snapshot.playerTimeControlStatus,
            waitingReason: snapshot.waitingReason,
            streamRoute: safeText(snapshot.streamType, pattern: #"^[A-Za-z0-9/._ -]{1,100}$"#),
            advertisedBitrateBps: finiteNonnegative(advertisedBitrate).flatMap { $0 > 0 ? $0 : nil },
            observedBitrateBps: finiteNonnegative(observedBitrate).flatMap { $0 > 0 ? $0 : nil },
            downloadedBytes: snapshot.downloadedBytes,
            droppedFrames: max(0, snapshot.droppedFrames),
            stalls: max(0, snapshot.stalls),
            peakBitrateBps: finiteNonnegative(snapshot.peakBitrateLimit),
            accessEventCount: max(0, snapshot.accessLogEventCount),
            errorEventCount: max(0, snapshot.errorLogEventCount),
            errorDomain: code == nil ? nil : domain,
            errorCode: code,
            errorTimestamp: snapshot.errorLogDate,
            errorComment: snapshot.errorLogComment == "—" ? "—" : Self.errorLogCommentSummary(snapshot.errorLogComment),
            errorResource: snapshot.errorLogResource,
            playbackPositionSeconds: finiteNonnegative(playbackPosition), captureID: captureID,
            itemGenerationID: itemGenerationID,
            captureState: captureState)
    }

}
