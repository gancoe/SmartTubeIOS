#if os(tvOS) && canImport(Libmpv)

import Foundation
import Darwin
import Observation
import UIKit
import Libmpv

@MainActor
@Observable
final class MPVPlaybackSession {
    private enum PropertyID: UInt64 {
        case currentTime = 1
        case duration
        case rate
        case paused
        case buffering
        case bufferSeconds
        case videoWidth
        case videoHeight
        case decoderName
        case codecName
        case fps
        case downloadSpeed
        case droppedFrames
    }

    private let url: URL
    private let headers: [String: String]
    private let resumePosition: Double
    private let resumeRate: Double
    private var resumeIsPlaying: Bool
    @ObservationIgnored nonisolated(unsafe) private var handle: OpaquePointer?
    private var attachedLayer: CAMetalLayer?
    @ObservationIgnored nonisolated(unsafe) private var eventTask: Task<Void, Never>?
    private var nextCommandID: UInt64 = 1
    private var didLoadFile = false

    var currentTime: Double = 0
    var duration: Double = 0
    var rate: Double
    var isPlaying: Bool
    var isBuffering = false
    var bufferSeconds: Double = 0
    var videoWidth = 0
    var videoHeight = 0
    var errorMessage: String?
    var hasEnded = false
    var isSeeking = false
    var isReady: Bool { didLoadFile }
    var decoderName: String?
    var codecName: String?
    var fps: Double = 0
    var downloadMbps: Double = 0
    @ObservationIgnored var isStopped = false
    @ObservationIgnored var diagnosticsStalls = 0
    @ObservationIgnored var diagnosticsErrorEventCount = 0
    @ObservationIgnored var diagnosticsErrorCode: Int?
    @ObservationIgnored var diagnosticsErrorTimestamp: Date?
    @ObservationIgnored var diagnosticsDroppedFrames = 0
    @ObservationIgnored var diagnosticsWasBuffering = false

    init(
        url: URL,
        headers: [String: String] = [:],
        position: Double = 0,
        rate: Double = 1,
        isPlaying: Bool = true
    ) {
        self.url = url
        self.headers = headers
        self.resumePosition = max(0, position)
        self.resumeRate = rate.isFinite && rate > 0 ? rate : 1
        self.resumeIsPlaying = isPlaying
        self.currentTime = max(0, position)
        self.rate = self.resumeRate
        self.isPlaying = isPlaying
    }

    deinit {
        eventTask?.cancel()
        if let handle {
            mpv_set_wakeup_callback(handle, nil, nil)
            mpv_terminate_destroy(handle)
        }
    }

    func attach(to layer: CAMetalLayer) {
        guard attachedLayer !== layer else { return }
        guard handle == nil else { return }
        guard !isStopped else { return }
        attachedLayer = layer
        guard setlocale(LC_NUMERIC, "C") != nil else {
            recordDiagnosticsError(code: nil)
            attachedLayer = nil
            isPlaying = false
            isStopped = true
            errorMessage = "MPV startup failed at numeric locale"
            return
        }
        guard let newHandle = mpv_create() else {
            recordDiagnosticsError(code: nil)
            attachedLayer = nil
            isPlaying = false
            isStopped = true
            errorMessage = "MPV startup failed at create"
            return
        }
        handle = newHandle

        var windowID = Int64(Int(bitPattern: Unmanaged.passUnretained(layer).toOpaque()))
        let optionStatus = withUnsafeMutablePointer(to: &windowID) {
            mpv_set_option(newHandle, "wid", MPV_FORMAT_INT64, $0)
        }
        guard check(optionStatus, stage: "wid"),
            setOption("vo", value: "gpu-next"),
            setOption("gpu-api", value: "vulkan"),
            setOption("gpu-context", value: "moltenvk"),
            setOption("hwdec", value: "videotoolbox"),
            setOption("terminal", value: "no"),
            setOption("hls-bitrate", value: "max"),
            setOption("pause", value: "yes"),
            setOption("speed", value: String(resumeRate)),
            setOption("cache", value: "yes"),
            setOption("cache-secs", value: String(PlaybackTuning.mpvForwardBufferSeconds)),
            setOption("demuxer-max-bytes", value: String(PlaybackTuning.mpvForwardBufferBytes))
        else {
            shutdown()
            return
        }

        if resumePosition > 0, !setOption("start", value: String(resumePosition)) {
            shutdown()
            return
        }

        if !headers.isEmpty {
            let fields =
                headers
                .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
                .map { "\(escapeListValue($0.key)): \(escapeListValue($0.value))" }
                .joined(separator: ",")
            guard setOption("http-header-fields", value: fields) else {
                shutdown()
                return
            }
        }

        guard check(mpv_initialize(newHandle), stage: "initialize") else {
            shutdown()
            return
        }

        observeProperties(on: newHandle)
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            while !Task.isCancelled {
                guard self != nil else { return }
                self?.pollEvents()
                try? await Task.sleep(for: PlaybackTuning.mpvEventPollInterval)
            }
        }

