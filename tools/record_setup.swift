import AppKit
import AVFoundation
import Carbon
import ScreenCaptureKit

_ = NSApplication.shared
NSApp.setActivationPolicy(.prohibited)

enum RecordingFailure: Error {
    case arguments, permissionRequired, settingsWindowNotFound, unsupportedOS
}

/// The whole System Settings window, sheets included, so nothing the user clicks is cropped.
func settingsWindow() async throws -> SCWindow {
    guard CGPreflightScreenCaptureAccess() else { throw RecordingFailure.permissionRequired }
    let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
    let windows = content.windows.filter {
        $0.owningApplication?.bundleIdentifier == "com.apple.systempreferences" && $0.frame.height > 200
    }
    guard let window = windows.max(by: { $0.frame.height < $1.frame.height }) else {
        throw RecordingFailure.settingsWindowNotFound
    }
    return window
}

func taviAdded() -> Bool {
    let filter = [kTISPropertyInputSourceID as String: "dev.3xhaust.inputmethod.tavi"] as CFDictionary
    guard let source = (TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource])?.first,
          let value = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled) else { return false }
    return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(value).takeUnretainedValue())
}

@available(macOS 15.0, *)
final class SetupRecorder: NSObject, SCRecordingOutputDelegate {
    private var completion: CheckedContinuation<Void, Error>?

    func record(window: SCWindow, seconds: Double, outputURL: URL) async throws {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = CGFloat(filter.pointPixelScale)
        let configuration = SCStreamConfiguration()
        configuration.width = Int(filter.contentRect.width * scale) / 2 * 2
        configuration.height = Int(filter.contentRect.height * scale) / 2 * 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 24)
        configuration.showsCursor = true
        configuration.capturesAudio = false
        configuration.captureMicrophone = false
        configuration.includeChildWindows = true
        print("SCALE=\(Int(scale))")
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        let recordingConfiguration = SCRecordingOutputConfiguration()
        recordingConfiguration.outputURL = outputURL
        recordingConfiguration.videoCodecType = .h264
        recordingConfiguration.outputFileType = .mp4
        let recording = SCRecordingOutput(configuration: recordingConfiguration, delegate: self)
        try stream.addRecordingOutput(recording)
        try await withCheckedThrowingContinuation { continuation in
            completion = continuation
            Task {
                do {
                    try await stream.startCapture()
                    // Ends a few seconds after Tavi is added, so the recorder needs no timing.
                    var remaining = seconds
                    while remaining > 0, !taviAdded() {
                        try await Task.sleep(nanoseconds: 250_000_000)
                        remaining -= 0.25
                    }
                    try await Task.sleep(nanoseconds: 3_000_000_000)
                    try await stream.stopCapture()
                } catch {
                    finish(.failure(error))
                }
            }
        }
    }

    /// Keyboard Settings only appears once frames are being written, so no click is missed.
    func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        print("RECORDING_STARTED")
        fflush(stdout)
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        print("RECORDING_FINISHED bytes=\(recordingOutput.recordedFileSize)")
        finish(.success(()))
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        finish(.failure(error))
    }

    private func finish(_ result: Result<Void, Error>) {
        guard let continuation = completion else { return }
        completion = nil
        continuation.resume(with: result)
    }
}

guard !taviAdded() else {
    print("Tavi is already in the input sources; remove it in Keyboard Settings first.")
    exit(1)
}
guard CommandLine.arguments.count == 3,
      let seconds = Double(CommandLine.arguments[1]), (1...180).contains(seconds)
else { throw RecordingFailure.arguments }
if #available(macOS 15.0, *) {
    try await SetupRecorder().record(
        window: try await settingsWindow(), seconds: seconds,
        outputURL: URL(fileURLWithPath: CommandLine.arguments[2])
    )
} else {
    throw RecordingFailure.unsupportedOS
}
