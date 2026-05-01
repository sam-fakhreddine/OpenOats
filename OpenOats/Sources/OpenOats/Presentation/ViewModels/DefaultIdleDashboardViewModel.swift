import Foundation
import SwiftUI

// MARK: - DefaultIdleDashboardViewModel

/// Default implementation of IdleDashboardViewModel for home screen
@MainActor
@Observable
final class DefaultIdleDashboardViewModel: IdleDashboardViewModel {
    let id: UUID
    
    // Loading and error state
    var isLoading: Bool = false
    var error: PresentationError? = nil
    
    // Calendar State
    var calendarAccessState: CalendarAccessState = .notDetermined
    var isCalendarIntegrationEnabled: Bool {
        didSet {
            if !isCalendarIntegrationEnabled {
                // Clear events when disabled
                upcomingEvents = []
                earlierTodayEvents = []
            } else {
                // Trigger refresh when enabled
                Task {
                    await refresh()
                }
            }
        }
    }
    var upcomingEvents: [CalendarEvent] = []
    var earlierTodayEvents: [CalendarEvent] = []
    var showsEarlierToday: Bool = false
    
    // Session History State
    var sessionHistory: [SessionIndex] = []
    var recentSessions: [SessionIndex] {
        Array(sessionHistory.prefix(5))
    }
    
    // Quick Actions State
    var canQuickStart: Bool {
        !hasActiveSession
    }
    var lastUsedBackend: BackendID? = nil
    
    // UI State
    var isCreateFolderSheetPresented: Bool = false
    var folderCreationEvent: CalendarEvent? = nil
    var newFolderPath: String = ""
    var newFolderColor: NotesFolderColor = .blue
    
    // Private state
    private var hasActiveSession: Bool = false
    private var shouldFail: Bool
    private var calendarEnabled: Bool
    private var savedEvents: [CalendarEvent] = []
    
    init(
        calendarEnabled: Bool = true,
        calendarAccessState: CalendarAccessState = .notDetermined,
        withHistory: Bool = false,
        withEvents: Bool = false,
        withFutureEvent: Bool = false,
        withMeetingURL: Bool = false,
        withEarlierTodayEvents: Bool = false,
        withActiveSession: Bool = false,
        shouldFail: Bool = false
    ) {
        self.id = UUID()
        self.calendarEnabled = calendarEnabled
        self.calendarAccessState = calendarEnabled ? calendarAccessState : .disabled
        self.isCalendarIntegrationEnabled = calendarEnabled
        self.shouldFail = shouldFail
        self.hasActiveSession = withActiveSession
        
        // Initialize with sample data if requested
        if withHistory {
            self.sessionHistory = Self.generateSampleSessionHistory()
        }
        
        if withEvents || withFutureEvent || withMeetingURL || withEarlierTodayEvents {
            let events = Self.generateSampleCalendarEvents(
                includeFuture: withFutureEvent || withEvents,
                includeMeetingURL: withMeetingURL,
                includeEarlierToday: withEarlierTodayEvents || withEvents
            )
            self.savedEvents = events
            self.upcomingEvents = events.filter { $0.endDate > Date() }
            self.earlierTodayEvents = events.filter { 
                Calendar.current.isDateInToday($0.startDate) && $0.endDate <= Date() 
            }
        }
        
        if withMeetingURL {
            self.lastUsedBackend = .mlxWhisper
        }
    }
    
    func clearError() {
        error = nil
    }
    
    func refresh() async {
        guard !isLoading else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        // Simulate failure if configured
        if shouldFail {
            error = PresentationError.sessionStartFailed(reason: "Refresh failed")
            isLoading = false
            return
        }
        
        // Clear events if calendar is disabled or denied
        if !isCalendarIntegrationEnabled || calendarAccessState == .denied {
            upcomingEvents = []
            earlierTodayEvents = []
            return
        }
        
        // Simulate calendar fetch
        if calendarAccessState == .authorized {
            upcomingEvents = savedEvents.filter { $0.endDate > Date() }
            earlierTodayEvents = savedEvents.filter { 
                Calendar.current.isDateInToday($0.startDate) && $0.endDate <= Date() 
            }
        }
        
        // Refresh session history
        if sessionHistory.isEmpty {
            sessionHistory = Self.generateSampleSessionHistory()
        }
        
        // Simulate async refresh
        try? await Task.sleep(for: .milliseconds(50))
    }
    
    func startRecording(for event: CalendarEvent) async throws -> SessionID {
        guard !shouldFail else {
            let failError = PresentationError.sessionStartFailed(reason: "Cannot start recording")
            error = failError
            throw failError
        }
        
        if hasActiveSession {
            throw PresentationError.sessionStartFailed(reason: "Another session is active")
        }
        
        // Create a new session for the event
        let sessionID = SessionID()
        lastUsedBackend = .mlxWhisper
        
        // Simulate recording start
        hasActiveSession = true
        
        return sessionID
    }
    