        let loadStatus = commandAsync("loadfile", arguments: [url.absoluteString, "replace"])
        if loadStatus < 0 {
            errorMessage = "Playback command failed (\(loadStatus))"
        }
    }

    func togglePlayback() {
        setPlaying(!isPlaying)
    }

    func setPlaying(_ playing: Bool) {
        if !didLoadFile {
            resumeIsPlaying = playing
            isPlaying = playing
            return
        }
        guard let handle else { return }
        var pause: Int32 = playing ? 0 : 1
        guard check(mpv_set_property(handle, "pause", MPV_FORMAT_FLAG, &pause), stage: "pause") else { return }
        isPlaying = playing
    }

    func setVideoOutputEnabled(_ enabled: Bool) {
        guard let handle else { return }
        _ = mpv_set_property_string(handle, "vid", enabled ? "auto" : "no")
    }

    func seek(to position: Double) {
        guard position.isFinite, self.handle != nil else { return }
        isSeeking = true
        let seekStatus = commandAsync("seek", arguments: [String(max(0, position)), "absolute+exact"])
        if seekStatus < 0 {
            errorMessage = "Playback command failed (\(seekStatus))"
            isSeeking = false
        }
        currentTime = max(0, position)
        hasEnded = false
    }

    func setRate(_ newRate: Double) {
        guard newRate.isFinite, newRate > 0, let handle else { return }
        var value = newRate
        guard check(mpv_set_property(handle, "speed", MPV_FORMAT_DOUBLE, &value), stage: "speed") else { return }
        rate = newRate
    }

    func stop() {
        shutdown()
        isBuffering = false
    }

    private func initializePlaybackState() {
        guard didLoadFile else { return }
        setRate(resumeRate)
        guard let handle else { return }
        var pause: Int32 = resumeIsPlaying ? 0 : 1
        if check(mpv_set_property(handle, "pause", MPV_FORMAT_FLAG, &pause), stage: "pause") {
            isPlaying = resumeIsPlaying
        }
    }

    private func observeProperties(on handle: OpaquePointer) {
        observe(PropertyID.currentTime, name: "time-pos", format: MPV_FORMAT_DOUBLE, on: handle)
        observe(PropertyID.duration, name: "duration", format: MPV_FORMAT_DOUBLE, on: handle)
        observe(PropertyID.rate, name: "speed", format: MPV_FORMAT_DOUBLE, on: handle)
        observe(PropertyID.paused, name: "pause", format: MPV_FORMAT_FLAG, on: handle)
        observe(PropertyID.buffering, name: "paused-for-cache", format: MPV_FORMAT_FLAG, on: handle)
        observe(PropertyID.bufferSeconds, name: "demuxer-cache-duration", format: MPV_FORMAT_DOUBLE, on: handle)
        observe(PropertyID.videoWidth, name: "video-params/w", format: MPV_FORMAT_INT64, on: handle)
        observe(PropertyID.videoHeight, name: "video-params/h", format: MPV_FORMAT_INT64, on: handle)
        observe(PropertyID.codecName, name: "video-codec", format: MPV_FORMAT_STRING, on: handle)
        observe(PropertyID.decoderName, name: "hwdec-current", format: MPV_FORMAT_STRING, on: handle)
        observe(PropertyID.fps, name: "container-fps", format: MPV_FORMAT_DOUBLE, on: handle)
        observe(PropertyID.downloadSpeed, name: "cache-speed", format: MPV_FORMAT_DOUBLE, on: handle)
        observe(PropertyID.droppedFrames, name: "decoder-frame-drop-count", format: MPV_FORMAT_INT64, on: handle)
    }

    private func observe(_ id: PropertyID, name: String, format: mpv_format, on handle: OpaquePointer) {
        _ = name.withCString { propertyName in
            mpv_observe_property(handle, id.rawValue, propertyName, format)
        }
    }

    private func pollEvents() {
        guard let handle else { return }
        while let event = mpv_wait_event(handle, 0), event.pointee.event_id != MPV_EVENT_NONE {
            switch event.pointee.event_id {
            case MPV_EVENT_FILE_LOADED:
                didLoadFile = true
                diagnosticsStalls = 0
                diagnosticsErrorEventCount = 0
                diagnosticsErrorCode = nil
                diagnosticsErrorTimestamp = nil
                diagnosticsDroppedFrames = 0
                diagnosticsWasBuffering = false
                hasEnded = false
                errorMessage = nil
                initializePlaybackState()
            case MPV_EVENT_END_FILE:
                handleEndFile(event.pointee.data)
            case MPV_EVENT_PROPERTY_CHANGE:
                handlePropertyChange(event.pointee.data)
            case MPV_EVENT_COMMAND_REPLY:
                if event.pointee.error < 0 {
                    recordDiagnosticsError(code: Int(event.pointee.error))
                    errorMessage = "Playback command failed (\(event.pointee.error))"
                }
            case MPV_EVENT_PLAYBACK_RESTART:
                isSeeking = false
            case MPV_EVENT_SHUTDOWN:
                eventTask?.cancel()
                eventTask = nil
                mpv_set_wakeup_callback(handle, nil, nil)
                mpv_destroy(handle)
                self.handle = nil
                attachedLayer = nil
                isStopped = true
                return
            default:
                break
            }
        }
    }

    private func handlePropertyChange(_ data: UnsafeMutableRawPointer?) {
        guard let data else { return }
        let property = data.assumingMemoryBound(to: mpv_event_property.self).pointee
        guard let name = property.name else { return }
        let propertyName = String(cString: name)
        guard let propertyData = property.data else { return }

        switch propertyName {
        case "time-pos":
            currentTime = propertyData.assumingMemoryBound(to: Double.self).pointee
        case "duration":
            duration = propertyData.assumingMemoryBound(to: Double.self).pointee
        case "speed":
            rate = propertyData.assumingMemoryBound(to: Double.self).pointee
        case "pause":
            if didLoadFile {
                isPlaying = propertyData.assumingMemoryBound(to: Int32.self).pointee == 0
            }
        case "paused-for-cache":
            let buffering = propertyData.assumingMemoryBound(to: Int32.self).pointee != 0
            if didLoadFile, buffering, !diagnosticsWasBuffering {
                diagnosticsStalls += 1
            }
            diagnosticsWasBuffering = buffering
            isBuffering = buffering
        case "demuxer-cache-duration":
            bufferSeconds = propertyData.assumingMemoryBound(to: Double.self).pointee
        case "video-params/w":
            videoWidth = Int(propertyData.assumingMemoryBound(to: Int64.self).pointee)
        case "video-params/h":
            videoHeight = Int(propertyData.assumingMemoryBound(to: Int64.self).pointee)
        case "video-codec":
            if let codec = propertyData.assumingMemoryBound(to: UnsafePointer<CChar>?.self).pointee {
                codecName = String(cString: codec)
            }
        case "hwdec-current":
            if let decoder = propertyData.assumingMemoryBound(to: UnsafePointer<CChar>?.self).pointee {
                decoderName = String(cString: decoder)
            }
        case "container-fps":
            fps = propertyData.assumingMemoryBound(to: Double.self).pointee
        case "cache-speed":
            downloadMbps = max(0, propertyData.assumingMemoryBound(to: Double.self).pointee) * 8 / 1_000_000
        case "decoder-frame-drop-count":
            diagnosticsDroppedFrames = max(0, Int(propertyData.assumingMemoryBound(to: Int64.self).pointee))
        default:
            break
        }
    }

    private func handleEndFile(_ data: UnsafeMutableRawPointer?) {
        guard let data else { return }
        let endFile = data.assumingMemoryBound(to: mpv_event_end_file.self).pointee
        isPlaying = false
        isBuffering = false
        switch endFile.reason {
        case MPV_END_FILE_REASON_EOF:
            hasEnded = true
        case MPV_END_FILE_REASON_ERROR:
            hasEnded = false
            recordDiagnosticsError(code: Int(endFile.error))
            errorMessage = "Unable to play this video"
        case MPV_END_FILE_REASON_STOP, MPV_END_FILE_REASON_QUIT:
            hasEnded = false
        default:
            break
        }
    }

    private func setOption(_ name: String, value: String) -> Bool {
        guard let handle else { return false }
        return check(
            name.withCString { optionName in
                value.withCString { optionValue in
                    mpv_set_option_string(handle, optionName, optionValue)
                }
            }, stage: name)
    }

    private func escapeListValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ",", with: "\\,")
    }

    private func commandAsync(_ command: String, arguments: [String]) -> Int32 {
        guard let handle else { return -1 }
        let pointers = ([command] + arguments).map { strdup($0) }
        defer {
            for pointer in pointers {
                free(pointer)
            }
        }
        var cArguments: [UnsafePointer<CChar>?] = pointers.map { pointer in
            pointer.map { UnsafePointer<CChar>($0) }
        }
        cArguments.append(nil)
        let commandID = nextCommandID
        nextCommandID &+= 1
        return cArguments.withUnsafeMutableBufferPointer { buffer in
            mpv_command_async(handle, commandID, buffer.baseAddress)
        }
    }

    private func check(_ status: Int32, stage: String) -> Bool {
        guard status >= 0 else {
            recordDiagnosticsError(code: Int(status))
            errorMessage = "MPV startup failed at \(stage) (\(status))"
            return false
        }
        return true
    }

    private func recordDiagnosticsError(code: Int?) {
        diagnosticsErrorEventCount += 1
        diagnosticsErrorCode = code
        diagnosticsErrorTimestamp = Date()
    }

    private func shutdown() {
        isStopped = true
        isPlaying = false
        eventTask?.cancel()
        eventTask = nil
        guard let handle else {
            attachedLayer = nil
            return
        }
        mpv_set_wakeup_callback(handle, nil, nil)
        mpv_terminate_destroy(handle)
        self.handle = nil
        attachedLayer = nil
    }
}

#endif
