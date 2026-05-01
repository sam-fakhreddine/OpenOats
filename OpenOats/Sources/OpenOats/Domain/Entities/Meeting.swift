import Foundation

// MARK: - Meeting Entity

/// Root aggregate representing a meeting session.
/// Contains all sessions that belong to a logical meeting.
public struct Meeting: Sendable, Equatable, Hashable, Codable {
    /// Unique identifier for this meeting.
    public let id: MeetingID
    
    /// Title or subject of the meeting.
    public let title: String
    
    /// When the meeting started.
    public let startTime: Date
    
    /// When the meeting ended, if it has concluded.
    public let endTime: Date?
    
    /// IDs of all recording sessions within this meeting.
    public let sessionIDs: [SessionID]
    
    /// Creates a new Meeting instance.
    /// - Parameters:
    ///   - id: Unique identifier for this meeting.
    ///   - title: Title or subject of the meeting.
    ///   - startTime: When the meeting started.
    ///   - endTime: When the meeting ended, if concluded.
    ///   - sessionIDs: IDs of recording sessions within this meeting.
    public init(
        id: MeetingID,
        title: String,
        startTime: Date,
        endTime: Date? = nil,
        sessionIDs: [SessionID] = []
    ) {
        self.id = id
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.sessionIDs = sessionIDs
    }
    
    /// Returns the duration of the meeting in seconds.
    /// Returns nil if the meeting has not ended yet.
    public var duration: TimeInterval? {
        guard let endTime = endTime else { return nil }
        return endTime.timeIntervalSince(startTime)
    }
    
    /// Returns a new Meeting with an additional session ID.
    /// - Parameter sessionID: The session ID to add.
    /// - Returns: A new Meeting with the session ID appended.
    public func withSessionID(_ sessionID: SessionID) -> Meeting {
        Meeting(
            id: id,
            title: title,
            startTime: startTime,
            endTime: endTime,
            sessionIDs: sessionIDs + [sessionID]
        )
    }
    
    /// Returns a new Meeting with the specified end time.
    /// - Parameter endTime: The time the meeting ended.
    /// - Returns: A new Meeting with the end time set.
    public func withEndedAt(_ endTime: Date) -> Meeting {
        Meeting(
            id: id,
            title: title,
            startTime: startTime,
            endTime: endTime,
            sessionIDs: sessionIDs
        )
    }
}
