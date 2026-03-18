import AVFoundation
import CoreAudio
import FluidAudio
import Observation
import os

/// Diagnostic logger — output visible in Console.app (filter by subsystem "com.opengranola.app").
private let _diagLogger = Logger(subsystem: "com.opengranola.app", category: "diagnostics")

func diagLog(_ msg: String) {
    _diagLogger.debug("\(msg, privacy: .public)")
}

/// Orchestrates dual StreamingTranscriber instances for mic (you) and system audio (them).
@Observable
@MainActor
final class TranscriptionEngine {
    private(set) var isRunning = false
    private(set) var assetStatus: String = "Ready"
    private(set) var lastError: String?
    private(set) var needsModelDownload = false

    /// Whether the user has confirmed they want to download models.
    var downloadConfirmed = false

    private let systemCapture = SystemAudioCapture()
    private let micCapture = MicCapture()
    private let transcriptStore: TranscriptStore

    /// Audio level from mic for the UI meter.
    var audioLevel: Float { micCapture.audioLevel }

    /// Publishes audio level changes only when the delta exceeds 0.02, avoiding re-renders
    /// for noise floor fluctuations. Polled at 50ms intervals on a utility task.
    var audioLevelStream: AsyncStream<Float> {
        AsyncStream { continuation in
            Task.detached(priority: .utility) { [weak self] in
                var lastLevel: Float = 0
                while !Task.isCancelled {
                    guard let self else { break }
                    let current = await self.audioLevel
                    if abs(current - lastLevel) > 0.02 {
                        continuation.yield(current)
                        lastLevel = current
                    }
                    try? await Task.sleep(for: .milliseconds(50))
                }
                continuation.finish()
            }
        }
    }

    private var micTask: Task<Void, Never>?
    private var sysTask: Task<Void, Never>?
    /// Keeps the mic stream alive for the audio level meter when transcription isn't running.
    private var micKeepAliveTask: Task<Void, Never>?

    /// Shared FluidAudio instances
    private var asrProvider: (any ASRProvider)?
    private var vadManager: VadManager?
    private var diarizerManager: DiarizerManager?

    /// Tracks the resolved mic device ID currently in use.
    private var currentMicDeviceID: AudioDeviceID = 0

    /// Tracks whether user selected "System Default" (0) or a specific device.
    private var userSelectedDeviceID: AudioDeviceID = 0

    /// Listens for default input device changes at the OS level.
    private var defaultDeviceListenerBlock: AudioObjectPropertyListenerBlock?

    init(transcriptStore: TranscriptStore) {
        self.transcriptStore = transcriptStore
        self.needsModelDownload = !AsrModels.modelsExist(
            at: AsrModels.defaultCacheDirectory(for: .v3), version: .v3
        )
    }

