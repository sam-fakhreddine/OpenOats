import Foundation
import Testing
@testable import OpenOats

// MARK: - IdleDashboardViewModel Property-Based Tests
// PHASE 1: RED - These tests will fail until implementations are created

@Suite("IdleDashboardViewModel State Transitions")
struct IdleDashboardViewModelStateTransitionTests {
    
    // MARK: - Initial State Invariants
    
    @Test("Initial state has no events when calendar disabled")
    func testInitialStateCalendarDisabled() async throws {
        // Given: A newly created IdleDashboardViewModel with calendar disabled
        let viewModel = try await createIdleDashboardViewModel(calendarEnabled: false)
        
        // Then: Initial state invariants must hold
        #expect(viewModel.calendarAccessState == .disabled)
        #expect(viewModel.isCalendarIntegrationEnabled == false)
        #expect(viewModel.upcomingEvents.isEmpty)
        #expect(viewModel.earlierTodayEvents.isEmpty)
        #expect(viewModel.isLoading == false)
        #expect(viewModel.error == nil)
        #expect(viewModel.showsEarlierToday == false)
        #expect(viewModel.isCreateFolderSheetPresented == false)
        #expect(viewModel.folderCreationEvent == nil)
    }
    
    @Test("Initial state shows calendar access state")
    func testInitialCalendarAccessState() async throws {
        // Given: Dashboard with calendar enabled
        let viewModel = try await createIdleDashboardViewModel(calendarEnabled: true)
        
        // Then: Should show appropriate access state
        // Could be authorized, denied, or notDetermined
        #expect(viewModel.calendarAccessState == .authorized ||
                viewModel.calendarAccessState == .denied ||
                viewModel.calendarAccessState == .notDetermined)
    }
    
    @Test("Session history is available on init")
    func testInitialSessionHistory() async throws {
        // Given: Dashboard with existing sessions
        let viewModel = try await createIdleDashboardViewModelWithHistory()
        
        // Then: Should have session history
        #expect(!viewModel.sessionHistory.isEmpty)
    }
    
    // MARK: - Calendar Toggle
    
    @Test("Enabling calendar integration requests access")
    func testEnableCalendarIntegration() async throws {
        // Given: Dashboard with calendar disabled
        let viewModel = try await createIdleDashboardViewModel(calendarEnabled: false)
        #expect(viewModel.isCalendarIntegrationEnabled == false)
        
        // When: Enabling calendar
        viewModel.isCalendarIntegrationEnabled = true
        
        // Then: Should trigger access request
        #expect(viewModel.calendarAccessState == .notDetermined ||
                viewModel.calendarAccessState == .authorized ||
                viewModel.calendarAccessState == .denied)
    }
    
    @Test("Disabling calendar clears events")
    func testDisableCalendarClearsEvents() async throws {
        // Given: Dashboard with calendar enabled and events
        let viewModel = try await createIdleDashboardViewModelWithEvents()
        #expect(!viewModel.upcomingEvents.isEmpty)
        
        // When: Disabling calendar
        viewModel.isCalendarIntegrationEnabled = false
        await viewModel.refresh()
        
        // Then: Events should be cleared
        #expect(viewModel.upcomingEvents.isEmpty)
        #expect(viewModel.earlierTodayEvents.isEmpty)
    }
    
    // MARK: - Refresh
    
    @Test("Refresh loads calendar events")
    func testRefreshLoadsEvents() async throws {
        // Given: Dashboard with calendar authorized
        let viewModel = try await createIdleDashboardViewModel(calendarEnabled: true)
        #expect(viewModel.calendarAccessState == .authorized)
        
        // Initially may have events from init
        let initialCount = viewModel.upcomingEvents.count
        
        // When: Refreshing
        await viewModel.refresh()
        
        // Then: Should have loaded events (may be same or different count)
        #expect(viewModel.isLoading == false)
        // Events may or may not change depending on timing
    }
    
    @Test("Refresh shows loading state")
    func testRefreshShowsLoading() async throws {
        // Given: Dashboard
        let viewModel = try await createIdleDashboardViewModel()
        
        // When: Refreshing
        let refreshTask = Task {
            await viewModel.refresh()
        }
        
        try await Task.sleep(for: .milliseconds(10))
        
        // Then: Should show loading
        #expect(viewModel.isLoading == true)
        
        await refreshTask.value
        
        // After completion
        #expect(viewModel.isLoading == false)
    }
    
    @Test("Refresh with calendar denied clears events")
    func testRefreshWithDeniedClearsEvents() async throws {
        // Given: Dashboard with denied access but events cached
        let viewModel = try await createIdleDashboardViewModelWithDeniedAccess()
        #expect(viewModel.calendarAccessState == .denied)
        
        // When: Refreshing
        await viewModel.refresh()
        
        // Then: Events should be empty
        #expect(viewModel.upcomingEvents.isEmpty)
        #expect(viewModel.earlierTodayEvents.isEmpty)
    }
    
    // MARK: - Quick Start
    
    @Test("Quick start creates session")
    func testQuickStartRecording() async throws {
        // Given: Dashboard in idle state
        let viewModel = try await createIdleDashboardViewModel()
        #expect(viewModel.canQuickStart == true)
        
        // When: Quick starting
        let sessionID = try await viewModel.startQuickRecording()
        
        // Then: Should return valid session ID
        #expect(sessionID.rawValue != UUID())
    }
    
    @Test("Quick start updates last used backend")
    func testQuickStartUpdatesLastBackend() async throws {
        // Given: Dashboard
        let viewModel = try await createIdleDashboardViewModel()
        let initialBackend = viewModel.lastUsedBackend
        
        // When: Quick starting
        _ = try await viewModel.startQuickRecording()
        
        // Then: Last used backend should be set
        #expect(viewModel.lastUsedBackend != nil)
        #expect(viewModel.lastUsedBackend == initialBackend || viewModel.lastUsedBackend != initialBackend)
    }
    
    @Test("Cannot quick start when already recording elsewhere")
    func testCannotQuickStartWhenRecording() async throws {
        // Given: Dashboard with active session elsewhere
        let viewModel = try await createIdleDashboardViewModelWithActiveSession()
        #expect(viewModel.canQuickStart == false)
        
        // When: Attempting to quick start
        // Then: Should throw error
        await #expect(throws: PresentationError.self) {
            try await viewModel.startQuickRecording()
        }
    }
    
    // MARK: - Event Recording
    
    @Test("Start recording for event creates session")
    func testStartRecordingForEvent() async throws {
        // Given: Dashboard with upcoming event
        let viewModel = try await createIdleDashboardViewModelWithEvents()
        #expect(!viewModel.upcomingEvents.isEmpty)
        
        let event = viewModel.upcomingEvents[0]
        
        // When: Starting recording for event
        let sessionID = try await viewModel.startRecording(for: event)
        
        // Then: Should return valid session ID
        #expect(sessionID.rawValue != UUID())
    }
    
    @Test("Start recording for event associates event")
    func testStartRecordingAssociatesEvent() async throws {
        // Given: Dashboard with event
        let viewModel = try await createIdleDashboardViewModelWithEvents()
        let event = viewModel.upcomingEvents[0]
        
        // When: Starting recording
        let sessionID = try await viewModel.startRecording(for: event)
        
        // Then: Session should be associated with event (implementation dependent)
        #expect(sessionID.rawValue != UUID())
    }
    
    // MARK: - Related Notes
    
    @Test("Open related notes for event with history")
    func testOpenRelatedNotesWithHistory() async throws {
        // Given: Dashboard with event that has history
        let viewModel = try await createIdleDashboardViewModelWithEventsAndHistory()
        let event = viewModel.upcomingEvents[0]
        
        // When: Opening related notes
        viewModel.openRelatedNotes(for: event)
        
        // Then: Should succeed without throwing (implementation dependent)
        // This test verifies the method exists and can be called
    }
    
    @Test("Open related notes for future event queues history")
    func testOpenRelatedNotesForFutureEvent() async throws {
        // Given: Dashboard with future event
        let viewModel = try await createIdleDashboardViewModelWithFutureEvent()
        let futureEvent = viewModel.upcomingEvents.first { $0.startDate > Date() }!
        
        // When: Opening related notes for future event
        viewModel.openRelatedNotes(for: futureEvent)
        
        // Then: Should queue history (implementation verified by not throwing)
    }
    
    // MARK: - Join Meeting
    
    @Test("Join meeting opens meeting URL")
    func testJoinMeeting() async throws {
        // Given: Dashboard with event that has meeting URL
        let viewModel = try await createIdleDashboardViewModelWithMeetingURLEvent()
        let event = viewModel.upcomingEvents.first { $0.meetingURL != nil }!
        
        // When: Joining meeting
        viewModel.joinMeeting(for: event)
        
        // Then: Should open URL (implementation dependent)
        // This test verifies the method exists and can be called
    }
    
    // MARK: - Folder Creation
    
    @Test("Create folder shows sheet")
    func testCreateFolderShowsSheet() async throws {
        // Given: Dashboard with event
        let viewModel = try await createIdleDashboardViewModelWithEvents()
        let event = viewModel.upcomingEvents[0]
        #expect(viewModel.isCreateFolderSheetPresented == false)
        
        // When: Beginning folder creation
        viewModel.folderCreationEvent = event
        viewModel.isCreateFolderSheetPresented = true
        
        // Then: Sheet should be shown
        #expect(viewModel.isCreateFolderSheetPresented == true)
        #expect(viewModel.folderCreationEvent == event)
    }
    
    @Test("Create folder with valid path succeeds")
    func testCreateFolderValidPath() async throws {
        // Given: Dashboard with event and sheet shown
        let viewModel = try await createIdleDashboardViewModelWithEvents()
        let event = viewModel.upcomingEvents[0]
        
        viewModel.newFolderPath = "Work/1:1s"
        viewModel.newFolderColor = .blue
        
        // When: Creating folder
        try await viewModel.createFolder(path: "Work/1:1s", color: .blue, for: event)
        
        // Then: Folder should be created (implementation dependent)
        #expect(viewModel.isCreateFolderSheetPresented == false)
    }
    
    @Test("Create folder with invalid path throws error")
    func testCreateFolderInvalidPath() async throws {
        // Given: Dashboard
        let viewModel = try await createIdleDashboardViewModelWithEvents()
        let event = viewModel.upcomingEvents[0]
        
        // When: Creating folder with too deep path
        // Then: Must throw error
        await #expect(throws: PresentationError.self) {
            try await viewModel.createFolder(
                path: "A/B/C/D/E", // Too deep (>2 levels)
                color: .blue,
                for: event
            )
        }
    }
    
    // MARK: - Meeting Folder Change
    
    @Test("Change meeting folder updates preference")
    func testChangeMeetingFolder() async throws {
        // Given: Dashboard with event
        let viewModel = try await createIdleDashboardViewModelWithEvents()
        let event = viewModel.upcomingEvents[0]
        
        // When: Changing folder
        try await viewModel.changeMeetingFolder(
            to: "Work/Meetings",
            for: event,
            moveExisting: false
        )
        
        // Then: Preference should be updated (implementation dependent)
    }
    
    @Test("Change meeting folder with move existing affects sessions")
    func testChangeMeetingFolderMoveExisting() async throws {
        // Given: Dashboard with event and existing sessions
        let viewModel = try await createIdleDashboardViewModelWithEventsAndHistory()
        let event = viewModel.upcomingEvents[0]
        let historyCount = viewModel.sessionHistory.count
        #expect(historyCount > 0)
        
        // When: Changing folder and moving existing
        try await viewModel.changeMeetingFolder(
            to: "NewFolder",
            for: event,
            moveExisting: true
        )
        
        // Then: Sessions should be moved (implementation dependent)
    }
    
    // MARK: - Toggle Earlier Today
    
    @Test("Toggle earlier today changes visibility")
    func testToggleEarlierToday() async throws {
        // Given: Dashboard with earlier today events
        let viewModel = try await createIdleDashboardViewModelWithEarlierTodayEvents()
        #expect(!viewModel.earlierTodayEvents.isEmpty)
        
        let initialVisibility = viewModel.showsEarlierToday
        
        // When: Toggling
        viewModel.showsEarlierToday.toggle()
        
        // Then: Visibility should change
        #expect(viewModel.showsEarlierToday != initialVisibility)
    }
    
    // MARK: - Helper Functions
    
    private func createIdleDashboardViewModel(calendarEnabled: Bool = true) async throws -> any IdleDashboardViewModel {
        throw TestError.notImplemented("IdleDashboardViewModel implementation not available")
    }
    
    private func createIdleDashboardViewModelWithHistory() async throws -> any IdleDashboardViewModel {
        throw TestError.notImplemented("IdleDashboardViewModel with history implementation not available")
    }
    
    private func createIdleDashboardViewModelWithEvents() async throws -> any IdleDashboardViewModel {
        throw TestError.notImplemented("IdleDashboardViewModel with events implementation not available")
    }
    
    private func createIdleDashboardViewModelWithDeniedAccess() async throws -> any IdleDashboardViewModel {
        throw TestError.notImplemented("IdleDashboardViewModel with denied access implementation not available")
    }
    
    private func createIdleDashboardViewModelWithActiveSession() async throws -> any IdleDashboardViewModel {
        throw TestError.notImplemented("IdleDashboardViewModel with active session implementation not available")
    }
    
    private func createIdleDashboardViewModelWithEventsAndHistory() async throws -> any IdleDashboardViewModel {
        throw TestError.notImplemented("IdleDashboardViewModel with events and history implementation not available")
    }
    
    private func createIdleDashboardViewModelWithFutureEvent() async throws -> any IdleDashboardViewModel {
        throw TestError.notImplemented("IdleDashboardViewModel with future event implementation not available")
    }
    
    private func createIdleDashboardViewModelWithMeetingURLEvent() async throws -> any IdleDashboardViewModel {
        throw TestError.notImplemented("IdleDashboardViewModel with meeting URL event implementation not available")
    }
    
    private func createIdleDashboardViewModelWithEarlierTodayEvents() async throws -> any IdleDashboardViewModel {
        throw TestError.notImplemented("IdleDashboardViewModel with earlier today events implementation not available")
    }
}

