import Foundation

// MARK: - Session Status

/// Represents the current state of a recording session.
public enum SessionStatus: String, Sendable, Equatable, Hashable, Codable {
    /// Session is actively recording.
    case active
    
    /// Session has been stopped and is finalizing.
    case finalizing
    
    /// Session has completed successfully.
    case completed
    
    /// Session failed during recording or processing.
    case failed
    
    /// Session was cancelled by the user.
    case cancelled
}

// MARK: - Session Entity

/// Represents an individual recording session within a meeting.
/// A session captures audio from a continuous recording period.
public struct Session: Sendable, Equatable, Hashable, Codable {
    /// Unique identifier for this session.
    public let id: SessionID
    
    /// ID of the parent meeting.
    public let meetingID: MeetingID
    
    /// When recording started.
    public let startTime: Date
    
    /// When recording ended, if it has concluded.
    public let endTime: Date?
    
    /// Current status of the session.
    public let status: SessionStatus
    
    /// ID of the backend used for transcription, if any.
    public let backendID: BackendID?
    
    /// Creates a new Session instance.
    /// - Parameters:
    ///   - id: Unique identifier for this session.
    ///   - meetingID: ID of the parent meeting.
    ///   - startTime: When recording started.
    ///   - endTime: When recording ended, if concluded.
    ///   - status: Current status of the session.
    ///   - backendID: ID of the transcription backend used.
    public init(
        id: SessionID,
        meetingID: MeetingID,
        startTime: Date,
        endTime: Date? = nil,
        status: SessionStatus = .active,
        backendID: BackendID? = nil
    ) {
        self.id = id
        self.meetingID = meetingID
        self.startTime = startTime
        self.endTime = endTime
        self.status = status
        self.backendID = backendID
    }
    
    /// Returns the duration of the session in seconds.
    /// Returns nil if the session has not ended yet.
    public var duration: TimeInterval? {
        guard let endTime = endTime else { return nil }
        return endTime.timeIntervalSince(startTime)
    }
    
    /// Returns a new Session with the specified status.
    /// - Parameter status: The new status to set.
    /// - Returns: A new Session with the updated status.
    public func withStatus(_ status: SessionStatus) -> Session {
        Session(
            id: id,
            meetingID: meetingID,
            startTime: startTime,
            endTime: endTime,
            status: status,
            backendID: backendID
        )
    }
    
    /// Returns a new Session with the specified end time.
    /// - Parameter endTime: The time recording ended.
    /// - Returns: A new Session with the end time set.
    public func withEndedAt(_ endTime: Date) -> Session {
        Session(
            id: id,
            meetingID: meetingID,
            startTime: startTime,
            endTime: endTime,
            status: status,
            backendID: backendID
        )
    }
}
