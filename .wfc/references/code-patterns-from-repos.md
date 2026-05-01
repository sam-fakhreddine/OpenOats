# Code Patterns Reference: Transcription Apps

> Extracted from OwlWhisper and Petal - macOS transcription applications
> Created for OpenOats adaptation

---

## 1. CODE PATTERNS

### 1.1 Service Layer Patterns (ASR/Transcription Abstraction)

#### Pattern A: Simple Service with Callbacks (OwlWhisper-style)

```swift
import Foundation

/// Service that abstracts transcription backend
class TranscriptionService {
    
    struct TranscriptionResult {
        let text: String
        let hasSpeech: Bool
        let durationMs: Int
    }
    
    // MARK: - State Callbacks
    var onReady: ((String) -> Void)?
    var onError: ((String) -> Void)?
    
    // Thread-safe state (main thread only)
    private(set) var isReady = false
    
    // MARK: - Internal Queue
    private let queue = DispatchQueue(label: "com.app.transcription")
    private var generation = 0  // For detecting stale operations
    
    // MARK: - Lifecycle
    
    /// Start service - verify models but don't load yet
    func start() {
        queue.async { [weak self] in
            self?.verifyModels()
        }
    }
    
    /// Preload models (call when recording starts)
    func preload() {
        queue.async { [weak self] in
            self?.ensureLoaded()
        }
    }
    
    func stop() {
        DispatchQueue.main.async { [weak self] in self?.isReady = false }
        queue.async { [weak self] in
            guard let self else { return }
            self.generation += 1
            self.cleanupModels()
        }
    }
    
    // MARK: - Transcription
    
    func transcribe(audioData: Data, sampleRate: Int, completion: @escaping (Result<TranscriptionResult, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self else {
                completion(.failure(NSError(domain: "TranscriptionService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Service released"])))
                return
            }
            
            let currentGen = self.generation
            self.ensureLoaded()
            
            // ... transcription logic ...
            
            // Check if service was stopped during processing
            guard self.generation == currentGen else {
                completion(.failure(NSError(domain: "TranscriptionService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Service stopped"])))
                return
            }
            
            // Return on main thread
            DispatchQueue.main.async {
                completion(.success(TranscriptionResult(text: "", hasSpeech: true, durationMs: 0)))
            }
        }
    }
    
    private func verifyModels() {
        // Check files exist
        let ready = checkModelsExist()
        DispatchQueue.main.async { [weak self] in
            self?.isReady = ready
            if ready { self?.onReady?("Model Name") }
            else { self?.onError?("Models not found") }
        }
    }
    
    private func ensureLoaded() {
        // Lazy load models into memory
    }
    
    private func cleanupModels() {
        // Release memory
    }
    
    private func checkModelsExist() -> Bool {
        return true
    }
}
```

#### Pattern B: Dependency Injection Client (Petal-style with Dependencies framework)

```swift
import Dependencies
import DependenciesMacros

/// DependencyClient pattern for testable services
@DependencyClient
public struct TranscriptionClient: Sendable {
    public var prepareModelIfNeeded: @Sendable (ModelOption) async throws -> Void
    public var transcribe: @Sendable (URL, ModelOption, TranscriptionMode, String?) async throws -> String
    public var unloadModel: @Sendable () async -> Void
    public var audioDurationSeconds: @Sendable (URL) -> Double
}

// MARK: - Live Implementation

extension TranscriptionClient: DependencyKey {
    public static var liveValue: Self {
        Self(
            prepareModelIfNeeded: { option in
                // Prepare model logic
            },
            transcribe: { audioURL, option, mode, prompt in
                // Transcription pipeline
                let transcript = try await performTranscription(audioURL, option, mode)
                return transcript
            },
            unloadModel: {
                @Dependency(\.modelClient) var modelClient
                await modelClient.unload()
            },
            audioDurationSeconds: { url in
                // Calculate duration
                return 0.0
            }
        )
    }
}

// MARK: - Test Implementation

extension TranscriptionClient: TestDependencyKey {
    public static var testValue: Self {
        Self(
            prepareModelIfNeeded: { _ in },
            transcribe: { _, _, _, _ in "Test transcription" },
            unloadModel: {},
            audioDurationSeconds: { _ in 1.0 }
        )
    }
}

// MARK: - Dependency Registration

public extension DependencyValues {
    var transcriptionClient: TranscriptionClient {
        get { self[TranscriptionClient.self] }
        set { self[TranscriptionClient.self] = newValue }
    }
}
```

#### Pattern C: Runtime Container Pattern (Petal-style)

```swift
/// Thread-safe singleton container for live service runtime
private final class LiveTranscriptionRuntime: @unchecked Sendable {
    private let stateQueue = DispatchQueue(label: "com.app.transcription.runtime")
    private var model: MLModel?
    
    var isReady: Bool {
        stateQueue.sync { model != nil }
    }
    
    func prepare() async throws {
        try await withCheckedThrowingContinuation { continuation in
            stateQueue.async { [self] in
                do {
                    try prepareLocked()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func prepareLocked() throws {
        guard model == nil else { return }
        // Load model
    }
    
    func transcribe(_ audioURL: URL) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            stateQueue.async { [self] in
                do {
                    let result = try transcribeLocked(audioURL)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func transcribeLocked(_ audioURL: URL) throws -> String {
        // Perform transcription
        return ""
    }
}

private enum LiveTranscriptionRuntimeContainer {
    static let shared = LiveTranscriptionRuntime()
}
```

---

### 1.2 Audio Recording/Capture Patterns

#### Pattern A: AVAudioEngine with Format Conversion (OwlWhisper-style)

