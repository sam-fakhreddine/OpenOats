import Foundation
import os

// MARK: - ElevenLabs Scribe Backend

/// Cloud transcription backend using the ElevenLabs Scribe v2 REST API.
/// 
/// Security features:
/// - SecureString for API key storage (XOR obfuscation, zero-on-deinit)
/// - SecureURLConstruction for safe URL building (no force unwraps)
/// - Path traversal protection on all URL paths
///
/// @unchecked Sendable: session and prepared are written once in prepare() before any transcribe() calls.
@available(macOS 15.0, *)
final class ElevenLabsScribeBackend: TranscriptionBackend, @unchecked Sendable {
    let displayName = "ElevenLabs Scribe"

    /// API key stored as SecureString (never plain String)
    private let apiKey: SecureString
    private let keyterms: [String]
    private let removeFillerWords: Bool
    private let session: URLSession
    private var prepared = false

    private static let log = Logger(subsystem: "com.openoats.app", category: "ElevenLabsScribe")

    // MARK: - Init

    /// Creates a new ElevenLabs Scribe backend with secure API key storage.
    ///
    /// - Parameters:
    ///   - apiKey: API key as a SecureString (preferred) or plain String
    ///   - customVocabulary: Custom vocabulary for transcription
    ///   - removeFillerWords: Whether to filter filler words
    init(apiKey: SecureString, customVocabulary: String = "", removeFillerWords: Bool = false) {
        self.apiKey = apiKey
        self.keyterms = Self.parseKeyterms(customVocabulary)
        self.removeFillerWords = removeFillerWords
        self.session = URLSession(configuration: .ephemeral)
    }

    /// Creates a new ElevenLabs Scribe backend with plain string API key.
    /// - Warning: Prefer the SecureString variant for production code.
    convenience init(apiKey: String, customVocabulary: String = "", removeFillerWords: Bool = false) {
        let secureKey = SecureString(apiKey)
        self.init(apiKey: secureKey, customVocabulary: customVocabulary, removeFillerWords: removeFillerWords)
    }

    // MARK: - TranscriptionBackend

    func checkStatus() -> BackendStatus {
        .ready
    }

