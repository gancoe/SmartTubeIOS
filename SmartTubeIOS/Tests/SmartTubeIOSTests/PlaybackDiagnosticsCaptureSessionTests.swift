import Foundation
import Testing

@testable import SmartTubeIOS

@Suite("Playback diagnostics capture")
struct PlaybackDiagnosticsCaptureSessionTests {
    @Test @MainActor
    func defaultsRetainWindowAcrossReopen() throws {
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let id = UUID()
        let start = Date(timeIntervalSince1970: 40_000)
        let session = PlaybackDiagnosticsCaptureSession(
            captureID: id, stateURL: url, defaults: defaults, now: start)
        session.note(errorCode: -16_830, at: start.addingTimeInterval(5))
        let reopened = PlaybackDiagnosticsCaptureSession(
            captureID: id, stateURL: url, defaults: try #require(UserDefaults(suiteName: suite)),
            now: start.addingTimeInterval(10))
        #expect(reopened.startedAt == start)
        #expect(reopened.endsAt == start.addingTimeInterval(65))
        #expect(reopened.state == .recovery)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test @MainActor
    func defaultsKeepEndedCaptureEnded() throws {
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let id = UUID()
        let start = Date(timeIntervalSince1970: 50_000)
        let session = PlaybackDiagnosticsCaptureSession(
            captureID: id, stateURL: url, defaults: defaults, now: start)
        session.refresh(at: start.addingTimeInterval(1_800))
        let reopened = PlaybackDiagnosticsCaptureSession(
            captureID: id, stateURL: url, defaults: defaults, now: start.addingTimeInterval(1_810))
        #expect(reopened.state == .ended)
        #expect(reopened.startedAt == start)
        #expect(reopened.endsAt == start.addingTimeInterval(1_800))
    }

    @Test @MainActor
    func malformedDefaultsCannotRenewCapture() throws {
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        for malformed: Any in ["invalid", Data("invalid".utf8)] {
            defaults.set(malformed, forKey: PlaybackDiagnosticsCaptureSession.defaultsKey)
            let session = PlaybackDiagnosticsCaptureSession(captureID: UUID(), stateURL: url, defaults: defaults)
            #expect(session.state == .ended)
            #expect(!session.isCapturing)
            #expect(defaults.object(forKey: PlaybackDiagnosticsCaptureSession.defaultsKey) != nil)
        }
    }

    @Test @MainActor
    func persistsWindowAndStopsAfterTargetErrorRecovery() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let stateURL = root.appendingPathComponent("capture.json")
        let id = UUID()
        let start = Date(timeIntervalSince1970: 10_000)
        let session = PlaybackDiagnosticsCaptureSession(captureID: id, stateURL: stateURL, now: start)
        session.note(errorCode: -12_889, at: start.addingTimeInterval(5))
        #expect(session.state == .recovery)
        #expect(session.endsAt == start.addingTimeInterval(65))

        let reopened = PlaybackDiagnosticsCaptureSession(
            captureID: id, stateURL: stateURL, now: start.addingTimeInterval(10))
        #expect(reopened.startedAt == start)
        #expect(reopened.endsAt == start.addingTimeInterval(65))
        reopened.refresh(at: start.addingTimeInterval(66))
        #expect(reopened.state == .ended)
    }

    @Test @MainActor
    func ignoresUnrelatedErrors() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let now = Date(timeIntervalSince1970: 20_000)
        let session = PlaybackDiagnosticsCaptureSession(captureID: UUID(), stateURL: url, now: now)
        session.note(errorCode: -1, at: now.addingTimeInterval(1))
        #expect(session.state == .active)
        #expect(session.endsAt == now.addingTimeInterval(1_800))
    }

    @Test @MainActor
    func invalidExistingStateFailsClosed() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let stateURL = root.appendingPathComponent("capture.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("invalid".utf8).write(to: stateURL)
        let session = PlaybackDiagnosticsCaptureSession(captureID: UUID(), stateURL: stateURL)
        #expect(!session.isCapturing)
        #expect(session.state == .ended)
    }

    @Test @MainActor
    func writeFailureFailsClosed() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("file".utf8).write(to: root)
        let session = PlaybackDiagnosticsCaptureSession(
            captureID: UUID(), stateURL: root.appendingPathComponent("child/state.json"))
        #expect(!session.isCapturing)
        #expect(session.state == .ended)
    }

    @Test @MainActor
    func excessiveStoredWindowCannotRestartCapture() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let stateURL = root.appendingPathComponent("capture.json")
        let id = UUID()
        let start = Date(timeIntervalSince1970: 30_000)
        _ = PlaybackDiagnosticsCaptureSession(captureID: id, stateURL: stateURL, now: start)
        var values = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as? [String: [String: Any]])
        values[id.uuidString.lowercased()]?["end"] = start.addingTimeInterval(3_600).timeIntervalSinceReferenceDate
        try JSONSerialization.data(withJSONObject: values).write(to: stateURL)
        let reopened = PlaybackDiagnosticsCaptureSession(
            captureID: id, stateURL: stateURL, now: start.addingTimeInterval(10))
        #expect(reopened.state == .ended)
    }
}