    func start(locale: Locale, inputDeviceID: AudioDeviceID = 0, captureAppBundleID: String = "", distinguishSpeakers: Bool = false, asrProviderKind: ASRProviderKind = .parakeetV3) async {
        diagLog("[ENGINE-0] start() called, isRunning=\(isRunning)")
        guard !isRunning else { return }
        lastError = nil

        // Block start if models need downloading and user hasn't confirmed
        if needsModelDownload && !downloadConfirmed {
            return
        }

        guard await ensureMicrophonePermission() else { return }

        isRunning = true

        // 1. Load ASR provider
        diagLog("[ENGINE-1] loading ASR provider (\(String(describing: asrProviderKind)))...")
        do {
            switch asrProviderKind {
            case .parakeetV3:
                assetStatus = needsModelDownload ? "Downloading ASR model (~600MB)..." : "Loading ASR model..."
                let models = try await AsrModels.downloadAndLoad(version: .v3)
                assetStatus = "Initializing ASR..."
                let asr = AsrManager(config: .default)
                try await asr.initialize(models: models)
                self.asrProvider = ParakeetASRProvider(asrManager: asr)
                needsModelDownload = false
            case .whisperLargeV3Turbo:
                assetStatus = "WhisperKit will download on first use (~600MB)"
                self.asrProvider = WhisperKitASRProvider()
                needsModelDownload = false
            }

            assetStatus = "Loading VAD model..."
            diagLog("[ENGINE-1b] loading VAD model...")
            let vad = try await VadManager()
            self.vadManager = vad

            if distinguishSpeakers {
                assetStatus = "Loading diarization model (~32MB)..."
                diagLog("[ENGINE-1c] loading DiarizerModels...")
                do {
                    let diarizerModels = try await DiarizerModels.download()
                    let dm = DiarizerManager()
                    dm.initialize(models: diarizerModels)
                    self.diarizerManager = dm
                    diagLog("[ENGINE-1c] DiarizerModels loaded OK")
                } catch {
                    diagLog("[ENGINE-1c-WARN] DiarizerModels load failed: \(error.localizedDescription) — continuing without diarization")
                    self.diarizerManager = nil
                }
            } else {
                self.diarizerManager = nil
            }

            downloadConfirmed = false
            assetStatus = "Models ready"
            diagLog("[ENGINE-2] models loaded")
        } catch {
            let msg = "Failed to load models: \(error.localizedDescription)"
            diagLog("[ENGINE-2-FAIL] \(msg)")
            lastError = msg
            assetStatus = "Ready"
            isRunning = false
            return
        }

        guard let asrProvider, let vadManager else { return }

        // 2. Start mic capture
        userSelectedDeviceID = inputDeviceID
        let targetMicID = inputDeviceID > 0 ? inputDeviceID : MicCapture.defaultInputDeviceID()
        currentMicDeviceID = targetMicID ?? 0
        diagLog("[ENGINE-3] starting mic capture, targetMicID=\(String(describing: targetMicID))")
        let micStream = micCapture.bufferStream(deviceID: targetMicID)

        // 3. Start system audio capture
        diagLog("[ENGINE-4] starting system audio capture...")
        let sysStreams: SystemAudioCapture.CaptureStreams?
        do {
            sysStreams = try await systemCapture.bufferStream(appBundleID: captureAppBundleID.isEmpty ? nil : captureAppBundleID)
            diagLog("[ENGINE-5] system audio capture started OK")
        } catch SystemAudioCapture.CaptureError.appNotFound(let id) {
            let msg = "App '\(id)' not running — capturing all system audio instead."
            diagLog("[ENGINE-5-WARN] \(msg)")
            lastError = msg
            sysStreams = try? await systemCapture.bufferStream(appBundleID: nil)
        } catch {
            let msg = "Failed to start system audio: \(error.localizedDescription)"
            diagLog("[ENGINE-5-FAIL] \(msg)")
            lastError = msg
            sysStreams = nil
        }

        // 4. Start mic transcription
        let store = transcriptStore
        let micTranscriber = StreamingTranscriber(
            asrProvider: asrProvider,
            vadManager: vadManager,
            speaker: .you,
            onPartial: { text in
                Task { @MainActor in store.volatileYouText = text }
            },
            onFinal: { text, id in
                Task { @MainActor in
                    store.volatileYouText = ""
                    store.append(Utterance(id: id, text: text, speaker: .you, timestamp: .now))
                }
            }
        )
        micTask = Task.detached {
            await micTranscriber.run(stream: micStream)
        }

        // 5. Start system audio transcription
        if let sysStream = sysStreams?.systemAudio {
            let sysTranscriber = StreamingTranscriber(
                asrProvider: asrProvider,
                vadManager: vadManager,
                speaker: .them,
                diarizerManager: self.diarizerManager,
                onPartial: { text in
                    Task { @MainActor in store.volatileThemText = text }
                },
                onFinal: { text, id in
                    Task { @MainActor in
                        store.volatileThemText = ""
                        store.append(Utterance(id: id, text: text, speaker: .them, timestamp: .now))
                    }
                }
            )
            sysTranscriber.onSpeakerIdentified = { id, speaker in
                Task { @MainActor in store.relabelUtterance(id: id, speaker: speaker) }
            }
            sysTask = Task.detached {
                await sysTranscriber.run(stream: sysStream)
            }
        }

        assetStatus = "Transcribing (\(asrProvider.modelDisplayName))"
        diagLog("[ENGINE-6] all transcription tasks started")

        // Install CoreAudio listener for default input device changes
        installDefaultDeviceListener()
    }

