import Foundation
import os

// MARK: - AssemblyAI Transcription Service

/// Actor-based cloud transcription service for AssemblyAI.
/// Implements `BatchTranscriptionService` for file-based transcription.
@available(macOS 15.0, *)
public actor AssemblyAITranscriptionService: BatchTranscriptionService {
    
    // MARK: - Properties
    
    public nonisolated let backendID: BackendID = BackendID("assemblyai")
    public nonisolated let displayName: String = "AssemblyAI"
    public nonisolated let supportedFormats: [AudioFormat] = [.wav, .mp3, .aac]
    public nonisolated let supportedLanguages: [LanguageCode] = [
        .english, .spanish, .french, .german, .italian,
        .portuguese, .chinese, .japanese, .korean
    ]
    public nonisolated let supportsSpeakerDiarization: Bool = true
    
    /// Configuration for the service.
    public let configuration: CloudTranscriptionConfiguration
    
    /// URLSession for network requests.
    private let urlSession: URLSession
    
    /// Logger for service operations.
    private static let log = Logger(
        subsystem: "com.openoats.app",
        category: "AssemblyAITranscriptionService"
    )
    
    // MARK: - Initialization
    
    /// Creates a new AssemblyAI transcription service.
    /// - Parameters:
    ///   - configuration: Cloud transcription configuration.
    ///   - urlSession: URLSession for network requests (optional, uses ephemeral by default).
    public init(
        configuration: CloudTranscriptionConfiguration,
        urlSession: URLSession? = nil
    ) {
        self.configuration = configuration
        self.urlSession = urlSession ?? URLSession(configuration: .ephemeral)
    }
    
    // MARK: - TranscriptionService Protocol
    
    /// Checks if the service is available by validating the API key.
    /// - Returns: true if the API key is valid and the service is reachable.
    public func isAvailable() async -> Bool {
        guard let secureAPIKey = await configuration.secureAPIKey else {
            Self.log.warning("API key not configured for AssemblyAI")
            return false
        }
        
        do {
            return try await secureAPIKey.withSecureAccess { apiKey in
                try await validateAPIKey(apiKey)
            }
        } catch {
            Self.log.error("API key validation failed: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Validates an audio file for transcription.
    /// - Parameter audioURL: URL to the audio file.
    /// - Returns: Validation result indicating if the file is valid.
    public func validateAudioFile(_ audioURL: URL) async -> ValidationResult {
        let pathExtension = audioURL.pathExtension.lowercased()
        
        // Map file extension to AudioFormat
        guard let format = AudioFormat(fromExtension: pathExtension) else {
            return ValidationResult.cloudInvalid(
                reason: "Unsupported file format: \(pathExtension)"
            )
        }
        
        // Check if format is supported
        guard supportedFormats.contains(format) else {
            return ValidationResult.cloudInvalid(
                reason: "Format \(format) is not supported. Supported: \(supportedFormats.map { $0.rawValue }.joined(separator: ", "))"
            )
        }
        
        // Verify file exists and is readable
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: audioURL.path) else {
            return ValidationResult.cloudInvalid(
                reason: "File not found: \(audioURL.path)"
            )
        }
        
        // Try to read file to verify it's valid
        do {
            let attributes = try fileManager.attributesOfItem(atPath: audioURL.path)
            guard let fileSize = attributes[.size] as? UInt64, fileSize > 0 else {
                return ValidationResult.cloudInvalid(
                    reason: "File is empty"
                )
            }
            
            // For WAV files, validate header
            if format == .wav {
                guard await validateWAVFile(audioURL) else {
                    return ValidationResult.cloudInvalid(
                        reason: "Invalid WAV file header"
                    )
                }
            }
            
            // Estimate duration based on file size and format
            let estimatedDuration = estimateDuration(fileSize: Int(fileSize), format: format)
            
            return ValidationResult(
                isValid: true,
                format: format,
                duration: estimatedDuration,
                error: nil
            )
            
        } catch {
            return ValidationResult.cloudInvalid(
                reason: "File read error: \(error.localizedDescription)"
            )
        }
    }
    
    // MARK: - BatchTranscriptionService Protocol
    
    /// Transcribes an audio file using AssemblyAI's API.
    /// - Parameters:
    ///   - audioURL: URL to the audio file.
    ///   - language: Target language code (nil = auto-detect).
    ///   - speakerDiarization: Whether to identify different speakers.
    ///   - progressHandler: Callback for progress updates.
    /// - Returns: Full transcription result.
    public func transcribeFile(
        at audioURL: URL,
        language: LanguageCode?,
        speakerDiarization: Bool,
        progressHandler: (@Sendable (TranscriptionProgress) -> Void)?
    ) async throws -> BatchTranscriptionResult {
        
        guard let secureAPIKey = await configuration.secureAPIKey else {
            throw TranscriptionError.backendFailed(
                backend: backendID.rawValue,
                reason: "API key not configured",
                recoverable: false
            )
        }
        
        // Validate audio file
        let validation = await validateAudioFile(audioURL)
        guard validation.isValid else {
            throw TranscriptionError.audioFormatUnsupported(
                format: audioURL.pathExtension,
                supportedFormats: supportedFormats.map { $0.rawValue }
            )
        }
        
        let startTime = Date()
        
        do {
            // Phase 1: Upload audio file
            Self.log.info("Starting audio upload for \(audioURL.lastPathComponent)")
            
            progressHandler?(
                TranscriptionProgress(
                    audioProcessed: .seconds(0),
                    totalDuration: validation.duration ?? .seconds(60),
                    percentage: 0.0,
                    estimatedTimeRemaining: nil
                )
            )
            
            let audioData = try Data(contentsOf: audioURL)
            let totalDurationSeconds = validation.duration?.components.seconds ?? 60
            
            let uploadURL = try await secureAPIKey.withSecureAccess { apiKey in
                try await uploadAudio(audioData, apiKey: apiKey) { uploadedBytes in
                let totalBytes = audioData.count
                let progress = Double(uploadedBytes) / Double(totalBytes)
                progressHandler?(
                    TranscriptionProgress(
                        audioProcessed: .seconds(Int64(progress * Double(totalDurationSeconds))),
                        totalDuration: validation.duration ?? .seconds(60),
                        percentage: progress * 0.3, // Upload is 30% of total
                        estimatedTimeRemaining: nil
                    )
                )
            }
            
            // Phase 2: Create transcript
            Self.log.info("Creating transcript job")
            progressHandler?(
                TranscriptionProgress(
                    audioProcessed: .seconds(0),
                    totalDuration: validation.duration ?? .seconds(60),
                    percentage: 0.3,
                    estimatedTimeRemaining: nil
                )
            )
            
            let transcriptID = try await secureAPIKey.withSecureAccess { apiKey in
                try await createTranscript(
                    uploadURL: uploadURL,
                    language: language,
                    speakerDiarization: speakerDiarization,
                    apiKey: apiKey
                )
            }
            
            // Phase 3: Poll for completion
            Self.log.info("Polling transcript \(transcriptID)")
            
            let (text, segments) = try await secureAPIKey.withSecureAccess { apiKey in
                try await pollTranscript(
                    id: transcriptID,
                    apiKey: apiKey,
                    totalDuration: validation.duration,
                    progressHandler: progressHandler
                )
            }
            
            let processingTime = Date().timeIntervalSince(startTime)
            
            Self.log.info("Transcription completed: \(transcriptID)")
            
            return BatchTranscriptionResult(
                transcriptID: TranscriptID(),
                segments: segments,
                fullText: text,
                language: language ?? .english,
                duration: validation.duration ?? .seconds(0),
                processingTime: .seconds(Int64(processingTime))
            )
            
        } catch let error as TranscriptionError {
            throw error
        } catch {
            throw mapError(error)
        }
    }
    
    /// Convenience overload with default parameters.
    public func transcribeFile(
        at audioURL: URL,
        language: LanguageCode?
    ) async throws -> BatchTranscriptionResult {
        return try await transcribeFile(
            at: audioURL,
            language: language,
            speakerDiarization: false,
            progressHandler: nil
        )
    }
    
    /// Estimates processing time for an audio file.
    /// - Parameter audioURL: URL to the audio file.
    /// - Returns: Estimated processing time.
    public func estimateProcessingTime(for audioURL: URL) async -> Duration {
        let validation = await validateAudioFile(audioURL)
        guard let duration = validation.duration else {
            return .seconds(30) // Default estimate
        }
        
        // AssemblyAI typically processes at ~1x real-time or faster
        // Add some buffer for upload and polling overhead
        let estimatedSeconds = Double(duration.components.seconds) * 1.5 + 10
        return .seconds(Int64(estimatedSeconds))
    }
    
    // MARK: - Streaming Upload
    
    /// Uploads audio data in a streaming fashion with progress tracking.
    /// - Parameters:
    ///   - audioStream: Async stream of audio data chunks.
    ///   - progressHandler: Callback for upload progress (0.0 to 1.0).
    /// - Returns: The upload URL from AssemblyAI.
    public func uploadStreaming(
        audioStream: AsyncStream<Data>,
        progressHandler: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        guard let secureAPIKey = await configuration.secureAPIKey else {
            throw TranscriptionError.backendFailed(
                backend: backendID.rawValue,
                reason: "API key not configured",
                recoverable: false
            )
        }
        
        // Collect all data from stream (AssemblyAI requires full file for upload endpoint)
        var totalData = Data()
        var uploadedBytes = 0
        
        for try await chunk in audioStream {
            totalData.append(chunk)
            uploadedBytes += chunk.count
            
            // Report progress as indeterminate since we don't know total size
            progressHandler?(Double(uploadedBytes) / Double(uploadedBytes + 1024 * 1024))
        }
        
        // Use a local copy to avoid capture issues
        let finalData = totalData
        return try await secureAPIKey.withSecureAccess { apiKey in
            try await uploadAudio(finalData, apiKey: apiKey) { bytes in
                let progress = Double(bytes) / Double(finalData.count)
                progressHandler?(progress)
            }
        }
    }
    
    // MARK: - Private API Methods
    
    private func validateAPIKey(_ apiKey: String) async throws -> Bool {
        // SEC-001 Fix: Use SecureURLConstruction to prevent URL injection
        let url = try SecureURLConstruction.assemblyAPIURL(path: "transcript")
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            throw TranscriptionError.backendFailed(
                backend: backendID.rawValue,
                reason: "Invalid URL for API validation",
                recoverable: true
            )
        }
        components.queryItems = [URLQueryItem(name: "limit", value: "1")]
        guard let finalURL = components.url else {
            throw TranscriptionError.backendFailed(
                backend: backendID.rawValue,
                reason: "Invalid URL for API validation",
                recoverable: true
            )
        }
        
        var request = URLRequest(url: finalURL)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10
        
        let (_, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }
        
        return (200..<300).contains(httpResponse.statusCode)
    }
    
    private func uploadAudio(
        _ audioData: Data,
        apiKey: String,
        progressHandler: (@Sendable (Int) -> Void)?
    ) async throws -> URL {
        // SEC-001 Fix: Use SecureURLConstruction to prevent URL injection
        let uploadEndpointURL = try SecureURLConstruction.assemblyAPIURL(path: "upload")
        
        var request = URLRequest(url: uploadEndpointURL)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.httpBody = audioData
        
        // Report initial progress
        progressHandler?(0)
        
        let maxRetries = await configuration.retryPolicy.maxRetries
        let initialDelay = await configuration.retryPolicy.retryDelay
        let exponentialBackoff = await configuration.retryPolicy.exponentialBackoff
        
        return try await performRequestWithRetry(
            request: request,
            maxRetries: maxRetries,
            initialDelay: initialDelay,
            exponentialBackoff: exponentialBackoff
        ) { data, response in
            // Report completion
            progressHandler?(audioData.count)
            
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let urlString = json?["upload_url"] as? String,
                  let url = URL(string: urlString) else {
                throw TranscriptionError.backendFailed(
                    backend: self.backendID.rawValue,
                    reason: "Invalid upload URL in response",
                    recoverable: true
                )
            }
            
            return url
        }
    }
    
    private func createTranscript(
        uploadURL: URL,
        language: LanguageCode?,
        speakerDiarization: Bool,
        apiKey: String
    ) async throws -> String {
        var body: [String: Any] = [
            "audio_url": uploadURL.absoluteString,
            "speech_model": "universal_3_pro"
        ]
        
        if let languageCode = language?.rawValue, languageCode != "auto" {
            body["language_code"] = languageCode
        }
        
        if speakerDiarization {
            body["speaker_labels"] = true
        }
        
        // SEC-001 Fix: Use SecureURLConstruction to prevent URL injection
        let transcriptEndpointURL = try SecureURLConstruction.assemblyAPIURL(path: "transcript")
        
        var request = URLRequest(url: transcriptEndpointURL)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let maxRetries = await configuration.retryPolicy.maxRetries
        let initialDelay = await configuration.retryPolicy.retryDelay
        let exponentialBackoff = await configuration.retryPolicy.exponentialBackoff
        
        return try await performRequestWithRetry(
            request: request,
            maxRetries: maxRetries,
            initialDelay: initialDelay,
            exponentialBackoff: exponentialBackoff
        ) { data, response in
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            // Check for API errors in response
            if let errorMessage = json?["error"] as? String {
                throw TranscriptionError.backendFailed(
                    backend: self.backendID.rawValue,
                    reason: errorMessage,
                    recoverable: false
                )
            }
            
            guard let id = json?["id"] as? String else {
                throw TranscriptionError.backendFailed(
                    backend: self.backendID.rawValue,
                    reason: "Missing transcript ID in response",
                    recoverable: true
                )
            }
            
            return id
        }
    }
    
    private func pollTranscript(
        id: String,
        apiKey: String,
        totalDuration: Duration?,
        progressHandler: (@Sendable (TranscriptionProgress) -> Void)?
    ) async throws -> (String, [TranscriptionSegment]) {
        // SEC-001 Fix: Use SecureURLConstruction to prevent URL injection
        let pollURL = try SecureURLConstruction.pollURL(forTranscriptID: id)
        
        let maxPollAttempts = 120 // 60 seconds with 500ms intervals
        let pollInterval: Duration = .milliseconds(500)
        let totalDurationSeconds = totalDuration?.components.seconds ?? 60
        
        for attempt in 0..<maxPollAttempts {
            try Task.checkCancellation()
            
            var request = URLRequest(url: pollURL)
            request.httpMethod = "GET"
            request.setValue(apiKey, forHTTPHeaderField: "Authorization")
            
            let (data, response) = try await urlSession.data(for: request)
            try checkHTTPStatus(response)
            
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let status = json?["status"] as? String
            
            // Calculate progress (upload was 30%, processing is 30-90%, finalization 90-100%)
            let processingProgress = min(Double(attempt) / Double(maxPollAttempts), 1.0)
            let totalProgress = 0.3 + (processingProgress * 0.7)
            
            progressHandler?(
                TranscriptionProgress(
                    audioProcessed: .seconds(Int64(processingProgress * Double(totalDurationSeconds))),
                    totalDuration: totalDuration ?? .seconds(60),
                    percentage: totalProgress,
                    estimatedTimeRemaining: .seconds(Int64(Double(maxPollAttempts - attempt) / 2.0))
                )
            )
            
            switch status {
            case "completed":
                let text = json?["text"] as? String ?? ""
                let segments = parseSegments(from: json)
                progressHandler?(
                    TranscriptionProgress(
                        audioProcessed: totalDuration ?? .seconds(0),
                        totalDuration: totalDuration ?? .seconds(0),
                        percentage: 1.0,
                        estimatedTimeRemaining: nil
                    )
                )
                return (text, segments)
                
            case "error":
                let errorMessage = json?["error"] as? String ?? "Unknown transcription error"
                throw TranscriptionError.backendFailed(
                    backend: backendID.rawValue,
                    reason: errorMessage,
                    recoverable: false
                )
                
            default:
                // Still processing, wait and retry
                try await Task.sleep(for: pollInterval)
            }
        }
        
        throw TranscriptionError.timeout(
            operation: "poll transcript",
            duration: .seconds(60)
        )
    }
    
    // MARK: - Private Helpers
    
    private func performRequestWithRetry<T>(
        request: URLRequest,
        maxRetries: Int,
        initialDelay: Duration,
        exponentialBackoff: Bool,
        operation: (Data, URLResponse) async throws -> T
    ) async throws -> T {
        var lastError: Error?
        
        for attempt in 0..<(maxRetries + 1) {
            try Task.checkCancellation()
            
            do {
                let (data, response) = try await urlSession.data(for: request)
                try checkHTTPStatus(response)
                return try await operation(data, response)
                
            } catch let error as TranscriptionError {
                // Don't retry non-recoverable errors
                if case .backendFailed(_, _, let recoverable) = error, !recoverable {
                    throw error
                }
                lastError = error
                
            } catch let error as URLError {
                // Network errors are typically recoverable
                lastError = error
                
            } catch {
                lastError = error
            }
            
            // Calculate delay for next attempt
            if attempt < maxRetries {
                let delaySeconds = exponentialBackoff
                    ? initialDelay.components.seconds * Int64(1 << attempt)
                    : initialDelay.components.seconds
                try await Task.sleep(for: .seconds(delaySeconds))
            }
        }
        
        // All retries exhausted
        throw lastError ?? TranscriptionError.backendFailed(
            backend: backendID.rawValue,
            reason: "Request failed after \(maxRetries) retries",
            recoverable: true
        )
    }
    
    private func checkHTTPStatus(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.networkFailure(reason: "Invalid HTTP response")
        }
        
        switch httpResponse.statusCode {
        case 200..<300:
            return // Success
            
        case 401, 403:
            throw TranscriptionError.backendFailed(
                backend: backendID.rawValue,
                reason: "Invalid API key",
                recoverable: false
            )
            
        case 429:
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                .flatMap { Date(timeIntervalSinceNow: Double($0) ?? 60) }
            throw TranscriptionError.rateLimited(
                provider: backendID.rawValue,
                retryAfter: retryAfter
            )
            
        case 500..<600:
            throw TranscriptionError.backendFailed(
                backend: backendID.rawValue,
                reason: "Server error (HTTP \(httpResponse.statusCode))",
                recoverable: true
            )
            
        default:
            throw TranscriptionError.backendFailed(
                backend: backendID.rawValue,
                reason: "HTTP error \(httpResponse.statusCode)",
                recoverable: httpResponse.statusCode >= 500
            )
        }
    }
    
    private func mapError(_ error: Error) -> TranscriptionError {
        if let transcriptionError = error as? TranscriptionError {
            return transcriptionError
        }
        
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return TranscriptionError.timeout(
                    operation: "network request",
                    duration: .seconds(30)
                )
            case .notConnectedToInternet, .networkConnectionLost:
                return TranscriptionError.networkFailure(
                    reason: urlError.localizedDescription
                )
            default:
                return TranscriptionError.networkFailure(
                    reason: urlError.localizedDescription
                )
            }
        }
        
        return TranscriptionError.backendFailed(
            backend: backendID.rawValue,
            reason: error.localizedDescription,
            recoverable: true
        )
    }
    
    private func validateWAVFile(_ url: URL) async -> Bool {
        guard let fileHandle = try? FileHandle(forReadingFrom: url) else {
            return false
        }
        defer { try? fileHandle.close() }
        
        guard let header = try? fileHandle.read(upToCount: 12) else {
            return false
        }
        
        // Check RIFF header
        let riff = header.prefix(4)
        let wave = header.dropFirst(8).prefix(4)
        
        return riff == Data("RIFF".utf8) && wave == Data("WAVE".utf8)
    }
    
    private func estimateDuration(fileSize: Int, format: AudioFormat) -> Duration {
        // Rough estimates based on typical compression ratios
        let bytesPerSecond: Double
        switch format {
        case .wav:
            // 16-bit, 44.1kHz, mono: 88200 bytes/second
            bytesPerSecond = 88200
        case .mp3:
            // Typical 128kbps: 16000 bytes/second
            bytesPerSecond = 16000
        case .aac:
            // Typical 128kbps: 16000 bytes/second
            bytesPerSecond = 16000
        case .flac:
            // Variable, estimate ~700kbps: 87500 bytes/second
            bytesPerSecond = 87500
        }
        
        let seconds = Double(fileSize) / bytesPerSecond
        return .seconds(Int64(seconds))
    }
    
    private func parseSegments(from json: [String: Any]?) -> [TranscriptionSegment] {
        guard let words = json?["words"] as? [[String: Any]] else {
            return []
        }
        
        var segments: [TranscriptionSegment] = []
        var currentSegment: [WordInfo] = []
        
        for wordData in words {
            guard let text = wordData["text"] as? String,
                  let start = wordData["start"] as? Double,
                  let end = wordData["end"] as? Double,
                  let confidence = wordData["confidence"] as? Double else {
                continue
            }
            
            let speaker = wordData["speaker"] as? String
            let wordInfo = WordInfo(
                text: text,
                startTime: start / 1000, // Convert ms to seconds
                endTime: end / 1000,
                confidence: confidence,
                speakerID: speaker
            )
            
            // Group words into segments based on speaker changes and pauses
            if let lastWord = currentSegment.last,
               wordInfo.startTime - lastWord.endTime > 2.0 || // 2+ second pause
               wordInfo.speakerID != lastWord.speakerID { // Speaker changed
                
                if let segment = createSegment(from: currentSegment) {
                    segments.append(segment)
                }
                currentSegment = []
            }
            
            currentSegment.append(wordInfo)
        }
        
        // Add final segment
        if let segment = createSegment(from: currentSegment) {
            segments.append(segment)
        }
        
        return segments
    }
    
    private func createSegment(from words: [WordInfo]) -> TranscriptionSegment? {
        guard let first = words.first, let last = words.last else { return nil }
        
        let text = words.map { $0.text }.joined(separator: " ")
        let avgConfidence = words.map { $0.confidence }.reduce(0, +) / Double(words.count)
        
        let speakerID: SpeakerID? = words.compactMap { $0.speakerID }.first
            .map { _ in SpeakerID() }
        
        return TranscriptionSegment(
            id: UtteranceID(),
            text: text,
            startTime: .seconds(Int64(first.startTime)),
            endTime: .seconds(Int64(last.endTime)),
            confidence: avgConfidence,
            isPartial: false,
            speakerID: speakerID
        )
    }
}

// MARK: - Supporting Types

private struct WordInfo {
    let text: String
    let startTime: Double
    let endTime: Double
    let confidence: Double
    let speakerID: String?
}

// MARK: - AudioFormat Extension

private extension AudioFormat {
    init?(fromExtension fileExtension: String) {
        switch fileExtension.lowercased() {
        case "wav":
            self = .wav
        case "mp3":
            self = .mp3
        case "aac", "m4a":
            self = .aac
        case "flac":
            self = .flac
        default:
            return nil
        }
    }
}

// MARK: - ValidationResult Helper

extension ValidationResult {
    static func cloudInvalid(reason: String) -> ValidationResult {
        return ValidationResult(
            isValid: false,
            format: nil,
            duration: nil,
            error: .configurationFailed(reason: reason)
        )
    }
}