    func prepare(
        onStatus: @Sendable (String) -> Void,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        // Validate API key is not empty using secure access
        let isEmpty = apiKey.withSecureAccess { $0.isEmpty }
        guard !isEmpty else {
            throw CloudASRError.invalidAPIKey(backend: "ElevenLabs")
        }

        onStatus("Validating ElevenLabs API key...")

        // Validate using /v1/voices — universally accessible with any valid key,
        // unlike /v1/user which requires elevated account permissions.
        // SEC-002: Use SecureURLConstruction with Result type (no force unwrap)
        let urlResult = Self.secureElevenLabsURL(path: "/v1/voices")
        
        let voicesURL: URL
        switch urlResult {
        case .success(let url):
            voicesURL = url
        case .failure:
            throw CloudASRError.httpError(statusCode: 500)
        }
        
        var request = URLRequest(url: voicesURL)
        request.httpMethod = "GET"
        
        // SEC-003: Use withSecureAccess to set API key in header
        apiKey.withSecureAccess { key in
            request.setValue(key, forHTTPHeaderField: "xi-api-key")
        }

        let (_, response) = try await session.data(for: request)

        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw CloudASRError.invalidAPIKey(backend: "ElevenLabs")
            }
            if !(200 ..< 300).contains(http.statusCode) {
                throw CloudASRError.httpError(statusCode: http.statusCode)
            }
        }

        prepared = true
        Self.log.info("ElevenLabs Scribe backend prepared successfully")
    }

    func transcribe(
        _ samples: [Float],
        locale: Locale,
        previousContext: String? = nil
    ) async throws -> String {
        guard prepared else { throw TranscriptionBackendError.notPrepared }

        // 1. Encode audio as WAV
        let wavData = WAVEncoder.encode(samples: samples)

        // 2. Build multipart/form-data body
        let boundary = UUID().uuidString
        let languageCode = locale.language.languageCode?.identifier ?? ""
        let body = Self.buildMultipartBody(
            boundary: boundary,
            wavData: wavData,
            languageCode: languageCode,
            keyterms: keyterms,
            removeFillerWords: removeFillerWords
        )

        // 3. POST to speech-to-text endpoint
        try Task.checkCancellation()

        // SEC-004: Use SecureURLConstruction with Result type
        let urlResult = Self.secureElevenLabsURL(path: "/v1/speech-to-text")
        
        let sttURL: URL
        switch urlResult {
        case .success(let url):
            sttURL = url
        case .failure:
            throw CloudASRError.httpError(statusCode: 500)
        }
        
        var request = URLRequest(url: sttURL)
        request.httpMethod = "POST"
        
        // SEC-005: Use withSecureAccess to set API key
        apiKey.withSecureAccess { key in
            request.setValue(key, forHTTPHeaderField: "xi-api-key")
        }
        
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 30

        let text: String = try await withTransientRetry { [session] in
            let (responseData, response) = try await session.data(for: request)

            if let http = response as? HTTPURLResponse {
                if http.statusCode == 401 || http.statusCode == 403 {
                    throw CloudASRError.invalidAPIKey(backend: "ElevenLabs")
                }
                if !(200 ..< 300).contains(http.statusCode) {
                    let errorBody = String(data: Data(responseData.prefix(2048)), encoding: .utf8) ?? "<non-utf8 body>"
                    Self.log.error("ElevenLabs Scribe request failed: status \(http.statusCode, privacy: .public), body: \(errorBody, privacy: .private)")
                    throw CloudASRError.httpError(statusCode: http.statusCode)
                }
            }

            let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any]
            guard let text = json?["text"] as? String else {
                throw CloudASRError.transcriptionFailed("Missing text field in response.")
            }
            return text
        }

        Self.log.info("ElevenLabs Scribe transcription completed")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Multipart Body Builder (internal for tests)

    /// Builds the multipart/form-data body posted to /v1/speech-to-text.
    ///
    /// `keyterms` are emitted as one multipart part per term, matching the
    /// ElevenLabs JS SDK and the Speech-to-Text API reference. Sending a single
    /// field with a JSON-array string as the value causes the server to validate
    /// the whole literal as one keyterm, which fails with
    /// `invalid_keyword` / "Some keyword contains invalid characters".
    static func buildMultipartBody(
        boundary: String,
        wavData: Data,
        languageCode: String,
        keyterms: [String],
        removeFillerWords: Bool
    ) -> Data {
        var body = Data()

        body.appendMultipart(boundary: boundary, name: "model_id", value: "scribe_v2")

        if !languageCode.isEmpty {
            body.appendMultipart(boundary: boundary, name: "language_code", value: languageCode)
        }

        body.appendMultipart(
            boundary: boundary,
            name: "file",
            filename: "audio.wav",
            contentType: "audio/wav",
            data: wavData
        )

        for keyterm in keyterms {
            body.appendMultipart(boundary: boundary, name: "keyterms", value: keyterm)
        }

        if removeFillerWords {
            body.appendMultipart(boundary: boundary, name: "no_verbatim", value: "true")
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }

    // MARK: - Secure URL Construction
    
    /// Constructs a secure ElevenLabs API URL with path validation.
    ///
    /// - Parameter path: API path (e.g., "/v1/voices", "/v1/speech-to-text")
    /// - Returns: Result containing safe URL or construction error
    /// - Security: Uses SecureURLConstruction (no force unwraps, path traversal protection)
    private static func secureElevenLabsURL(path: String) -> Result<URL, SecureURLConstruction.Error> {
        SecureURLConstruction.elevenLabsAPIURL(path: path)
    }

    // MARK: - Private: Keyterms Parser

    /// Parses vocabulary lines into a flat array of keyterm strings.
    ///
    /// Input format (one entry per line):
    /// ```
    /// Preferred: alias1, alias2
    /// PlainTerm
    /// ```
    ///
    /// Lines with `:` use the preferred term (before the colon) only.
    /// Plain lines use the term as-is.
    /// Max 1000 terms; terms longer than 50 chars are truncated.
    private static func parseKeyterms(_ vocabulary: String) -> [String] {
        let lines = vocabulary.split(separator: "\n", omittingEmptySubsequences: true)
        var result: [String] = []

        for line in lines {
            guard result.count < 1000 else { break }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let term: String
            if trimmed.contains(":") {
                let parts = trimmed.split(separator: ":", maxSplits: 1)
                guard parts.count >= 1 else { continue }
                let preferred = parts[0].trimmingCharacters(in: .whitespaces)
                guard !preferred.isEmpty else { continue }
                term = preferred
            } else {
                term = trimmed
            }

            let finalTerm = term.count > 50 ? String(term.prefix(50)) : term
            result.append(finalTerm)
        }

        return result
    }
}

// MARK: - Multipart Form Data Helpers

private extension Data {
    mutating func appendMultipart(boundary: String, name: String, value: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n".data(using: .utf8)!)
        append("\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }

    mutating func appendMultipart(
        boundary: String,
        name: String,
        filename: String,
        contentType: String,
        data: Data
    ) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(contentType)\r\n".data(using: .utf8)!)
        append("\r\n".data(using: .utf8)!)
        append(data)
        append("\r\n".data(using: .utf8)!)
    }
}