```swift
import AVFoundation

/// Records 16kHz mono float32 PCM using AVAudioEngine
class AudioRecorder {
    
    private let engine = AVAudioEngine()
    private var buffer = Data()
    private let lock = NSLock()
    private let targetSampleRate: Double = 16000
    private(set) var lastError: Error?
    
    /// Start recording - throws on failure
    func startRecording() throws {
        lock.lock()
        buffer = Data()
        lastError = nil
        lock.unlock()
        
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        // Target format: 16kHz mono float32
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioRecorderError.formatCreationFailed
        }
        
        // Create converter if needed
        let converter: AVAudioConverter?
        if inputFormat.sampleRate != targetSampleRate || inputFormat.channelCount != 1 {
            guard let conv = AVAudioConverter(from: inputFormat, to: targetFormat) else {
                throw AudioRecorderError.converterCreationFailed
            }
            converter = conv
        } else {
            converter = nil
        }
        
        // Install tap
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] pcmBuffer, _ in
            guard let self else { return }
            
            let outputBuffer: AVAudioPCMBuffer
            if let converter {
                // Convert format
                let ratio = self.targetSampleRate / inputFormat.sampleRate
                let outputFrameCount = AVAudioFrameCount(Double(pcmBuffer.frameLength) * ratio)
                guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount) else {
                    self.setError(AudioRecorderError.formatCreationFailed)
                    return
                }
                
                var error: NSError?
                var hasProvidedData = false
                converter.convert(to: converted, error: &error) { _, outStatus in
                    if hasProvidedData {
                        outStatus.pointee = .noDataNow
                        return nil
                    }
                    hasProvidedData = true
                    outStatus.pointee = .haveData
                    return pcmBuffer
                }
                
                if let error {
                    self.setError(error)
                    return
                }
                outputBuffer = converted
            } else {
                outputBuffer = pcmBuffer
            }
            
            // Extract float32 data
            guard let channelData = outputBuffer.floatChannelData else {
                self.setError(AudioRecorderError.formatCreationFailed)
                return
            }
            let frameCount = Int(outputBuffer.frameLength)
            let data = Data(bytes: channelData[0], count: frameCount * MemoryLayout<Float>.size)
            
            self.lock.lock()
            self.buffer.append(data)
            self.lock.unlock()
        }
        
        try engine.start()
    }
    
    /// Stop recording and return data
    func stopRecording() -> (data: Data, error: Error?) {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        
        lock.lock()
        let result = buffer
        let error = lastError
        buffer = Data()
        lastError = nil
        lock.unlock()
        
        return (result, error)
    }
    
    private func setError(_ error: Error) {
        lock.lock()
        lastError = error
        lock.unlock()
    }
    
    enum AudioRecorderError: LocalizedError {
        case formatCreationFailed
        case converterCreationFailed
        
        var errorDescription: String? {
            switch self {
            case .formatCreationFailed:
                return "Failed to create audio format (16kHz mono float32)"
            case .converterCreationFailed:
                return "Failed to create audio converter"
            }
        }
    }
}
```

#### Pattern B: AVAudioRecorder with Pre-warming (Petal-style)

```swift
import AVFoundation

/// Uses AVAudioRecorder with standby recorder pattern for instant start
private final class LiveAudioCaptureRuntime: @unchecked Sendable {
    private let stateQueue = DispatchQueue(label: "com.app.audio.runtime")
    private var recorder: AVAudioRecorder?
    private var standbyRecorder: AVAudioRecorder?
    private var standbyURL: URL?
    private var recordingURL: URL?
    
    private static let recordingSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatLinearPCM),
        AVSampleRateKey: 44_100,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false
    ]
    
    var isRecording: Bool {
        stateQueue.sync { recorder?.isRecording ?? false }
    }
    
    /// Pre-create recorder for instant start
    func warmup() {
        stateQueue.async { [self] in
            warmupStandbyLocked()
        }
    }
    
    private func warmupStandbyLocked() {
        guard standbyRecorder == nil, recorder == nil else { return }
        
        let url = FileManager.default.temporaryDirectory
            .appending(path: "recording-\(UUID().uuidString).wav")
        
        do {
            let rec = try AVAudioRecorder(url: url, settings: Self.recordingSettings)
            rec.isMeteringEnabled = true
            guard rec.prepareToRecord() else { return }
            standbyRecorder = rec
            standbyURL = url
        } catch {}
    }
    
    func startRecording() async throws {
        try await withCheckedThrowingContinuation { continuation in
            stateQueue.async { [self] in
                do {
                    try startRecordingLocked()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func startRecordingLocked() throws {
        guard recorder == nil else { return }
        
        // Use pre-warmed standby if available
        if let standby = standbyRecorder, let url = standbyURL {
            standbyRecorder = nil
            standbyURL = nil
            guard standby.record() else {
                throw AudioRecorderError.failedToStart
            }
            recorder = standby
            recordingURL = url
            return
        }
        
        // Fallback: create fresh
        let url = FileManager.default.temporaryDirectory
            .appending(path: "recording-\(UUID().uuidString).wav")
        
        let rec = try AVAudioRecorder(url: url, settings: Self.recordingSettings)
        rec.isMeteringEnabled = true
        guard rec.prepareToRecord(), rec.record() else {
            throw AudioRecorderError.failedToStart
        }
        
        recorder = rec
        recordingURL = url
    }
    
    func stopRecording() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            stateQueue.async { [self] in
                do {
                    let url = try stopRecordingLocked()
                    continuation.resume(returning: url)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func stopRecordingLocked() throws -> URL {
        guard let recorder, let url = recordingURL else {
            throw AudioRecorderError.notRecording
        }
        
        recorder.stop()
        self.recorder = nil
        recordingURL = nil
        
        // Pre-warm next standby
        stateQueue.asyncAfter(deadline: .now() + 0.1) { [self] in
            warmupStandbyLocked()
        }
        
        return url
    }
    
    enum AudioRecorderError: Error {
        case notRecording
        case failedToStart
    }
}
```

#### Pattern C: Audio Level Monitoring

```swift
/// Thread-safe rolling average for audio levels
private final class LevelSmoother: @unchecked Sendable {
    private var levels: [Double] = []
    private let windowSize: Int
    private let lock = NSLock()
    
    init(windowSize: Int = 8) {
        self.windowSize = windowSize
    }
    
    func smooth(_ level: Double) -> Double {
        lock.lock()
        defer { lock.unlock() }
        levels.append(level)
        if levels.count > windowSize {
            levels.removeFirst(levels.count - windowSize)
        }
        return levels.reduce(0, +) / Double(levels.count)
    }
}

// Usage in audio recorder
private func startLevelPolling() {
    let timer = DispatchSource.makeTimerSource(queue: stateQueue)
    timer.schedule(deadline: .now(), repeating: .milliseconds(60))
    timer.setEventHandler { [weak self] in
        guard let self, let recorder = self.recorder, recorder.isRecording else { return }
        recorder.updateMeters()
        let power = recorder.averagePower(forChannel: 0)
        let normalized = Self.normalizePower(power)
        let smoothed = self.levelSmoother.smooth(normalized)
        
        DispatchQueue.main.async { [weak self] in
            self?.levelHandler?(smoothed)
        }
    }
    levelTimer = timer
    timer.resume()
}

private static func normalizePower(_ power: Float) -> Double {
    if power <= -80 { return 0 }
    let normalized = (Double(power) + 50.0) / 50.0
    return max(0, min(1, normalized))
}
```

---

### 1.3 Hotkey/Global Shortcut Implementation

#### Pattern A: CGEventTap with Modifier Keys (OwlWhisper-style)

