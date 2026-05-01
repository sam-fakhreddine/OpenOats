# Implementation Handoff: MeetingAppMonitor

## Test Specification (RED Phase Complete)

**Test File:** `OpenOats/Tests/OpenOatsTests/Detection/MeetingAppMonitorTests.swift`

### Required API

```swift
@MainActor
final class MeetingAppMonitor: ObservableObject {
    // MARK: - Published State
    @Published var runningMeetingApps: [RunningMeetingApp]
    
    // MARK: - Callbacks
    var onMeetingStarted: ((RunningMeetingApp) -> Void)?
    var onMeetingEnded: ((RunningMeetingApp) -> Void)?
    
    // MARK: - Static Registry
    static let knownMeetingApps: [String: String]
    
    // MARK: - Lifecycle
    func startMonitoring(customBundleIDs: [String])
    func stopMonitoring()
    
    // MARK: - Data Model
    struct RunningMeetingApp: Identifiable, Equatable {
        let id: UUID
        let bundleID: String
        let name: String
        let processID: pid_t
        let launchDate: Date
        var isUsingCamera: Bool
        var isUsingMicrophone: Bool
        var lastActivityDate: Date?
    }
}
```

### Test Cases to Pass

1. **Hardware Detection**
   - `testHardwareDetection_WhenCameraInUse_DetectsMeeting()`
   - `testHardwareDetection_WhenMicInUse_DetectsMeeting()`
   - `testHardwareDetection_WhenNeitherIdle_NoMeeting()`
   - `testHardwareDetection_WhenMeetingEnds_TriggersCallback()`

2. **App Lifecycle**
   - `testAppLifecycle_WhenZoomLaunched_AddsToRunningApps()`
   - `testAppLifecycle_WhenZoomTerminated_RemovesFromRunningApps()`
   - `testAppLifecycle_WhenMultipleAppsRunning_TracksAll()`

3. **Filtering**
   - `testFiltering_WhenAppInIgnoredList_DoesNotDetect()`
   - `testFiltering_CustomBundleIDs_Detected()`
   - `testFiltering_NonMeetingApps_Ignored()`

4. **State Management**
   - `testState_WhenMonitoringStarted_UpdatesState()`
   - `testState_WhenMonitoringStopped_ClearsApps()`
   - `testState_DuplicateApps_NotAdded()`

5. **Known Apps Registry**
   - `testKnownApps_Zoom_Recognized()`
   - `testKnownApps_Teams_Recognized()`
   - `testKnownApps_FaceTime_Recognized()`
   - `testKnownApps_HasMinimumCount()` (≥20 apps)

### Implementation Notes

1. **Hardware Detection Strategy:**
   - Poll every 2 seconds
   - Use `AVCaptureDevice.DiscoverySession` to check device availability
   - If `lockForConfiguration()` throws, device is in use by another app
   - Check both `.video` and `.audio` media types

2. **App Lifecycle:**
   - Use `NSWorkspace.shared.runningApplications`
   - Subscribe to `NSWorkspace.didLaunchApplicationNotification`
   - Subscribe to `NSWorkspace.didTerminateApplicationNotification`
   - Filter by `activationPolicy == .regular`

3. **Known Meeting Apps (Minimum 20):**
   - Zoom: `us.zoom.xos`
   - Teams: `com.microsoft.teams`, `com.microsoft.teams2`
   - FaceTime: `com.apple.FaceTime`
   - Meet: Chrome PWA bundle IDs
   - Webex, Skype, Slack, Discord, etc.

4. **Threading:**
   - `@MainActor` required
   - Use `Timer.scheduledTimer` for polling
   - All callbacks on main thread

### Acceptance Criteria

- [ ] All 17 test cases pass
- [ ] No compiler warnings
- [ ] `@MainActor` compliance
- [ ] Proper memory management (no retain cycles)
- [ ] Known apps registry has ≥20 entries

## Next Steps

1. Implement MeetingAppMonitor.swift
2. Run tests to verify GREEN phase
3. Hand off to refactor phase