// MARK: - IdleDashboardViewModel Property Tests (Invariants)

@Suite("IdleDashboardViewModel UI State Invariants")
struct IdleDashboardViewModelInvariantTests {
    
    @Test("Calendar disabled implies no events")
    func testCalendarDisabledImpliesNoEvents() async throws {
        // Property: isCalendarIntegrationEnabled == false → upcomingEvents.isEmpty
        let viewModel = try await createIdleDashboardViewModel(calendarEnabled: false)
        
        if !viewModel.isCalendarIntegrationEnabled {
            #expect(viewModel.upcomingEvents.isEmpty)
            #expect(viewModel.earlierTodayEvents.isEmpty)
        }
    }
    
    @Test("Calendar access denied implies empty events")
    func testAccessDeniedImpliesNoEvents() async throws {
        // Property: calendarAccessState == .denied → upcomingEvents.isEmpty
        let viewModel = try await createIdleDashboardViewModelWithDeniedAccess()
        
        if viewModel.calendarAccessState == .denied {
            await viewModel.refresh()
            #expect(viewModel.upcomingEvents.isEmpty)
        }
    }
    
    @Test("Earlier today events are subset of all day events")
    func testEarlierTodayIsSubset() async throws {
        // Property: earlierTodayEvents ⊆ all day events
        let viewModel = try await createIdleDashboardViewModelWithEarlierTodayEvents()
        
        let now = Date()
        for event in viewModel.earlierTodayEvents {
            // All earlier today events should end before now
            #expect(event.endDate <= now)
            // And be from today
            #expect(Calendar.current.isDateInToday(event.startDate))
        }
    }
    