```swift
import Cocoa

/// Hotkey configuration stored in UserDefaults
struct HotkeyConfig {
    var keyCode: UInt16
    var modifiers: NSEvent.ModifierFlags
    var displayName: String
    
    var isModifierOnly: Bool { modifiers.isEmpty }
    
    static var current: HotkeyConfig {
        get {
            let keyCode = UserDefaults.standard.object(forKey: "hotkeyKeyCode") as? Int ?? 63
            let mods = UserDefaults.standard.integer(forKey: "hotkeyModifiers")
            let modFlags = NSEvent.ModifierFlags(rawValue: UInt(mods))
            let name = modFlags.isEmpty ? keyCodeName(UInt16(keyCode)) : displayName(keyCode: UInt16(keyCode), modifiers: modFlags)
            return HotkeyConfig(keyCode: UInt16(keyCode), modifiers: modFlags, displayName: name)
        }
        set {
            UserDefaults.standard.set(Int(newValue.keyCode), forKey: "hotkeyKeyCode")
            UserDefaults.standard.set(Int(newValue.modifiers.rawValue), forKey: "hotkeyModifiers")
        }
    }
    
    static func displayName(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option)  { parts.append("⌥") }
        if modifiers.contains(.shift)   { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        parts.append(keyCodeName(keyCode))
        return parts.joined()
    }
    
    static func keyCodeName(_ keyCode: UInt16) -> String {
        let map: [UInt16: String] = [
            63: "Fn", 61: "⌥", 54: "⌘", 59: "⌃",
            0: "A", 1: "S", 2: "D", 3: "F",
            // ... more mappings
        ]
        return map[keyCode] ?? "Key\(keyCode)"
    }
}

/// Global hotkey manager
class HotkeyManager {
    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retryTimer: Timer?
    private var retainedSelf: Unmanaged<HotkeyManager>?
    private var keyPressed = false
    private var config = HotkeyConfig.current
    
    func start() {
        stop()
        config = HotkeyConfig.current
        
        if config.isModifierOnly {
            // Use flagsChanged for modifier-only keys
            setupModifierMonitoring()
        } else {
            // Use CGEventTap for combo keys
            setupEventTap()
        }
    }
    
    private func setupEventTap() {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let mgr = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
            
            // Handle tap disable
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = mgr.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            guard keyCode == mgr.config.keyCode else { return Unmanaged.passUnretained(event) }
            
            // KeyUp - don't check modifiers (user may have released them)
            if type == .keyUp && mgr.keyPressed {
                mgr.updateState(false)
                return nil  // Consume event
            }
            
            // Check modifiers match
            let actual = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
                .intersection([.shift, .control, .option, .command])
            let required = mgr.config.modifiers.intersection([.shift, .control, .option, .command])
            guard actual == required else { return Unmanaged.passUnretained(event) }
            
            if type == .keyDown {
                mgr.updateState(true)
                return nil  // Consume event
            }
            return Unmanaged.passUnretained(event)
        }
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: {
                let retained = Unmanaged.passRetained(self)
                self.retainedSelf = retained
                return retained.toOpaque()
            }()
        ) else {
            // Fallback to NSEvent monitoring
            setupFallbackMonitoring()
            return
        }
        
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        
        // Re-enable timer
        retryTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            guard let self, let tap = self.eventTap else { return }
            if !CGEvent.tapIsEnabled(tap: tap) {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
    }
    
    private func updateState(_ isDown: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if isDown && !self.keyPressed {
                self.keyPressed = true
                self.onKeyDown?()
            } else if !isDown && self.keyPressed {
                self.keyPressed = false
                self.onKeyUp?()
            }
        }
    }
    
    func stop() {
        retryTimer?.invalidate()
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            retainedSelf?.release()
            retainedSelf = nil
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        keyPressed = false
    }
    
    deinit { stop() }
}
```

#### Pattern B: KeyboardShortcuts Framework Integration (Petal-style)

```swift
import KeyboardShortcuts

// Define shortcuts
extension KeyboardShortcuts.Name {
    static let pushToTalk = Self("pushToTalk", default: .init(.k, modifiers: .option))
}

/// Register handlers
func registerShortcutHandlers() {
    KeyboardShortcuts.removeAllHandlers()
    
    KeyboardShortcuts.onKeyDown(for: .pushToTalk) { [weak self] in
        Task { await self?.pushToTalkKeyDown() }
    }
    
    KeyboardShortcuts.onKeyUp(for: .pushToTalk) { [weak self] in
        Task { await self?.pushToTalkKeyUp() }
    }
}

// In Settings UI
import KeyboardShortcuts
import SwiftUI

struct GeneralPane: View {
    var body: some View {
        Form {
            LabeledContent("Push to Talk") {
                KeyboardShortcuts.Recorder(for: .pushToTalk)
            }
        }
    }
}
```

---

### 1.4 Model Download/Management Patterns

#### Pattern A: Chunked Parallel Download with Resume (OwlWhisper-style)

