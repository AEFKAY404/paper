import AVFAudio
import Foundation
import Speech

enum VoiceCaptureError: LocalizedError {
    case onDeviceUnavailable, speechDenied, microphoneDenied, audioUnavailable

    var errorDescription: String? {
        switch self {
        case .onDeviceUnavailable: "On-device speech recognition is unavailable for this language on this Mac."
        case .speechDenied: "Speech Recognition is off for Paper. Enable it in System Settings → Privacy & Security."
        case .microphoneDenied: "Microphone access is off for Paper. Enable it in System Settings → Privacy & Security."
        case .audioUnavailable: "The microphone is unavailable. Check your audio input and try again."
        }
    }
}

/// Created lazily on first invocation. Audio never enters Paper's persistence layer.
@MainActor
final class NativeSpeechCapture {
    private var recognizer: SFSpeechRecognizer?
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var latestTranscript: String?
    private var finalTranscript: String?
    private var finish: ((String?) -> Void)?
    private var timeoutTask: Task<Void, Never>?

    var isCapturing: Bool { engine?.isRunning == true }
    var recognitionMode: String { recognizer?.supportsOnDeviceRecognition == true ? "onDevice" : "unavailable" }

    func authorize() async throws {
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current),
              recognizer.supportsOnDeviceRecognition else {
            throw VoiceCaptureError.onDeviceUnavailable
        }
        let status: SFSpeechRecognizerAuthorizationStatus
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            status = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
        } else { status = SFSpeechRecognizer.authorizationStatus() }
        guard status == .authorized else { throw VoiceCaptureError.speechDenied }
        guard await AVAudioApplication.requestRecordPermission() else { throw VoiceCaptureError.microphoneDenied }
        guard recognizer.isAvailable else { throw VoiceCaptureError.onDeviceUnavailable }
        self.recognizer = recognizer
    }

    func startCapture() throws {
        guard let recognizer, recognizer.supportsOnDeviceRecognition else { throw VoiceCaptureError.onDeviceUnavailable }
        guard engine == nil else { return }
        latestTranscript = nil
        finalTranscript = nil
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw VoiceCaptureError.audioUnavailable }
        do {
            try input.installAudioTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(AVAudioPCMBuffer(copying: buffer))
            }
        } catch { throw VoiceCaptureError.audioUnavailable }
        self.request = request
        self.engine = engine
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    self.latestTranscript = result.bestTranscription.formattedString
                    if result.isFinal { self.finalTranscript = self.latestTranscript }
                }
                if result?.isFinal == true || error != nil { self.finishIfWaiting() }
            }
        }
        do {
            engine.prepare()
            try engine.start()
        } catch {
            cancel()
            throw VoiceCaptureError.audioUnavailable
        }
    }

    func stopCapture() async -> String? {
        guard let request else { return nil }
        stopMicrophone()
        request.endAudio()
        if let finalTranscript { cleanupRecognition(); return finalTranscript }
        return await withCheckedContinuation { continuation in
            finish = { continuation.resume(returning: $0) }
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                self?.finishIfWaiting()
            }
        }
    }

    func cancel() {
        stopMicrophone()
        request?.endAudio()
        finish?(nil)
        cleanupRecognition()
    }

    private func stopMicrophone() {
        guard let engine else { return }
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        self.engine = nil
    }

    private func finishIfWaiting() {
        guard let finish else { return }
        let transcript = finalTranscript ?? latestTranscript
        cleanupRecognition()
        finish(transcript)
    }

    private func cleanupRecognition() {
        timeoutTask?.cancel()
        timeoutTask = nil
        finish = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        request = nil
    }
}