    /// Restart only the mic capture with a new device, keeping system audio and models intact.
    /// Pass the raw setting value (0 = system default, or a specific AudioDeviceID).
    func restartMic(inputDeviceID: AudioDeviceID) {
        guard isRunning, let asrProvider, let vadManager else { return }

        // Only update user selection when explicitly changed (not from OS listener)
        if inputDeviceID != 0 || userSelectedDeviceID != 0 {
            userSelectedDeviceID = inputDeviceID
        }
        let targetMicID = inputDeviceID > 0 ? inputDeviceID : MicCapture.defaultInputDeviceID() ?? 0
        guard targetMicID != currentMicDeviceID else {
            diagLog("[ENGINE-MIC-SWAP] same device \(targetMicID), skipping")
            return
        }

        diagLog("[ENGINE-MIC-SWAP] switching mic from \(currentMicDeviceID) to \(targetMicID)")

        // Tear down old mic
        micTask?.cancel()
        micTask = nil
        micCapture.stop()

        currentMicDeviceID = targetMicID

        // Start new mic stream
        let micStream = micCapture.bufferStream(deviceID: targetMicID)
        let store = transcriptStore
        let micTranscriber = StreamingTranscriber(
            asrProvider: asrProvider,
            vadManager: vadManager,
            speaker: .you,
            onPartial: { text in
                Task { @MainActor in store.volatileYouText = text }
            },
            onFinal: { text, id in
                Task { @MainActor in
                    store.volatileYouText = ""
                    store.append(Utterance(id: id, text: text, speaker: .you, timestamp: .now))
                }
            }
        )
        micTask = Task.detached {
            await micTranscriber.run(stream: micStream)
        }

        diagLog("[ENGINE-MIC-SWAP] mic restarted on device \(targetMicID)")
    }

    // MARK: - Default Device Listener

    private func installDefaultDeviceListener() {
        guard defaultDeviceListenerBlock == nil else { return }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.isRunning, self.userSelectedDeviceID == 0 else { return }
                // User has "System Default" selected — follow the OS default
                self.restartMic(inputDeviceID: 0)
            }
        }
        defaultDeviceListenerBlock = block

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )
    }

    private func removeDefaultDeviceListener() {
        guard let block = defaultDeviceListenerBlock else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )
        defaultDeviceListenerBlock = nil
    }

    private func ensureMicrophonePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if !granted {
                lastError = "Microphone access denied. Enable it in System Settings > Privacy & Security > Microphone."
                assetStatus = "Ready"
            }
            return granted
        case .denied, .restricted:
            lastError = "Microphone access is disabled. Enable it in System Settings > Privacy & Security > Microphone."
            assetStatus = "Ready"
            return false
        @unknown default:
            lastError = "Unable to verify microphone permission."
            assetStatus = "Ready"
            return false
        }
    }

    /// Gracefully drain buffered audio before stopping.
    /// Finishes async streams so transcribers flush remaining speech samples,
    /// then awaits task completion before tearing down audio hardware.
    func finalize() async {
        removeDefaultDeviceListener()
        micKeepAliveTask?.cancel()

        // Finish the async streams — causes StreamingTranscriber.run()
        // to exit its for-await loop and hit the final speechSamples flush
        micCapture.finishStream()
        systemCapture.finishStream()

        // Wait for transcriber tasks to complete (includes final flush)
        await micTask?.value
        await sysTask?.value

        // Now safe to tear down audio hardware
        micCapture.stop()
        await systemCapture.stop()

        micTask = nil
        sysTask = nil
        micKeepAliveTask = nil
        currentMicDeviceID = 0
        isRunning = false
        assetStatus = "Ready"
    }

    func stop() async {
        removeDefaultDeviceListener()
        micTask?.cancel()
        sysTask?.cancel()
        micKeepAliveTask?.cancel()
        micTask = nil
        sysTask = nil
        micKeepAliveTask = nil
        await systemCapture.stop()
        micCapture.stop()
        currentMicDeviceID = 0
        isRunning = false
        assetStatus = "Ready"
    }
}