```swift
import Foundation

class ModelDownloader {
    struct Progress {
        let bytesDownloaded: Int64
        let totalBytes: Int64
        var fraction: Double { totalBytes > 0 ? Double(bytesDownloaded) / Double(totalBytes) : 0 }
    }
    
    private let chunkSize: Int64 = 5 * 1024 * 1024  // 5MB chunks
    private let maxConcurrency = 6
    private let cancelLock = NSLock()
    private var _cancelled = false
    private var cancelled: Bool {
        get { cancelLock.lock(); defer { cancelLock.unlock() }; return _cancelled }
        set { cancelLock.lock(); defer { cancelLock.unlock() }; _cancelled = newValue }
    }
    
    func download(from url: URL, to destination: URL, progress: @escaping (Progress) -> Void) async throws {
        cancelled = false
        
        // 1. Get file size with HEAD/Range request
        let (finalURL, totalBytes) = try await resolveDownload(url)
        
        if totalBytes <= 0 {
            // Fallback to simple download
            try await simpleDownload(from: finalURL, to: destination, progress: progress)
            return
        }
        
        // 2. Calculate chunks
        let chunks = buildChunks(totalBytes: totalBytes)
        let metaPath = destination.path + ".chunks"
        
        // 3. Load completed chunks (resume support)
        var completedChunks = loadCompletedChunks(from: metaPath)
        
        // 4. Pre-allocate file
        if !FileManager.default.fileExists(atPath: destination.path) {
            FileManager.default.createFile(atPath: destination.path, contents: nil)
            let handle = try FileHandle(forWritingTo: destination)
            try handle.truncate(atOffset: UInt64(totalBytes))
            try handle.close()
        }
        
        let initialBytes = completedChunks.reduce(0) { sum, idx in sum + chunks[idx].length }
        let downloaded = LockedCounter(initialValue: initialBytes)
        
        DispatchQueue.main.async {
            progress(Progress(bytesDownloaded: initialBytes, totalBytes: totalBytes))
        }
        
        // 5. Serial file writer actor
        let fileWriter = try FileWriter(url: destination)
        
        // 6. Parallel download with throttling
        let pendingIndices = chunks.indices.filter { !completedChunks.contains($0) }
        
        try await withThrowingTaskGroup(of: Int.self) { group in
            var iterator = pendingIndices.makeIterator()
            
            // Fill initial concurrency slots
            for _ in 0..<maxConcurrency {
                guard let idx = iterator.next() else { break }
                let chunk = chunks[idx]
                group.addTask {
                    guard !self.cancelled else { throw DownloadError.cancelled }
                    let data = try await self.downloadChunk(from: finalURL, chunk: chunk)
                    try await fileWriter.write(data: data, at: UInt64(chunk.offset))
                    return idx
                }
            }
            
            // As each completes, add next
            for try await completedIdx in group {
                guard !cancelled else { throw DownloadError.cancelled }
                
                let bytesAdded = chunks[completedIdx].length
                let newTotal = downloaded.add(bytesAdded)
                completedChunks.insert(completedIdx)
                saveCompletedChunks(completedChunks, to: metaPath)
                
                DispatchQueue.main.async {
                    progress(Progress(bytesDownloaded: newTotal, totalBytes: totalBytes))
                }
                
                if let idx = iterator.next() {
                    let chunk = chunks[idx]
                    group.addTask {
                        guard !self.cancelled else { throw DownloadError.cancelled }
                        let data = try await self.downloadChunk(from: finalURL, chunk: chunk)
                        try await fileWriter.write(data: data, at: UInt64(chunk.offset))
                        return idx
                    }
                }
            }
        }
        
        try await fileWriter.close()
        
        // Cleanup metadata
        try? FileManager.default.removeItem(atPath: metaPath)
    }
    
    private func resolveDownload(_ url: URL) async throws -> (URL, Int64) {
        var request = URLRequest(url: url)
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DownloadError.serverError(statusCode: 0)
        }
        
        let finalURL = http.url ?? url
        
        // Parse Content-Range header
        var totalBytes: Int64 = -1
        if let contentRange = http.value(forHTTPHeaderField: "Content-Range"),
           let slashIdx = contentRange.lastIndex(of: "/"),
           let size = Int64(contentRange[contentRange.index(after: slashIdx)...]) {
            totalBytes = size
        }
        
        return (finalURL, totalBytes)
    }
    
    private func downloadChunk(from url: URL, chunk: Chunk) async throws -> Data {
        let endByte = chunk.offset + chunk.length - 1
        var request = URLRequest(url: url)
        request.setValue("bytes=\(chunk.offset)-\(endByte)", forHTTPHeaderField: "Range")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 206 else {
            throw DownloadError.serverError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        
        guard Int64(data.count) == chunk.length else {
            throw DownloadError.dataSizeMismatch(expected: chunk.length, got: Int64(data.count))
        }
        
        return data
    }
    
    private struct Chunk {
        let index: Int
        let offset: Int64
        let length: Int64
    }
    
    private func buildChunks(totalBytes: Int64) -> [Chunk] {
        var chunks: [Chunk] = []
        var offset: Int64 = 0
        var idx = 0
        while offset < totalBytes {
            let length = min(chunkSize, totalBytes - offset)
            chunks.append(Chunk(index: idx, offset: offset, length: length))
            offset += length
            idx += 1
        }
        return chunks
    }
    
    private func loadCompletedChunks(from path: String) -> Set<Int> {
        guard let data = FileManager.default.contents(atPath: path),
              let text = String(data: data, encoding: .utf8) else { return [] }
        let indices = text.split(separator: ",").compactMap { Int($0) }
        return Set(indices)
    }
    
    private func saveCompletedChunks(_ chunks: Set<Int>, to path: String) {
        let text = chunks.sorted().map(String.init).joined(separator: ",")
        try? text.write(toFile: path, atomically: true, encoding: .utf8)
    }
    
    func cancel() {
        cancelled = true
    }
    
    enum DownloadError: LocalizedError {
        case serverError(statusCode: Int)
        case cancelled
        case dataSizeMismatch(expected: Int64, got: Int64)
        
        var errorDescription: String? {
            switch self {
            case .serverError(let code): return "Server error (HTTP \(code))"
            case .cancelled: return "Download cancelled"
            case .dataSizeMismatch(let expected, let got): return "Size mismatch: expected \(expected), got \(got)"
            }
        }
    }
}

// Actor for serialized file writes
private actor FileWriter {
    private let handle: FileHandle
    
    init(url: URL) throws {
        handle = try FileHandle(forWritingTo: url)
    }
    
    func write(data: Data, at offset: UInt64) throws {
        try handle.seek(toOffset: offset)
        handle.write(data)
    }
    
    func close() throws {
        try handle.close()
    }
}

// Thread-safe counter
private final class LockedCounter: @unchecked Sendable {
    private var value: Int64
    private let lock = NSLock()
    
    init(initialValue: Int64 = 0) {
        self.value = initialValue
    }
    
    func add(_ delta: Int64) -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        value += delta
        return value
    }
}
```

---

### 1.5 Settings/Preferences Management

#### Pattern A: UserDefaults with Type Safety (OwlWhisper-style)

```swift
// Simple UserDefaults wrapper
struct HotkeyConfig {
    var keyCode: UInt16
    var modifiers: NSEvent.ModifierFlags
    var displayName: String
    
    static var current: HotkeyConfig {
        get {
            let keyCode = UserDefaults.standard.object(forKey: "hotkeyKeyCode") as? Int ?? 63
            let mods = UserDefaults.standard.integer(forKey: "hotkeyModifiers")
            let modFlags = NSEvent.ModifierFlags(rawValue: UInt(mods))
            // ... compute display name
            return HotkeyConfig(keyCode: UInt16(keyCode), modifiers: modFlags, displayName: name)
        }
        set {
            UserDefaults.standard.set(Int(newValue.keyCode), forKey: "hotkeyKeyCode")
            UserDefaults.standard.set(Int(newValue.modifiers.rawValue), forKey: "hotkeyModifiers")
        }
    }
}
```

#### Pattern B: @Shared Property Wrapper (Petal-style with Sharing framework)