    func startQuickRecording() async throws -> SessionID {
        guard !shouldFail else {
            let failError = PresentationError.sessionStartFailed(reason: "Cannot start recording")
            error = failError
            throw failError
        }
        
        guard canQuickStart else {
            throw PresentationError.sessionStartFailed(reason: "Another session is active")
        }
        
        // Create a new quick session
        let sessionID = SessionID()
        lastUsedBackend = lastUsedBackend ?? .mlxWhisper
        
        // Simulate recording start
        hasActiveSession = true
        
        return sessionID
    }
    
    func openRelatedNotes(for event: CalendarEvent) {
        // Implementation would open notes view for the event
        // This is a no-op for the ViewModel, but would trigger UI navigation
        print("Open related notes for: \(event.title)")
    }
    
    func joinMeeting(for event: CalendarEvent) {
        guard let meetingURL = event.meetingURL else { return }
        
        // In a real implementation, this would open the meeting URL
        print("Join meeting: \(meetingURL)")
        
        #if os(macOS)
        NSWorkspace.shared.open(meetingURL)
        #endif
    }
    
    func requestCalendarAccess() async {
        // Simulate permission request
        switch calendarAccessState {
        case .notDetermined:
            // Simulate user granting permission
            calendarAccessState = .authorized
        case .denied:
            // Stay denied
            break
        default:
            break
        }
    }
    
    func createFolder(path: String, color: NotesFolderColor, for event: CalendarEvent) async throws {
        guard !shouldFail else {
            let failError = PresentationError.validationFailed(field: "folder", reason: "Create folder failed")
            error = failError
            throw failError
        }
        
        // Validate path depth (max 2 levels as per test requirement)
        let components = path.split(separator: "/")
        guard components.count <= 2 else {
            let failError = PresentationError.validationFailed(field: "folder", reason: "Path too deep (max 2 levels)")
            error = failError
            throw failError
        }
        
        guard !path.isEmpty else {
            let failError = PresentationError.validationFailed(field: "folder", reason: "Path cannot be empty")
            error = failError
            throw failError
        }
        
        // In a real implementation, this would create the folder
        // For now, just update the state
        newFolderPath = path
        newFolderColor = color
        
        // Close the sheet
        isCreateFolderSheetPresented = false
        folderCreationEvent = nil
    }
    
    func changeMeetingFolder(to folderPath: String?, for event: CalendarEvent, moveExisting: Bool) async throws {
        guard !shouldFail else {
            let failError = PresentationError.validationFailed(field: "folder", reason: "Change folder failed")
            error = failError
            throw failError
        }
        
        // In a real implementation, this would update the meeting family preferences
        // and optionally move existing sessions
        print("Changed meeting folder to: \(folderPath ?? "default") for: \(event.title), moveExisting: \(moveExisting)")
    }
    
    // MARK: - Private Methods
    
    private static func generateSampleSessionHistory() -> [SessionIndex] {
        let now = Date()
        let calendar = Calendar.current
        
        return [
            SessionIndex(
                id: "session_\(calendar.date(byAdding: .hour, value: -2, to: now)!.timeIntervalSince1970)",
                startedAt: calendar.date(byAdding: .hour, value: -2, to: now)!,
                endedAt: calendar.date(byAdding: .minute, value: -30, to: now),
                templateSnapshot: nil,
                title: "Weekly Team Standup",
                utteranceCount: 45,
                hasNotes: true,
                language: "en",
                meetingApp: "Zoom",
                engine: "mlx-whisper",
                tags: ["team", "weekly"],
                folderPath: "Work/Team",
                source: nil,
                meetingFamilyKey: "weekly-team-standup",
                transcriptIssue: nil,
                transcriptRecovery: nil
            ),
            SessionIndex(
                id: "session_\(calendar.date(byAdding: .day, value: -1, to: now)!.timeIntervalSince1970)",
                startedAt: calendar.date(byAdding: .day, value: -1, to: now)!,
                endedAt: calendar.date(byAdding: .day, value: -1, to: now)!.addingTimeInterval(3600),
                templateSnapshot: nil,
                title: "Product Planning",
                utteranceCount: 78,
                hasNotes: true,
                language: "en",
                meetingApp: "Microsoft Teams",
                engine: "whisperkit",
                tags: ["product", "planning"],
                folderPath: "Work/Product",
                source: nil,
                meetingFamilyKey: "product-planning",
                transcriptIssue: nil,
                transcriptRecovery: nil
            ),
            SessionIndex(
                id: "session_\(calendar.date(byAdding: .day, value: -3, to: now)!.timeIntervalSince1970)",
                startedAt: calendar.date(byAdding: .day, value: -3, to: now)!,
                endedAt: calendar.date(byAdding: .day, value: -3, to: now)!.addingTimeInterval(1800),
                templateSnapshot: nil,
                title: "1:1 with Manager",
                utteranceCount: 32,
                hasNotes: true,
                language: "en",
                meetingApp: "Zoom",
                engine: "mlx-whisper",
                tags: ["1:1", "manager"],
                folderPath: "Work/1:1s",
                source: nil,
                meetingFamilyKey: "1-1-with-manager",
                transcriptIssue: nil,
                transcriptRecovery: nil
            ),
            SessionIndex(
                id: "session_\(calendar.date(byAdding: .day, value: -5, to: now)!.timeIntervalSince1970)",
                startedAt: calendar.date(byAdding: .day, value: -5, to: now)!,
                endedAt: calendar.date(byAdding: .day, value: -5, to: now)!.addingTimeInterval(2700),
                templateSnapshot: nil,
                title: "Design Review",
                utteranceCount: 56,
                hasNotes: false,
                language: "en",
                meetingApp: nil,
                engine: "assemblyai",
                tags: ["design", "review"],
                folderPath: nil,
                source: nil,
                meetingFamilyKey: "design-review",
                transcriptIssue: nil,
                transcriptRecovery: nil
            ),
            SessionIndex(
                id: "session_\(calendar.date(byAdding: .day, value: -7, to: now)!.timeIntervalSince1970)",
                startedAt: calendar.date(byAdding: .day, value: -7, to: now)!,
                endedAt: calendar.date(byAdding: .day, value: -7, to: now)!.addingTimeInterval(3600),
                templateSnapshot: nil,
                title: "All Hands Meeting",
                utteranceCount: 120,
                hasNotes: true,
                language: "en",
                meetingApp: "Zoom",
                engine: "mlx-whisper",
                tags: ["all-hands", "company"],
                folderPath: "Work/Company",
                source: nil,
                meetingFamilyKey: "all-hands-meeting",
                transcriptIssue: nil,
                transcriptRecovery: nil
            )
        ]
    }
    
