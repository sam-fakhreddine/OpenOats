import Foundation

/// REST client for Voyage AI embeddings and reranking APIs.
/// Uses secure patterns: SecureString for API keys and SecureURLConstruction for URLs.
@available(macOS 15.0, *)
actor VoyageClient {
    private let baseURL = "https://api.voyageai.com/v1"

    enum VoyageError: Error, LocalizedError {
        case httpError(Int, String)
        case decodingError
        case emptyResponse
        case invalidURL
        case pathTraversalDetected

        var errorDescription: String? {
            switch self {
            case .httpError(let code, let msg): "Voyage AI error (HTTP \(code)): \(msg)"
            case .decodingError: "Failed to decode Voyage AI response"
            case .emptyResponse: "Empty response from Voyage AI"
            case .invalidURL: "Failed to construct valid URL"
            case .pathTraversalDetected: "Path traversal detected in request"
            }
        }
    }

    // MARK: - Embeddings

    /// Fetches embeddings for the provided texts using secure API patterns.
    ///
    /// - Parameters:
    ///   - apiKey: The API key as a SecureString (never store as plain String)
    ///   - texts: Texts to embed
    ///   - inputType: Type of input (e.g., "document", "query")
    ///   - model: Model name
    ///   - dimensions: Output dimensions
    /// - Returns: Array of embedding vectors
    func embed(
        apiKey: SecureString,
        texts: [String],
        inputType: String,
        model: String = "voyage-4-lite",
        dimensions: Int = 256
    ) async throws -> [[Float]] {
        let body = EmbedRequest(
            input: texts,
            model: model,
            input_type: inputType,
            output_dimension: dimensions
        )

        // Use withSecureAccess to temporarily access the API key
        let data = try await apiKey.withSecureAccess { key in
            try await self.post(
                path: "/embeddings",
                apiKey: key,
                body: body
            )
        }

        let response = try JSONDecoder().decode(EmbedResponse.self, from: data)
        guard !response.data.isEmpty else { throw VoyageError.emptyResponse }

        // Sort by index to maintain order
        return response.data
            .sorted { $0.index < $1.index }
            .map { $0.embedding }
    }

    /// Fetches embeddings using a plain String API key (for backwards compatibility).
    /// - Warning: Prefer the SecureString variant for production code.
    func embed(
        apiKey: String,
        texts: [String],
        inputType: String,
        model: String = "voyage-4-lite",
        dimensions: Int = 256
    ) async throws -> [[Float]] {
        let secureKey = SecureString(apiKey)
        return try await embed(
            apiKey: secureKey,
            texts: texts,
            inputType: inputType,
            model: model,
            dimensions: dimensions
        )
    }

    // MARK: - Reranking

    /// Reranks documents using secure API patterns.
    ///
    /// - Parameters:
    ///   - apiKey: The API key as a SecureString
    ///   - query: The query string
    ///   - documents: Documents to rerank
    ///   - topN: Number of top results to return
    ///   - model: Reranking model name
    /// - Returns: Array of (index, score) tuples
    func rerank(
        apiKey: SecureString,
        query: String,
        documents: [String],
        topN: Int = 5,
        model: String = "rerank-2.5-lite"
    ) async throws -> [(index: Int, score: Double)] {
        let body = RerankRequest(
            query: query,
            documents: documents,
            model: model,
            top_k: topN
        )

        let data = try await apiKey.withSecureAccess { key in
            try await self.post(
                path: "/rerank",
                apiKey: key,
                body: body
            )
        }

        let response = try JSONDecoder().decode(RerankResponse.self, from: data)
        return response.data.map { (index: $0.index, score: $0.relevance_score) }
    }

    /// Reranks documents using a plain String API key (for backwards compatibility).
    /// - Warning: Prefer the SecureString variant for production code.
    func rerank(
        apiKey: String,
        query: String,
        documents: [String],
        topN: Int = 5,
        model: String = "rerank-2.5-lite"
    ) async throws -> [(index: Int, score: Double)] {
        let secureKey = SecureString(apiKey)
        return try await rerank(
            apiKey: secureKey,
            query: query,
            documents: documents,
            topN: topN,
            model: model
        )
    }

    // MARK: - HTTP Helpers

    nonisolated static func describeHTTPError(statusCode: Int, data: Data) -> (message: String, retryable: Bool) {
        let detail = extractErrorDetail(from: data)
        let normalized = detail?.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = normalized?.lowercased() ?? ""

        if statusCode == 429 {
            if lowercased.contains("payment method") || lowercased.contains("billing") || lowercased.contains("balance") {
                return ("Add a payment method in Voyage AI billing to enable knowledge base indexing.", false)
            }
            return ("Voyage AI is rate limiting requests. Try again in a moment.", true)
        }

        if statusCode == 401 || statusCode == 403 {
            return ("Check your Voyage AI API key and account access.", false)
        }

        if let normalized, !normalized.isEmpty {
            return (normalized, false)
        }

        return ("Unknown error", false)
    }

    /// Performs a POST request with secure URL construction.
    ///
    /// Uses SecureURLConstruction to prevent path traversal attacks.
    private func post<T: Encodable>(
        path: String,
        apiKey: String,
        body: T,
        retryOn429: Bool = true
    ) async throws -> Data {
        // SEC-001: Use SecureURLConstruction to prevent URL injection
        let result = SecureURLConstruction.build(
            baseURL: baseURL,
            path: path
        )
        
        let url: URL
        switch result {
        case .success(let safeURL):
            url = safeURL
        case .failure(let error):
            if case SecureURLConstruction.Error.pathTraversalDetected = error {
                throw VoyageError.pathTraversalDetected
            } else {
                throw VoyageError.invalidURL
            }
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw VoyageError.httpError(-1, "No HTTP response")
        }

        let errorInfo = Self.describeHTTPError(statusCode: http.statusCode, data: data)

        if http.statusCode == 429, retryOn429, errorInfo.retryable {
            try await Task.sleep(for: .seconds(20))
            return try await post(path: path, apiKey: apiKey, body: body, retryOn429: false)
        }

        guard (200...299).contains(http.statusCode) else {
            throw VoyageError.httpError(http.statusCode, errorInfo.message)
        }

        return data
    }

    private nonisolated static func extractErrorDetail(from data: Data) -> String? {
        if let response = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
            return response.detail ?? response.message ?? response.error
        }

        return String(data: data, encoding: .utf8)
    }

    // MARK: - Request/Response Types

    private struct EmbedRequest: Encodable {
        let input: [String]
        let model: String
        let input_type: String
        let output_dimension: Int
    }

    private struct EmbedResponse: Decodable {
        let data: [EmbeddingData]

        struct EmbeddingData: Decodable {
            let index: Int
            let embedding: [Float]
        }
    }

    private struct RerankRequest: Encodable {
        let query: String
        let documents: [String]
        let model: String
        let top_k: Int
    }

    private struct RerankResponse: Decodable {
        let data: [RerankResult]

        struct RerankResult: Decodable {
            let index: Int
            let relevance_score: Double
        }
    }

    private struct APIErrorResponse: Decodable {
        let detail: String?
        let message: String?
        let error: String?
    }
}