```swift
import Sharing

/// Type-safe shared state using @Shared property wrapper
extension SharedReaderKey where Self == InMemoryKey<Bool>.Default {
    static var hasCompletedSetup: Self {
        Self[.inMemory("hasCompletedSetup"), default: false]
    }
}

extension SharedKey where Self == AppStorageKey<TranscriptionMode>.Default {
    static var transcriptionMode: Self {
        Self[.appStorage("transcriptionMode"), default: .verbatim]
    }
}

extension SharedKey where Self == AppStorageKey<String>.Default {
    static var smartPrompt: Self {
        Self[.appStorage("smartPrompt"), default: "Clean up filler words..."]
    }
}

// Usage in Observable model
@Observable
@MainActor
final class AppModel {
    @ObservationIgnored @Shared(.hasCompletedSetup) var hasCompletedSetup = false
    @ObservationIgnored @Shared(.transcriptionMode) var transcriptionMode: TranscriptionMode = .verbatim
    @ObservationIgnored @Shared(.smartPrompt) var smartPrompt = "Clean up filler words..."
    
    func updateMode(_ mode: TranscriptionMode) {
        $transcriptionMode.withLock { $0 = mode }
    }
}
```

---

### 1.6 Menu Bar Implementation

#### Pattern A: NSStatusBar with Custom Window (OwlWhisper-style)

```swift
import Cocoa

class MenubarController: NSObject {
    enum State {
        case ready
        case recording
        case transcribing
        case error
    }
    
    private let statusItem: NSStatusItem
    private var settingsWindow: SettingsWindowController?
    private var animationTimer: Timer?
    private var animationFrame = 0
    
    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "App")
        }
        
        rebuildMenu()
    }
    
    func setState(_ state: State) {
        guard let button = statusItem.button else { return }
        
        switch state {
        case .ready:
            stopAnimation()
            button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "Ready")
            button.appearsDisabled = false
        case .recording:
            button.appearsDisabled = false
            startAnimation(frames: recordingFrames, interval: 0.3)
        case .transcribing:
            button.appearsDisabled = false
            startAnimation(frames: transcribingFrames, interval: 0.25)
        case .error:
            stopAnimation()
            button.image = NSImage(systemSymbolName: "mic.badge.xmark", accessibilityDescription: "Error")
            button.appearsDisabled = true
        }
    }
    
    private func startAnimation(frames: [NSImage], interval: TimeInterval) {
        stopAnimation()
        animationFrame = 0
        animationTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self, let button = self.statusItem.button else { return }
            button.image = frames[self.animationFrame % frames.count]
            self.animationFrame += 1
        }
    }
    
    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }
    
    func rebuildMenu() {
        let menu = NSMenu()
        
        let titleItem = NSMenuItem(title: "App Name", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(NSMenuItem.separator())
        
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusItem.menu = menu
    }
    
    @objc private func openSettings() {
        // Show settings window
    }
}
```

#### Pattern B: SwiftUI MenuBarExtra (Petal-style)

```swift
import SwiftUI

@main
struct PetalApp: App {
    @State private var model: AppModel
    
    init() {
        let appModel = AppModel()
        _model = State(initialValue: appModel)
        NSApplication.shared.setActivationPolicy(.accessory)  // Hide dock icon
    }
    
    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(viewModel: MenuBarContentViewModel(appModel: model))
        } label: {
            Label("Petal", systemImage: model.menuBarSymbolName)
        }
        .menuBarExtraStyle(.menu)
    }
}

// Menu bar content
struct MenuBarContentView: View {
    @Bindable var viewModel: MenuBarContentViewModel
    
    var body: some View {
        Label(viewModel.statusTitle, systemImage: viewModel.statusSymbolName)
            .foregroundStyle(viewModel.statusColor)
        
        if viewModel.isRecording {
            Button("Stop Recording") {
                viewModel.stopRecording()
            }
        }
        
        Divider()
        
        Button("Settings...") {
            viewModel.openSettings()
        }
        .keyboardShortcut(",", modifiers: .command)
        
        Button("Quit") {
            viewModel.quit()
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
```

---

## 2. ARCHITECTURE IMPLEMENTATIONS

### 2.1 Project Structure

#### OwlWhisper (Simple, Single-Target)

```
OwlWhisper/
├── OwlWhisper/
│   ├── main.swift                 # Entry point
│   ├── AppDelegate.swift          # App lifecycle
│   ├── ASRService.swift           # Transcription service
│   ├── AudioRecorder.swift          # Audio capture
│   ├── HotkeyManager.swift        # Global shortcuts
│   ├── MenubarController.swift     # Menu bar UI
│   ├── FloatingIndicator.swift    # Overlay window
│   ├── SettingsWindowController.swift  # Settings UI
│   ├── ModelDownloader.swift      # Download manager
│   ├── PasteController.swift      # Clipboard/paste
│   ├── UpdateChecker.swift        # Update checks
│   └── Resources/
│       └── Localizable.strings
└── scripts/
    └── setup.sh                   # Model setup
```

#### Petal (Modular, Multi-Package)

```
petal/
├── petal/                         # Main app target
│   ├── PetalApp.swift            # App entry
│   ├── App/
│   │   ├── AppModel.swift        # Main observable model
│   │   ├── Settings/
│   │   │   ├── SettingsView.swift
│   │   │   └── SettingsViewModel.swift
│   │   └── AboutView.swift
│   ├── Views/
│   │   ├── MenuBarContentView.swift
│   │   └── MenuBar/
│   │       └── MenuBarContentViewModel.swift
│   └── Support/
│       └── PetalDeepLink.swift
├── PetalKit/                      # Swift package
│   ├── Package.swift
│   └── Sources/
│       ├── AudioClient/          # Audio recording client
│       ├── TranscriptionClient/  # Transcription client
│       ├── KeyboardClient/       # Keyboard monitoring
│       ├── WindowClient/         # Window management
│       ├── SoundClient/          # Sound effects
│       ├── HistoryClient/        # History persistence
│       ├── MLXClient/            # ML inference
│       ├── Shared/               # Shared types/keys
│       └── UI/                   # SwiftUI components
└── mlx-voxtral-swift/            # ML package dependency
```

---

### 2.2 Dependency Injection Approaches

#### Approach A: Constructor Injection (OwlWhisper-style)

```swift
class AppDelegate: NSObject, NSApplicationDelegate {
    private var menubarController: MenubarController!
    private var hotkeyManager: HotkeyManager!
    private var audioRecorder: AudioRecorder!
    private var asrService: ASRService?
    private var pasteController: PasteController!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create dependencies
        menubarController = MenubarController()
        pasteController = PasteController()
        audioRecorder = AudioRecorder()
        
        hotkeyManager = HotkeyManager()
        hotkeyManager.onKeyDown = { [weak self] in
            self?.startRecording()
        }
        
        menubarController.onHotkeyChanged = { [weak self] in
            self?.hotkeyManager.reload()
        }
    }
}
```

#### Approach B: Dependencies Framework with @Dependency (Petal-style)

