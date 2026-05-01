import Foundation

// MARK: - Storage Error

/// Errors that can occur during data persistence operations.
public enum StorageError: Error, Sendable, Equatable {
    /// Failed to write data to storage.
    /// - Parameters:
    ///   - path: The target path.
    ///   - underlying: The underlying error, if any.
    case writeFailed(path: String, underlying: Error?)
    
    /// Failed to read data from storage.
    /// - Parameters:
    ///   - path: The source path.
    ///   - underlying: The underlying error, if any.
    case readFailed(path: String, underlying: Error?)
    
    /// Data corruption detected.
    /// - Parameters:
    ///   - entity: The entity type.
    ///   - id: The entity identifier.
    case corruptionDetected(entity: String, id: String)
    
    /// Entity not found.
    /// - Parameters:
    ///   - entity: The entity type.
    ///   - id: The entity identifier.
    case notFound(entity: String, id: String)
    
    /// Migration failed.
    /// - Parameters:
    ///   - fromVersion: Source schema version.
    ///   - toVersion: Target schema version.
    ///   - reason: Failure reason.
    case migrationFailed(fromVersion: Int, toVersion: Int, reason: String)
    
    /// Storage quota exceeded.
    /// - Parameter available: Bytes available, if known.
    case quotaExceeded(available: Int64?)
    
    /// Invalid path or file name.
    /// - Parameter path: The invalid path.
    case invalidPath(path: String)
}

extension StorageError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .writeFailed(let path, _):
            return "Failed to write to '\(path)'"
            
        case .readFailed(let path, _):
            return "Failed to read from '\(path)'"
            
        case .corruptionDetected(let entity, let id):
            return "Data corruption detected in \(entity) with ID '\(id)'"
            
        case .notFound(let entity, let id):
            return "\(entity) with ID '\(id)' not found"
            
        case .migrationFailed(let from, let to, let reason):
            return "Migration from version \(from) to \(to) failed: \(reason)"
            
        case .quotaExceeded(let available):
            let space = available.map { " (\($0) bytes available)" } ?? ""
            return "Storage quota exceeded\(space)"
            
        case .invalidPath(let path):
            return "Invalid path: '\(path)'"
        }
    }
}

// MARK: - Equatable Conformance for Error Types with Associated Values

extension StorageError {
    public static func == (lhs: StorageError, rhs: StorageError) -> Bool {
        switch (lhs, rhs) {
        case (.writeFailed(let lPath, _), .writeFailed(let rPath, _)):
            return lPath == rPath
        case (.readFailed(let lPath, _), .readFailed(let rPath, _)):
            return lPath == rPath
        case (.corruptionDetected(let lEntity, let lId), .corruptionDetected(let rEntity, let rId)):
            return lEntity == rEntity && lId == rId
        case (.notFound(let lEntity, let lId), .notFound(let rEntity, let rId)):
            return lEntity == rEntity && lId == rId
        case (.migrationFailed(let lFrom, let lTo, let lReason), .migrationFailed(let rFrom, let rTo, let rReason)):
            return lFrom == rFrom && lTo == rTo && lReason == rReason
        case (.quotaExceeded(let lAvailable), .quotaExceeded(let rAvailable)):
            return lAvailable == rAvailable
        case (.invalidPath(let lPath), .invalidPath(let rPath)):
            return lPath == rPath
        default:
            return false
        }
    }
}