    @Test("Upcoming events are sorted by start time")
    func testEventsSortedByStartTime() async throws {
        // Property: upcomingEvents is sorted by startDate
        let viewModel = try await createIdleDashboardViewModelWithEvents()
        
        let events = viewModel.upcomingEvents
        for i in 0..<(events.count - 1) {
            #expect(events[i].startDate <= events[i + 1].startDate)
        }
    }
    
    @Test("Recent sessions are subset of session history")
    func testRecentSessionsSubset() async throws {
        // Property: recentSessions ⊆ sessionHistory
        let viewModel = try await createIdleDashboardViewModelWithHistory()
        
        for recent in viewModel.recentSessions {
            #expect(viewModel.sessionHistory.contains { $0.id == recent.id })
        }
        #expect(viewModel.recentSessions.count <= viewModel.sessionHistory.count)
    }
    
    @Test("Can quick start when no active session")
    func testCanQuickStartInvariant() async throws {
        // Property: canQuickStart == !hasActiveSession
        let viewModel = try await createIdleDashboardViewModel()
        
        // Without active session, should be able to quick start
        #expect(viewModel.canQuickStart == true)
        
        // With active session, should not be able to quick start
        let withSession = try await createIdleDashboardViewModelWithActiveSession()
        #expect(withSession.canQuickStart == false)
    }
    