```swift
import Dependencies

@MainActor
@Observable
final class AppModel {
    @ObservationIgnored @Dependency(\.transcriptionClient) private var transcriptionClient
    @ObservationIgnored @Dependency(\.audioClient) private var audioClient
    @ObservationIgnored @Dependency(\.pasteClient) private var pasteClient
    @ObservationIgnored @Dependency(\.permissionsClient) private var permissionsClient
    
    func startRecording() async {
        // Use injected dependencies
        try? await audioClient.startRecording { level in
            self.updateLevel(level)
        }
        
        let transcript = try? await transcriptionClient.transcribe(audioURL, model, mode, nil)
        await pasteClient.paste(transcript, true)
    }
}
```

---

### 2.3 Multiple Transcription Backends

```swift
enum TranscriptionBackend {
    case whisperLocal(modelPath: String)
    case appleSpeech
    case mlxPipeline(model: MLXPipelineModel)
}

protocol TranscriptionProvider {
    func transcribe(_ audioURL: URL, options: TranscriptionOptions) async throws -> String
}

struct WhisperProvider: TranscriptionProvider {
    func transcribe(_ audioURL: URL, options: TranscriptionOptions) async throws -> String {
        // Use Whisper model
        return ""
    }
}

struct AppleSpeechProvider: TranscriptionProvider {
    @available(macOS 26, *)
    func transcribe(_ audioURL: URL, options: TranscriptionOptions) async throws -> String {
        #if canImport(Speech)
        let transcriber = SpeechTranscriber(locale: Locale.current)
        // ... transcription logic
        #endif
        return ""
    }
}

struct TranscriptionService {
    private let providers: [TranscriptionBackend: TranscriptionProvider]
    
    func transcribe(_ audioURL: URL, backend: TranscriptionBackend) async throws -> String {
        guard let provider = providers[backend] else {
            throw TranscriptionError.unsupportedBackend
        }
        return try await provider.transcribe(audioURL, options: defaultOptions)
    }
}
```

---

### 2.4 State Management Patterns

#### Pattern A: Simple State Enum (OwlWhisper)

```swift
class MenubarController {
    enum State {
        case ready
        case recording
        case transcribing
        case error
    }
    
    func setState(_ state: State) {
        // Update UI based on state
    }
}
```

#### Pattern B: Observable with @Observable (Petal)

```swift
@MainActor
@Observable
final class AppModel {
    enum ProcessingStage: Equatable {
        case trimming
        case speeding
        case transcribing
        case refining
    }
    
    enum SessionState: Equatable {
        case idle
        case recording
        case processing(ProcessingStage)
        case error(String)
    }
    
    var sessionState: SessionState = .idle
    var lastError: String?
    var transientMessage: String?
    
    var statusTitle: String {
        switch sessionState {
        case .idle: return hasCompletedSetup ? "Ready" : "Setup Required"
        case .recording: return "REC"
        case let .processing(stage):
            switch stage {
            case .trimming: return "Trimming"
            case .transcribing: return "Transcribing"
            default: return "Processing"
            }
        case .error: return "Error"
        }
    }
}
```

---

### 2.5 Error Handling Strategies

```swift
// Define domain-specific errors
enum TranscriptionError: LocalizedError {
    case modelNotFound
    case audioTooShort
    case noSpeechDetected
    case backendUnavailable
    case permissionDenied
    
    var errorDescription: String? {
        switch self {
        case .modelNotFound: return "Transcription model not found"
        case .audioTooShort: return "Audio too short"
        case .noSpeechDetected: return "No speech detected in recording"
        case .backendUnavailable: return "Transcription service unavailable"
        case .permissionDenied: return "Permission denied"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .modelNotFound: return "Please download the required model in settings"
        case .permissionDenied: return "Grant permission in System Settings"
        default: return nil
        }
    }
}

// Usage with async/await
do {
    let transcript = try await transcribe(audioURL)
} catch let error as TranscriptionError {
    // Handle known errors
    showError(error.localizedDescription, suggestion: error.recoverySuggestion)
} catch {
    // Handle unknown errors
    reportIssue(error)
    showGenericError()
}

// Result type for callbacks
func transcribe(audioData: Data, completion: @escaping (Result<TranscriptionResult, Error>) -> Void) {
    queue.async {
        do {
            let result = try performTranscription(audioData)
            DispatchQueue.main.async {
                completion(.success(result))
            }
        } catch {
            DispatchQueue.main.async {
                completion(.failure(error))
            }
        }
    }
}
```

---

## 3. TROUBLESHOOTING/DEBUGGING

### 3.1 Permission Handling

```swift
import AVFoundation
import Cocoa

class PermissionManager {
    
    // MARK: - Microphone
    
    func checkMicrophonePermission() -> AVAuthorizationStatus {
        return AVCaptureDevice.authorizationStatus(for: .audio)
    }
    
    func requestMicrophonePermission() async -> Bool {
        let status = checkMicrophonePermission()
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
    
    func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
    
    // MARK: - Accessibility
    
    func checkAccessibilityPermission() -> Bool {
        return AXIsProcessTrusted()
    }
    
    func requestAccessibilityPermission() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
    }
    
    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

// Continuous monitoring
func startPermissionMonitoring() {
    permissionMonitorTask?.cancel()
    permissionMonitorTask = Task { [weak self] in
        while !Task.isCancelled {
            guard let self else { return }
            await self.refreshPermissionStatusAsync()
            try? await Task.sleep(for: .seconds(1))
        }
    }
}
```

---

### 3.2 Error Recovery Patterns

```swift
// Retry with exponential backoff
func retryWithBackoff<T>(maxAttempts: Int = 3, operation: () async throws -> T) async throws -> T {
    var lastError: Error?
    
    for attempt in 0..<maxAttempts {
        do {
            return try await operation()
        } catch {
            lastError = error
            let delay = Double(pow(2.0, Double(attempt)))  // 1s, 2s, 4s
            try? await Task.sleep(for: .seconds(delay))
        }
    }
    
    throw lastError ?? TranscriptionError.unknown
}

// Degraded mode fallback
func transcribeWithFallback(_ audioURL: URL) async -> String {
    do {
        // Try primary backend
        return try await primaryBackend.transcribe(audioURL)
    } catch {
        logWarning("Primary backend failed: \(error)")
        
        do {
            // Fallback to Apple Speech
            return try await appleSpeechBackend.transcribe(audioURL)
        } catch {
            logError("Fallback also failed: \(error)")
            return "[Transcription failed]"
        }
    }
}

// Circuit breaker pattern
class CircuitBreaker {
    private var failures = 0
    private let threshold = 5
    private var lastFailure: Date?
    private let resetTimeout: TimeInterval = 60
    
    var isOpen: Bool {
        if failures >= threshold {
            if let last = lastFailure, Date().timeIntervalSince(last) > resetTimeout {
                failures = 0
                return false
            }
            return true
        }
        return false
    }
    
    func recordSuccess() {
        failures = 0
    }
    
    func recordFailure() {
        failures += 1
        lastFailure = Date()
    }
}
```

