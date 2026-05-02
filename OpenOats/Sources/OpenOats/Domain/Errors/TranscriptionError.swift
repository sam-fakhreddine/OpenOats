import Foundation

// MARK: - Transcription Error

/// Errors that can occur during the transcription process.
public enum TranscriptionError: Error, Sendable, Equatable {
    /// Backend failed to process audio.
    /// - Parameters:
    ///   - backend: The backend identifier.
    ///   - reason: Human-readable failure reason.
    ///   - recoverable: Whether the operation can be retried.
    case backendFailed(backend: String, reason: String, recoverable: Bool)
    
    /// Audio format is not supported by the backend.
    /// - Parameters:
    ///   - format: The unsupported format.
    ///   - supportedFormats: List of supported formats.
    case audioFormatUnsupported(format: String, supportedFormats: [String])
    
    /// Operation timed out.
    /// - Parameters:
    ///   - operation: The operation that timed out.
    ///   - duration: How long the operation ran before timing out.
    case timeout(operation: String, duration: Duration)
    
    /// Model required for transcription is not available.
    /// - Parameters:
    ///   - model: The model identifier.
    ///   - reason: Why the model is unavailable.
    case modelUnavailable(model: String, reason: String)
    
    /// Network-related error during transcription.
    /// - Parameter reason: The network error description.
    case networkFailure(reason: String)
    
    /// Rate limit exceeded.
    /// - Parameters:
    ///   - provider: The provider that rate-limited.
    ///   - retryAfter: When to retry the request.
    case rateLimited(provider: String, retryAfter: Date?)
    
    /// VAD manager was not initialized when required.
    case vadManagerNotInitialized
}

extension TranscriptionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .backendFailed(let backend, let reason, let recoverable):
            let recovery = recoverable ? " (recoverable)" : " (not recoverable)"
            return "Transcription backend '\(backend)' failed: \(reason)\(recovery)"
            
        case .audioFormatUnsupported(let format, let supported):
            return "Audio format '\(format)' is not supported. Supported: \(supported.joined(separator: ", "))"
            
        case .timeout(let operation, let duration):
            return "Operation '\(operation)' timed out after \(duration) seconds"
            
        case .modelUnavailable(let model, let reason):
            return "Model '\(model)' is unavailable: \(reason)"
            
        case .networkFailure(let reason):
            return "Network failure: \(reason)"
            
        case .rateLimited(let provider, let retryAfter):
            let retry = retryAfter.map { " - retry after \($0)" } ?? ""
            return "Rate limited by '\(provider)'\(retry)"
            
        case .vadManagerNotInitialized:
            return "VAD manager was not initialized"
        }
    }
}