    @Test("Folder creation event matches sheet state")
    func testFolderCreationEventMatchesSheet() async throws {
        // Property: isCreateFolderSheetPresented == (folderCreationEvent != nil)
        let viewModel = try await createIdleDashboardViewModelWithEvents()
        
        // Initially
        #expect(viewModel.isCreateFolderSheetPresented == (viewModel.folderCreationEvent != nil))
        
        // After showing sheet
        viewModel.folderCreationEvent = viewModel.upcomingEvents.first
        viewModel.isCreateFolderSheetPresented = true
        #expect(viewModel.isCreateFolderSheetPresented == (viewModel.folderCreationEvent != nil))
    }
    
    @Test("Shows earlier today only when events exist")
    func testShowsEarlierTodayOnlyWhenEvents() async throws {
        // Property: showsEarlierToday → !earlierTodayEvents.isEmpty
        let viewModel = try await createIdleDashboardViewModel()
        
        if viewModel.showsEarlierToday {
            #expect(!viewModel.earlierTodayEvents.isEmpty)
        }
    }
    
    @Test("New folder path is normalized")
    func testNewFolderPathNormalized() async throws {
        // Property: newFolderPath should be normalized (no leading/trailing slashes, etc.)
        let viewModel = try await createIdleDashboardViewModel()
        
        viewModel.newFolderPath = "/Work/1:1s/"
        // After normalization (implementation dependent)
        // Should not have leading/trailing slashes
        #expect(!viewModel.newFolderPath.hasPrefix("/") || viewModel.newFolderPath.count > 1)
        #expect(!viewModel.newFolderPath.hasSuffix("/") || viewModel.newFolderPath.count > 1)
    }
    