---

### 3.3 Logging Approaches

```swift
import os.log

// Modern OSLog (preferred)
class AudioService {
    private let logger = Logger(subsystem: "com.app.transcription", category: "Audio")
    
    func startRecording() {
        logger.info("Starting audio recording")
        
        do {
            try performStart()
            logger.debug("Audio engine started successfully")
        } catch {
            logger.error("Failed to start recording: \(error.localizedDescription)")
        }
    }
}

// Console log for debugging
func consoleLog(_ message: String) {
    #if DEBUG
    print("[\(Date())] \(message)")
    #endif
}

// File-based debug logging
class FileLogger {
    private let logFile: URL
    private let dateFormatter: DateFormatter
    
    init() {
        logFile = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("debug.log")
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    }
    
    func log(_ message: String, level: LogLevel = .info) {
        let timestamp = dateFormatter.string(from: Date())
        let line = "[\(timestamp)] [\(level.rawValue)] \(message)\n"
        
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFile.path) {
                if let handle = try? FileHandle(forWritingTo: logFile) {
                    _ = handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.close()
                }
            } else {
                try? data.write(to: logFile)
            }
        }
    }
    
    enum LogLevel: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
    }
}
```

---

### 3.4 Crash Handling

```swift
import Foundation

class CrashReporter {
    static func setup() {
        // Catch uncaught exceptions
        NSSetUncaughtExceptionHandler { exception in
            let stack = exception.callStackSymbols.joined(separator: "\n")
            CrashReporter.saveCrashReport(
                type: "Exception",
                name: exception.name.rawValue,
                reason: exception.reason ?? "Unknown",
                stack: stack
            )
        }
        
        // Catch signals
        let signals: [Int32] = [SIGILL, SIGTRAP, SIGABRT, SIGFPE, SIGBUS, SIGSEGV]
        for signal in signals {
            signal(signal) { sig in
                let stack = Thread.callStackSymbols.joined(separator: "\n")
                CrashReporter.saveCrashReport(
                    type: "Signal",
                    name: "Signal \(sig)",
                    reason: "Process received signal \(sig)",
                    stack: stack
                )
                exit(sig)
            }
        }
    }
    
    static func saveCrashReport(type: String, name: String, reason: String, stack: String) {
        let report = """
        Crash Report
        ============
        Date: \(Date())
        Type: \(type)
        Name: \(name)
        Reason: \(reason)
        
        Stack Trace:
        \(stack)
        """
        
        let crashFile = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("crash_\(Int(Date().timeIntervalSince1970)).txt")
        
        try? report.write(to: crashFile, atomically: true, encoding: .utf8)
    }
}
```

---

### 3.5 Model Loading Failures

```swift
class ModelManager {
    enum LoadResult {
        case success(Model)
        case needsDownload
        case corrupted
        case incompatible
        case error(Error)
    }
    
    func loadModel(named name: String) -> LoadResult {
        let modelPath = modelsDirectory.appendingPathComponent(name)
        
        // Check existence
        guard FileManager.default.fileExists(atPath: modelPath.path) else {
            return .needsDownload
        }
        
        // Verify integrity (checksum)
        if !verifyChecksum(for: modelPath) {
            return .corrupted
        }
        
        // Check version compatibility
        if !checkVersionCompatibility(name) {
            return .incompatible
        }
        
        do {
            let model = try loadModelFromDisk(modelPath)
            return .success(model)
        } catch {
            return .error(error)
        }
    }
    
    func handleLoadFailure(_ result: LoadResult, modelName: String) {
        switch result {
        case .needsDownload:
            showDownloadPrompt(for: modelName)
        case .corrupted:
            showAlert("Model appears corrupted. Re-download?", actions: [
                "Re-download": { self.repairModel(named: modelName) },
                "Cancel": {}
            ])
        case .incompatible:
            showAlert("Model incompatible with this app version. Please update the app.")
        case .error(let error):
            reportIssue(error)
            showGenericError()
        case .success:
            break
        }
    }
    
    private func repairModel(named name: String) {
        // Delete corrupted model
        let path = modelsDirectory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: path)
        
        // Trigger re-download
        downloadModel(named: name)
    }
}
```

---

## 4. SWIFTUI/macOS SPECIFIC PATTERNS

### 4.1 Menu Bar App Architecture

```swift
import SwiftUI

@main
struct MenuBarApp: App {
    @State private var model = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    
    init() {
        NSApplication.shared.setActivationPolicy(.accessory)  // No dock icon
    }
    
    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(systemName: model.menuBarIcon)
        }
        .menuBarExtraStyle(.menu)
    }
}

// Window management
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Setup complete
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        return false  // Don't show dock icon on re-open
    }
}
```

---

### 4.2 Floating Window/Overlay Patterns

#### Pattern A: NSWindow-based (OwlWhisper)

```swift
import Cocoa

class FloatingIndicator {
    private var window: NSWindow?
    
    func show() {
        ensureWindow()
        
        // Position at bottom center of screen
        if let screen = NSScreen.main {
            let frame = window!.frame
            let x = screen.frame.midX - frame.width / 2
            let y = screen.visibleFrame.minY + 4
            window?.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        // Fade in
        window?.alphaValue = 0
        window?.orderFrontRegardless()
        
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            window?.animator().alphaValue = 1
        }
    }
    
    private func ensureWindow() {
        guard window == nil else { return }
        
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 40),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        
        // Visual styling
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = .statusBar  // Float above other windows
        win.hasShadow = false
        win.ignoresMouseEvents = true  // Click-through
        win.collectionBehavior = [.canJoinAllSpaces, .stationary]
        
        // Add visual effect view
        let bg = NSVisualEffectView(frame: win.contentRect)
        bg.blendingMode = .behindWindow
        bg.material = .hudWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 20
        bg.appearance = NSAppearance(named: .darkAqua)
        win.contentView = bg
        
        window = win
    }
    
    func hide() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            window?.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.window?.orderOut(nil)
        })
    }
}
```

#### Pattern B: SwiftUI-based Window (Petal)

```swift
import SwiftUI

struct FloatingCapsuleView: View {
    @Bindable var state: FloatingCapsuleState
    
    var body: some View {
        Group {
            switch state.phase {
            case .recording:
                recordingContent
            case .transcribing:
                transcribingContent
            case .hidden:
                EmptyView()
            default:
                EmptyView()
            }
        }
        .fixedSize()
        .animation(.easeInOut(duration: 0.35), value: state.phase)
    }
    
    private var recordingContent: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
            Text("REC")
                .font(.footnote.weight(.semibold))
            RecordingBars(level: state.level)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }
}

// Window management
@DependencyClient
struct WindowClient: Sendable {
    var show: @Sendable (_ config: WindowConfig, _ content: @escaping @MainActor @Sendable () -> NSView) async -> Void
    var close: @Sendable (_ id: String) async -> Void
}
```