    private static func generateSampleCalendarEvents(
        includeFuture: Bool,
        includeMeetingURL: Bool,
        includeEarlierToday: Bool
    ) -> [CalendarEvent] {
        let now = Date()
        let calendar = Calendar.current
        var events: [CalendarEvent] = []
        
        if includeEarlierToday {
            // Add earlier today event
            events.append(CalendarEvent(
                id: "event-morning-standup",
                title: "Morning Standup",
                startDate: calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now)!,
                endDate: calendar.date(bySettingHour: 9, minute: 30, second: 0, of: now)!,
                externalIdentifier: "standup-series",
                calendarID: "work",
                calendarTitle: "Work",
                calendarColorHex: "#4285F4",
                organizer: "team-lead@company.com",
                participants: [
                    Participant(name: "Alice", email: "alice@company.com"),
                    Participant(name: "Bob", email: "bob@company.com")
                ],
                isOnlineMeeting: true,
                meetingURL: includeMeetingURL ? URL(string: "https://zoom.us/j/123456") : nil
            ))
        }
        
        if includeFuture {
            // Add upcoming events
            events.append(CalendarEvent(
                id: "event-1-1",
                title: "1:1 with Manager",
                startDate: calendar.date(byAdding: .hour, value: 1, to: now)!,
                endDate: calendar.date(byAdding: .hour, value: 2, to: now)!,
                externalIdentifier: "1-1-series",
                calendarID: "work",
                calendarTitle: "Work",
                calendarColorHex: "#4285F4",
                organizer: "manager@company.com",
                participants: [
                    Participant(name: "Manager", email: "manager@company.com")
                ],
                isOnlineMeeting: true,
                meetingURL: includeMeetingURL ? URL(string: "https://zoom.us/j/789012") : nil
            ))
            
            events.append(CalendarEvent(
                id: "event-planning",
                title: "Product Planning",
                startDate: calendar.date(byAdding: .hour, value: 3, to: now)!,
                endDate: calendar.date(byAdding: .hour, value: 5, to: now)!,
                externalIdentifier: "planning-series",
                calendarID: "work",
                calendarTitle: "Work",
                calendarColorHex: "#4285F4",
                organizer: "pm@company.com",
                participants: [
                    Participant(name: "Product Manager", email: "pm@company.com"),
                    Participant(name: "Engineer", email: "eng@company.com"),
                    Participant(name: "Designer", email: "design@company.com")
                ],
                isOnlineMeeting: false,
                meetingURL: nil
            ))
            
            events.append(CalendarEvent(
                id: "event-review",
                title: "Design Review",
                startDate: calendar.date(byAdding: .hour, value: 6, to: now)!,
                endDate: calendar.date(byAdding: .hour, value: 7, to: now)!,
                externalIdentifier: nil,
                calendarID: "work",
                calendarTitle: "Work",
                calendarColorHex: "#4285F4",
                organizer: "design@company.com",
                participants: [
                    Participant(name: "Designer", email: "design@company.com")
                ],
                isOnlineMeeting: true,
                meetingURL: includeMeetingURL ? URL(string: "https://teams.microsoft.com/l/meetup-join/abc123") : nil
            ))
        }
        
        return events.sorted { $0.startDate < $1.startDate }
    }
}
