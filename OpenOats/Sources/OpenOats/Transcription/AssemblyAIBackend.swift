import Foundation
import os

// MARK: - Cloud ASR shared error type

/// Errors for cloud-based ASR backends (AssemblyAI, ElevenLabs, etc.).
/// Response bodies are never included to avoid leaking sensitive data.
enum CloudASRError: LocalizedError {
    case invalidAPIKey(backend: String)
    case invalidUploadURL
    case httpError(statusCode: Int)
    case transcriptionFailed(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey(let backend):
            "Invalid \(backend) API key. Check Settings > Transcription."
        case .invalidUploadURL:
            "Cloud ASR received an invalid upload URL."
        case .httpError(let code):
            "Cloud ASR request failed (HTTP \(code))."
        case .transcriptionFailed(let msg):
            "Transcription failed: \(msg)"
        case .timeout:
            "Cloud ASR request timed out."
        }
    }
}

// MARK: - Transient Retry Helper

/// Retries a throwing async operation on transient HTTP failures (5xx, timeouts).
/// Respects task cancellation between attempts.
func withTransientRetry<T>(
    maxAttempts: Int = 3,
    initialDelay: Duration = .milliseconds(250),
    operation: () async throws -> T
) async throws -> T {
    var lastError: Error?
    for attempt in 0 ..< maxAttempts {
        try Task.checkCancellation()
        do {
            return try await operation()
        } catch let error as CloudASRError where error.isTransient {
            lastError = error
        } catch let error as URLError where error.code == .timedOut || error.code == .networkConnectionLost {
            lastError = error
        }
        if attempt < maxAttempts - 1 {
            let delay = initialDelay * (1 << attempt)
            try await Task.sleep(for: delay)
        }
    }
    throw lastError!
}

extension CloudASRError {
    var isTransient: Bool {
        if case .httpError(let code) = self { return code >= 500 }
        if case .timeout = self { return true }
        return false
    }
}

// MARK: - AssemblyAI Backend

/// Cloud transcription backend using the AssemblyAI REST API.
/// @unchecked Sendable: session and prepared are written once in prepare() before any transcribe() calls.
@available(macOS 15.0, *)
final class AssemblyAIBackend: TranscriptionBackend, @unchecked Sendable {
    let displayName = "AssemblyAI"

    // SEC-006 Fix: Use SecureString instead of plain String for API key
    private let secureAPIKey: SecureString
    private let customSpelling: [[String: Any]]
    private let session: URLSession
    private var prepared = false

    private static let log = Logger(subsystem: "com.openoats.app", category: "AssemblyAI")

    // MARK: - Init

    /// Creates a new AssemblyAI backend with secure API key storage.
    ///
    /// - Parameters:
    ///   - apiKey: API key as a SecureString (preferred) or plain String
    ///   - customVocabulary: Custom vocabulary for transcription
    init(apiKey: SecureString, customVocabulary: String = "") {
        self.secureAPIKey = apiKey
        self.customSpelling = Self.parseCustomSpelling(customVocabulary)
        self.session = URLSession(configuration: .ephemeral)
    }

    /// Creates a new AssemblyAI backend with plain string API key.
    /// - Warning: Prefer the SecureString variant for production code.
    convenience init(apiKey: String, customVocabulary: String = "") {
        let secureKey = SecureString(apiKey)
        self.init(apiKey: secureKey, customVocabulary: customVocabulary)
    }

    // MARK: - TranscriptionBackend

    func checkStatus() -> BackendStatus {
        .ready
    }

