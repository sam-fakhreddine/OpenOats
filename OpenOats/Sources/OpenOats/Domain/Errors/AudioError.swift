import Foundation

// MARK: - Audio Error

/// Errors that occur during audio capture and processing.
public enum AudioError: Error, Sendable, Equatable {
    /// Audio capture failed.
    /// - Parameters:
    ///   - device: The audio device.
    ///   - reason: Failure reason.
    case captureFailed(device: String, reason: String)
    
    /// Audio format is not supported.
    /// - Parameters:
    ///   - format: The unsupported format.
    ///   - sampleRate: The sample rate, if relevant.
    case formatUnsupported(format: String, sampleRate: Int?)
    
    /// Microphone permission denied.
    case permissionDenied
    
    /// Audio device not found.
    /// - Parameter device: The device identifier.
    case deviceNotFound(device: String)
    
    /// Audio hardware error.
    /// - Parameter code: The hardware error code.
    case hardwareError(code: Int)
    
    /// Audio session configuration failed.
    /// - Parameter reason: Configuration failure reason.
    case configurationFailed(reason: String)
    
    /// Audio buffer overflow.
    /// - Parameter maxSize: Maximum buffer size.
    case bufferOverflow(maxSize: Int)
    
    /// Audio encoding/decoding error.
    /// - Parameter codec: The codec that failed.
    case codecError(codec: String)
}

extension AudioError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .captureFailed(let device, let reason):
            return "Audio capture failed on '\(device)': \(reason)"
            
        case .formatUnsupported(let format, let sampleRate):
            let rate = sampleRate.map { " at \($0) Hz" } ?? ""
            return "Audio format '\(format)'\(rate) is not supported"
            
        case .permissionDenied:
            return "Microphone permission denied"
            
        case .deviceNotFound(let device):
            return "Audio device '\(device)' not found"
            
        case .hardwareError(let code):
            return "Audio hardware error (code: \(code))"
            
        case .configurationFailed(let reason):
            return "Audio configuration failed: \(reason)"
            
        case .bufferOverflow(let maxSize):
            return "Audio buffer overflow (max: \(maxSize) bytes)"
            
        case .codecError(let codec):
            return "Audio codec error with '\(codec)'"
        }
    }
}