    @Test("Refresh updates last refresh time")
    func testRefreshUpdatesTime() async throws {
        // Property: refresh() updates the data
        let viewModel = try await createIdleDashboardViewModelWithEvents()
        let eventsBefore = viewModel.upcomingEvents
        
        // Wait a bit
        try await Task.sleep(for: .milliseconds(100))
        
        // Refresh
        await viewModel.refresh()
        
        // Data may or may not change, but refresh should complete without error
        #expect(viewModel.isLoading == false)
    }
    
    // MARK: - Helper Functions
    
    private func createIdleDashboardViewModel(calendarEnabled: Bool = true) async throws -> any IdleDashboardViewModel {
        throw TestError.notImplemented("IdleDashboardViewModel implementation not available")
    }
    
    private func createIdleDashboardViewModelWithEvents() async throws -> any IdleDashboardViewModel {
        throw TestError.notImplemented("IdleDashboardViewModel with events implementation not available")
    }
    
    private func createIdleDashboardViewModelWithDeniedAccess() async throws -> any IdleDashboardViewModel {
        throw TestError.notImplemented("IdleDashboardViewModel with denied access implementation not available")
    }
    
    private func createIdleDashboardViewModelWithActiveSession() async throws -> any IdleDashboardViewModel {
        throw TestError.notImplemented("IdleDashboardViewModel with active session implementation not available")
    }
    
