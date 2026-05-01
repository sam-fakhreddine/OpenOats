# Implementation Handoff: MeetingDetectionEngine

## Test Specification (RED Phase Complete)

**Test File:** `OpenOats/Tests/OpenOatsTests/Detection/MeetingDetectionEngineTests.swift`

### Required API

```swift
@MainActor
final class MeetingDetectionEngine: ObservableObject {
    // MARK: - Published State
    @Published private(set) var state: DetectionState
    @Published private(set) var lastDetectedMeeting: MeetingAppMonitor.RunningMeetingApp?
    
    // MARK: - State Machine
    enum DetectionState: Equatable {
        case idle
        case monitoring
        case awaitingUserResponse
        case recording
        case ending
    }
    
    // MARK: - Dependencies
    private let settings: SettingsStore
    private let coordinator: AppCoordinator
    private let appMonitor: MeetingAppMonitor
    
    // MARK: - Lifecycle
    init(settings: SettingsStore, coordinator: AppCoordinator)
    func start()
    func stop()
    
    // MARK: - Event Handlers (called by MeetingAppMonitor)
    func handleMeetingDetected(_ app: MeetingAppMonitor.RunningMeetingApp)
    func handleMeetingEnded(_ app: MeetingAppMonitor.RunningMeetingApp)
    
    // MARK: - User Actions
    func userAcceptedMeeting()
    func userDeclinedMeeting()
    func userStoppedRecording()
    func markAsNotMeeting()
}

// MARK: - Notification Delegate
extension MeetingDetectionEngine: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, 
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void)
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void)
}
```

### Test Cases to Pass

1. **State Machine (6 tests)**
   - `testStateMachine_InitialState_IsIdle()`
   - `testStateMachine_WhenStarted_TransitionsToMonitoring()`
   - `testStateMachine_WhenDisabled_RemainsIdle()`
   - `testStateMachine_WhenMeetingDetected_TransitionsToAwaitingResponse()`
   - `testStateMachine_WhenUserAccepts_TransitionsToRecording()`
   - `testStateMachine_WhenUserDeclines_ReturnsToMonitoring()`
   - `testStateMachine_WhenMeetingEnds_TransitionsToEnding()`
   - `testStateMachine_WhenSilenceTimeoutReached_FinalizesMeeting()`

2. **Notifications (2 tests)**
   - `testNotification_WhenMeetingDetected_SendsNotification()`
   - `testNotification_CategoryIsMeetingDetected()`

3. **Ignore List (2 tests)**
   - `testIgnoreList_WhenAppIgnored_DoesNotDetect()`
   - `testIgnoreList_WhenMarkAsNotMeeting_AddsToIgnored()`

4. **Settings Integration (2 tests)**
   - `testSettings_SilenceTimeout_Respected()`
   - `testSettings_AutoDetectDisabled_DoesNotStart()`

5. **Multi-Meeting (1 test - future)**
   - `testMultiMeeting_WhenSecondMeetingDetected_TracksBoth()`

### State Machine Diagram

```
┌─────────┐    start()     ┌───────────┐
│  idle   │ ─────────────→│ monitoring│
└─────────┘               └─────┬─────┘
     ↑                          │
     │                          │ meeting detected
     │                          ↓
     │                   ┌──────────────┐
     │                   │awaitingUser  │
     │                   │   Response   │
     │                   └──────┬───────┘
     │                          │
     │          ┌───────────────┼───────────────┐
     │          │               │               │
     │          ↓               ↓               ↓
     │    userDeclined()  userAccepted()  timeout
     │          │               │               │
     │          ↓               ↓               ↓
     │    ┌─────────┐    ┌──────────┐    ┌─────────┐
     └────┤monitoring│    │ recording│    │ ending  │
          └─────────┘    └────┬─────┘    └────┬────┘
                              │                 │
                              │ meeting ended   │ silence timeout
                              ↓                 ↓
                         ┌─────────┐      ┌─────────┐
                         │ ending  │      │ finalize│
                         └────┬────┘      └────┬────┘
                              │                 │
                              └─────────────────┘
                                                │
                                                ↓
                                          ┌─────────┐
                                          │monitoring│
                                          └─────────┘
```

### Notification Actions

**Category: MEETING_DETECTED**
- "Start Recording" → `userAcceptedMeeting()`
- "Not Now" → `userDeclinedMeeting()`
- "Always Ignore This App" → `markAsNotMeeting()`

### Implementation Notes

1. **State Machine:**
   - Use enum with associated values if needed
   - Guard transitions (e.g., can't go from idle to recording)
   - Log all state changes

2. **Silence Timeout:**
   - Use `Task.sleep` with cancellation support (NOT DispatchQueue)
   - Read timeout from `settings.silenceTimeoutMinutes`
   - Convert to seconds: `Double(timeoutMinutes) * 60`

3. **Notifications:**
   - Request authorization on init
   - Set delegate to self
   - Create category with 3 actions
   - Handle responses in delegate method

4. **Coordinator Integration:**
   - `userAcceptedMeeting()` → `coordinator.startSession()`
   - Silence timeout → `coordinator.finalizeSession()`
   - `userStoppedRecording()` → `coordinator.finalizeSession()`

5. **Ignore List:**
   - Check `settings.ignoredAppBundleIDs` before detecting
   - `markAsNotMeeting()` adds to ignored list
   - Persist through SettingsStore

### Acceptance Criteria

- [ ] All 15 test cases pass
- [ ] State machine guards invalid transitions
- [ ] Notifications have correct category and actions
- [ ] Silence timeout uses Task.sleep (not DispatchQueue)
- [ ] No retain cycles (weak self in closures)
- [ ] @MainActor compliance throughout

## Next Steps

1. Implement MeetingDetectionEngine.swift
2. Run tests to verify GREEN phase
3. Integrate with AppCoordinator
4. Wire up in OpenOatsApp.swift