---

### 4.3 Settings UI Patterns

#### Pattern A: NSWindowController (AppKit)

```swift
import Cocoa

class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    
    func show() {
        if let w = window, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 400),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        
        // Modern title bar
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.delegate = self
        
        // Add visual effect background
        let vfx = NSVisualEffectView()
        vfx.blendingMode = .behindWindow
        vfx.material = .windowBackground
        vfx.state = .followsWindowActiveState
        w.contentView = vfx
        
        // Add stack view for content
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 12
        vfx.addSubview(stack)
        
        // Add controls...
        
        window = w
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func windowWillClose(_ notification: Notification) {
        // Cleanup
    }
}
```

#### Pattern B: SwiftUI Settings (Modern)

```swift
import SwiftUI

struct SettingsView: View {
    @State var selectedTab: SettingsTab = .general
    @Bindable var viewModel: SettingsViewModel
    
    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("General", systemImage: "gearshape", value: .general) {
                GeneralPane(viewModel: viewModel)
            }
            Tab("Transcription", systemImage: "waveform", value: .transcription) {
                TranscriptionPane(viewModel: viewModel)
            }
            Tab("Shortcuts", systemImage: "keyboard", value: .shortcuts) {
                ShortcutsPane(viewModel: viewModel)
            }
        }
        .frame(width: 500, height: 400)
    }
}

struct GeneralPane: View {
    @Bindable var viewModel: SettingsViewModel
    
    var body: some View {
        Form {
            Section("Permissions") {
                LabeledContent("Microphone") {
                    if viewModel.microphoneAuthorized {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Grant Access") {
                            viewModel.requestMicrophonePermission()
                        }
                    }
                }
            }
            
            Section("Shortcuts") {
                LabeledContent("Push to Talk") {
                    KeyboardShortcuts.Recorder(for: .pushToTalk)
                }
            }
        }
        .formStyle(.grouped)
    }
}
```

---

### 4.4 SwiftUI + AppKit Integration

```swift
import SwiftUI
import Cocoa

// Hosting NSView in SwiftUI
struct NSViewWrapper: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // Configure
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// Hosting SwiftUI in NSWindow
func showSwiftUIWindow<Content: View>(@ViewBuilder content: () -> Content) {
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
    )
    
    window.contentView = NSHostingView(rootView: content())
    window.center()
    window.makeKeyAndOrderFront(nil)
}

// Integration pattern used in Petal
class AppDelegate: NSObject, NSApplicationDelegate {
    @Dependency(\.windowClient) private var windowClient
    
    @objc func showAboutPanel() {
        NSApp.setActivationPolicy(.regular)  // Show in dock temporarily
        
        Task {
            await windowClient.show(.about, {
                NSHostingView(rootView: AboutView())
            }, {
                NSApp.setActivationPolicy(.accessory)  // Hide dock again
            })
        }
    }
}

// WindowClient implementation
@MainActor
final class WindowRuntime {
    static let shared = WindowRuntime()
    private var windows: [String: NSWindow] = [:]
    
    func show(config: WindowConfig, content: () -> NSView, onClose: () -> Void) {
        let window = NSWindow(
            contentRect: config.frame,
            styleMask: config.styleMask,
            backing: .buffered,
            defer: false
        )
        
        window.contentView = content()
        window.isReleasedWhenClosed = false
        
        // Store reference
        windows[config.id] = window
        
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
    
    func close(id: String) {
        windows[id]?.close()
        windows.removeValue(forKey: id)
    }
}
```

---

### 4.5 Animation Patterns

```swift
import SwiftUI

// Recording bars animation
struct RecordingBars: View {
    let level: Double
    @State private var animating = false
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5) { i in
                RoundedRectangle(cornerRadius: 1)
                    .frame(width: 3, height: height(for: i))
                    .animation(.easeInOut(duration: 0.1), value: level)
            }
        }
    }
    
    private func height(for index: Int) -> CGFloat {
        let base = CGFloat(level) * 20
        let offset = CGFloat(index) * 2
        return max(4, base + offset)
    }
}

// Blinking animation
struct BlinkingLight: View {
    @State private var isOn = false
    
    var body: some View {
        Circle()
            .fill(isOn ? Color.red : Color.red.opacity(0.3))
            .frame(width: 8, height: 8)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    isOn = true
                }
            }
    }
}

// Shimmer effect for loading
struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        gradient: Gradient(colors: [.clear, .white.opacity(0.5), .clear]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 2)
                    .offset(x: -geo.size.width + phase * geo.size.width * 2)
                }
                .mask(content)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}
```

---

## 5. KEY RECOMMENDATIONS FOR OPENOATS

### Architecture Choices

1. **Start Simple**: Begin with OwlWhisper's single-target approach for faster iteration
2. **Migrate Gradually**: Move to Petal's modular package structure as complexity grows
3. **Use @Observable**: Adopt SwiftUI's native observation over ObservableObject for macOS 14+

### Critical Implementation Details

1. **Always check CGEventTap status**: System can disable it - implement re-enable timer
2. **Use standby recorders**: Pre-warm AVAudioRecorder for instant recording start
3. **Implement chunked downloads**: Models are large - resume capability is essential
4. **Monitor permissions continuously**: Users revoke permissions - don't assume state
5. **Handle stop() during transcription**: Use generation counter to detect stale operations

### Testing Strategies

```swift
// From Petal: Environment-based testing
static var isRunningInSwiftUIPreview: Bool {
    ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
}

static var isRunningUnattendedE2E: Bool {
    ProcessInfo.processInfo.environment["PETAL_UNATTENDED_E2E"] == "1"
}

// Use in model init
init() {
    if Self.isRunningInSwiftUIPreview {
        // Mock state for previews
        microphoneAuthorized = true
        hasCompletedSetup = true
    }
}
```

### Performance Tips

1. **Lazy load models**: Don't load at startup - use `preload()` when recording starts
2. **Idle unload**: Free memory after 60s of inactivity
3. **Use actors for file I/O**: Serialize writes with Swift actors
4. **Profile transcription**: Track RTF (Real-Time Factor) per model

---

## Source Repositories

- **OwlWhisper**: https://github.com/sanvibyfish/OwlWhisper
- **Petal**: https://github.com/Aayush9029/petal

---

*Document created for OpenOats development reference*