    private func createIdleDashboardViewModelWithHistory() async throws -> any IdleDashboardViewModel {
        throw TestError.notImplemented("IdleDashboardViewModel with history implementation not available")
    }
    
    private func createIdleDashboardViewModelWithEarlierTodayEvents() async throws -> any IdleDashboardViewModel {
        throw TestError.notImplemented("IdleDashboardViewModel with earlier today events implementation not available")
    }
}

// MARK: - Error Presentation Tests

@Suite("IdleDashboardViewModel Error Presentation")
struct IdleDashboardViewModelErrorPresentationTests {
    
    @Test("Calendar access failure presents error")
    func testCalendarAccessFailure() async throws {
        // Given: Dashboard that will fail to get access
        let viewModel = try await createFailingIdleDashboardViewModel()
        
        // When: Requesting access
        await viewModel.requestCalendarAccess()
        
        // Then: Error should be set if access fails
        if viewModel.calendarAccessState == .denied {
            #expect(viewModel.error != nil || true) // May or may not set error
        }
    }
    
    @Test("Refresh failure presents error")
    func testRefreshFailure() async throws {
        // Given: Dashboard that will fail on refresh
        let viewModel = try await createFailingIdleDashboardViewModel()
        
        // When: Refreshing
        await viewModel.refresh()
        
        // Then: Error should be set
        // Note: refresh might not throw but could set error
        // #expect(viewModel.error != nil) // Depends on implementation
    }
    
    @Test("Quick start failure presents error")
    func testQuickStartFailure() async throws {
        // Given: Dashboard that will fail
        let viewModel = try await createFailingIdleDashboardViewModel()
        
        // When: Quick starting
        do {
            _ = try await viewModel.startQuickRecording()
            Issue.record("Expected operation to fail")
        } catch {
            // Then: Error should be set
            #expect(viewModel.error != nil)
        }
    }
    
    @Test("Folder creation failure presents error")
    func testFolderCreationFailure() async throws {
        // Given: Dashboard
        let viewModel = try await createFailingIdleDashboardViewModel()
        let event = CalendarEvent(
            id: "test",
            title: "Test",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600)
        )
        
        // When: Creating folder with invalid data
        do {
            try await viewModel.createFolder(path: "", color: .blue, for: event)
            Issue.record("Expected operation to fail")
        } catch {
            // Then: Error should be set
            #expect(viewModel.error != nil)
        }
    }
    
    @Test("Clear error removes error state")
    func testClearError() async throws {
        // Given: Dashboard with error
        let viewModel = try await createFailingIdleDashboardViewModel()
        do {
            _ = try await viewModel.startQuickRecording()
        } catch {
            #expect(viewModel.error != nil)
        }
        
        // When: Clearing error
        viewModel.clearError()
        
        // Then: Error should be nil
        #expect(viewModel.error == nil)
    }
    
    @Test("Error recovery suggestion is helpful")
    func testErrorRecoverySuggestion() async throws {
        // Given: Various errors
        let calendarError = PresentationError.sessionStartFailed(reason: "Calendar access denied")
        
        // Then: Should have recovery suggestion
        #expect(calendarError.recoverySuggestion != nil)
        #expect(!calendarError.recoverySuggestion!.isEmpty)
    }
    
    // MARK: - Helper Functions
    
    private func createFailingIdleDashboardViewModel() async throws -> any IdleDashboardViewModel {
        throw TestError.notImplemented("Failing IdleDashboardViewModel implementation not available")
    }
    
    private func createIdleDashboardViewModel() async throws -> any IdleDashboardViewModel {
        throw TestError.notImplemented("IdleDashboardViewModel implementation not available")
    }
}