    func prepare(
        onStatus: @Sendable (String) -> Void,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard !secureAPIKey.isEmpty else {
            throw CloudASRError.invalidAPIKey(backend: "AssemblyAI")
        }

        onStatus("Validating AssemblyAI API key...")
        
        // Use withSecureAccess to temporarily access the API key
        try await secureAPIKey.withSecureAccess { apiKey in
            // SEC-004 Fix: Use SecureURLConstruction to prevent URL injection
            let url = try SecureURLConstruction.assemblyAPIURL(path: "transcript")
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
                throw CloudASRError.invalidAPIKey(backend: "AssemblyAI")
            }
            components.queryItems = [URLQueryItem(name: "limit", value: "1")]
            guard let finalURL = components.url else {
                throw CloudASRError.invalidAPIKey(backend: "AssemblyAI")
            }
            
            var request = URLRequest(url: finalURL)
            request.httpMethod = "GET"
            request.setValue(apiKey, forHTTPHeaderField: "Authorization")
            
            let (_, response) = try await session.data(for: request)
            
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 401 || http.statusCode == 403 {
                    throw CloudASRError.invalidAPIKey(backend: "AssemblyAI")
                }
                if !(200 ..< 300).contains(http.statusCode) {
                    throw CloudASRError.httpError(statusCode: http.statusCode)
                }
            }
        }

        prepared = true
        Self.log.info("AssemblyAI backend prepared successfully")
    }

    func transcribe(
        _ samples: [Float],
        locale: Locale,
        previousContext: String? = nil
    ) async throws -> String {
        guard prepared else { throw TranscriptionBackendError.notPrepared }

        // 1. Encode audio as WAV
        let wavData = WAVEncoder.encode(samples: samples)

        // 2. Upload audio (uses secureAPIKey internally)
        let uploadURL = try await upload(wavData)

        // 3. Validate upload URL
        guard let components = URLComponents(url: uploadURL, resolvingAgainstBaseURL: false),
              components.scheme == "https",
              let host = components.host,
              host.hasSuffix(".assemblyai.com")
        else {
            throw CloudASRError.invalidUploadURL
        }

        // 4. Create transcript (uses secureAPIKey internally)
        let transcriptID = try await createTranscript(
            audioURL: uploadURL,
            locale: locale
        )

        // 5. Poll for completion (uses secureAPIKey internally)
        let text = try await pollTranscript(id: transcriptID)

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Private: Upload

    private func upload(_ data: Data) async throws -> URL {
        try await secureAPIKey.withSecureAccess { apiKey in
            // SEC-005 Fix: Use SecureURLConstruction to prevent URL injection
            let uploadURL = try SecureURLConstruction.assemblyAPIURL(path: "upload")
            
            var request = URLRequest(url: uploadURL)
            request.httpMethod = "POST"
            request.setValue(apiKey, forHTTPHeaderField: "Authorization")
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            request.httpBody = data

            return try await withTransientRetry { [session] in
                let (responseData, response) = try await session.data(for: request)
                try self.checkHTTPStatus(response)

                let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any]
                guard let urlString = json?["upload_url"] as? String,
                      let url = URL(string: urlString)
                else {
                    throw CloudASRError.invalidUploadURL
                }

                return url
            }
        }
    }

    // MARK: - Private: Create Transcript

    private func createTranscript(audioURL: URL, locale: Locale) async throws -> String {
        var body: [String: Any] = [
            "audio_url": audioURL.absoluteString,
            "speech_models": ["universal-3-pro", "universal-2"],
        ]

        // Language code from locale (e.g. "en", "pl", "de")
        let languageCode = locale.language.languageCode?.identifier
        if let languageCode, !languageCode.isEmpty {
            body["language_code"] = languageCode
        }

        if !customSpelling.isEmpty {
            body["custom_spelling"] = customSpelling
        }
        
        return try await secureAPIKey.withSecureAccess { apiKey in
            // SEC-006 Fix: Use SecureURLConstruction to prevent URL injection
            let transcriptURL = try SecureURLConstruction.assemblyAPIURL(path: "transcript")
            
            var request = URLRequest(url: transcriptURL)
            request.httpMethod = "POST"
            request.setValue(apiKey, forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            return try await withTransientRetry { [session] in
                let (responseData, response) = try await session.data(for: request)

                // Log diagnostic info for client errors before throwing
                if let http = response as? HTTPURLResponse, (400 ..< 500).contains(http.statusCode) {
                    let errorMessage = (try? JSONSerialization.jsonObject(with: responseData) as? [String: Any])?["error"] as? String
                    Self.log.error("Transcript creation failed (HTTP \(http.statusCode, privacy: .public)): \(errorMessage ?? "unknown", privacy: .public)")
                }

                try self.checkHTTPStatus(response)

                let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any]
                guard let id = json?["id"] as? String else {
                    throw CloudASRError.transcriptionFailed("Missing transcript ID in response.")
                }

                return id
            }
        }
    }

    // MARK: - Private: Poll

    private func pollTranscript(id: String) async throws -> String {
        // SEC-002 Fix: Use SecureURLConstruction to prevent URL injection
        let url = try SecureURLConstruction.pollURL(forTranscriptID: id)
        
        return try await secureAPIKey.withSecureAccess { apiKey in
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue(apiKey, forHTTPHeaderField: "Authorization")

            for _ in 0 ..< 120 {
                try Task.checkCancellation()
                try await Task.sleep(for: .milliseconds(500))

                let (data, response) = try await session.data(for: request)
                try checkHTTPStatus(response)

                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let status = json?["status"] as? String

                switch status {
                case "completed":
                    let text = json?["text"] as? String ?? ""
                    Self.log.info("Transcript \(id) completed")
                    return text
                case "error":
                    let errorMessage = json?["error"] as? String ?? "Unknown error"
                    Self.log.error("Transcript \(id) failed: \(errorMessage)")
                    throw CloudASRError.transcriptionFailed(errorMessage)
                default:
                    continue
                }
            }

            Self.log.error("Transcript \(id) timed out after 60s")
            throw CloudASRError.timeout
        }
    }

    // MARK: - Private: HTTP Status Check

    private func checkHTTPStatus(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse,
              !(200 ..< 300).contains(http.statusCode)
        else { return }
        throw CloudASRError.httpError(statusCode: http.statusCode)
    }

    // MARK: - Private: Custom Spelling Parser

    /// Parses vocabulary lines into AssemblyAI custom_spelling format.
    ///
    /// Input format (one entry per line):
    /// ```
    /// Preferred: alias1, alias2
    /// PlainTerm
    /// ```
    ///
    /// Lines with `:` produce `{"from": ["alias1", "alias2"], "to": "Preferred"}`.
    /// Lines without `:` are ignored (no alias mapping).
    private static func parseCustomSpelling(_ vocabulary: String) -> [[String: Any]] {
        vocabulary
            .split(separator: "\n")
            .compactMap { line -> [String: Any]? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.contains(":") else { return nil }

                let parts = trimmed.split(separator: ":", maxSplits: 1)
                guard parts.count == 2 else { return nil }

                let preferred = parts[0].trimmingCharacters(in: .whitespaces)
                let aliases = parts[1]
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }

                guard !preferred.isEmpty, !aliases.isEmpty else { return nil }

                return ["from": aliases, "to": preferred]
            }
    }
}
