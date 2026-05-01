# Meeting Detection Test Plan

## Overview

This test plan defines the testing strategy for the meeting detection feature. It follows TDD principles with tests written before implementation (RED phase), then implemented to pass (GREEN phase), then refactored.

**Scope:**
- Unit tests for individual components
- Integration tests for component interactions
- Mock/stub infrastructure for isolated testing
- Coverage targets and acceptance criteria

## Test Strategy Summary

| Level | Count | Purpose |
|-------|-------|---------|
| Unit Tests | 120+ | Component isolation with mocks |
| Integration Tests | 25+ | Cross-component workflows |
| End-to-End Tests | 5 | Full user scenarios |
| Performance Tests | 3 | CPU, memory, latency bounds |

**Coverage Target:** 85% line coverage, 100% of properties verified

---

## Unit Test Strategy

### Philosophy
- **Test behavior, not implementation**: Verify what component does, not how
- **One assertion per test**: Clear failure indication
- **Arrange-Act-Assert**: Consistent test structure
- **Mocks for dependencies**: Isolate unit under test

### Test Organization

```
OpenOats/Tests/OpenOatsTests/Detection/
├── MeetingAppMonitorTests.swift          (Hardware & Lifecycle)
├── MeetingAppRegistryTests.swift         (Known app bundle IDs)
├── MeetingDetectionEngineTests.swift     (State machine & Settings)
├── SilenceTimeoutTests.swift             (Timer & Timeout)
├── NotificationHandlingTests.swift       (UNUserNotificationCenter)
├── AppCoordinatorIntegrationTests.swift  (Coordinator callbacks)
├── IgnoredAppsTests.swift                (Blacklist behavior)
├── ConfidenceScoringTests.swift          (False positive reduction)
├── StateVisibilityTests.swift            (UI observability)
├── AppTerminationTests.swift             (Cleanup behavior)
├── MeetingAppMonitorIntegrationTests.swift (Component integration)
└── EndToEndDetectionTests.swift           (Full scenarios)
```

---

## Mock/Stub Requirements

### Mock Infrastructure

#### MockAVCaptureDevice
```swift
/// Simulates camera/microphone hardware state for testing
class MockAVCaptureDevice {
    var shouldFailLock: Bool = false
    var lockAttempts: Int = 0
    var unlockCalls: Int = 0
    
    func lockForConfiguration() throws {
        lockAttempts += 1
        if shouldFailLock {
            throw AVCaptureDevice.ConfigurationLockError.deviceInUseByAnotherApplication
        }
    }
    
    func unlockForConfiguration() {
        unlockCalls += 1
    }
}
```

**Purpose:** Test hardware detection without real camera/mic
**Properties tested:** SAFETY-002, LIVENESS-005, PERFORMANCE-001

#### MockNSWorkspace
```swift
/// Simulates app launch/termination notifications
class MockNSWorkspace {
    var runningApplications: [NSRunningApplication] = []
    var launchHandlers: [(NSRunningApplication) -> Void] = []
    var terminationHandlers: [(NSRunningApplication) -> Void] = []
    
    func simulateAppLaunch(_ app: NSRunningApplication) {
        runningApplications.append(app)
        launchHandlers.forEach { $0(app) }
    }
    
    func simulateAppTermination(_ app: NSRunningApplication) {
        runningApplications.removeAll { $0.processIdentifier == app.processIdentifier }
        terminationHandlers.forEach { $0(app) }
    }
}
```

**Purpose:** Test app lifecycle without launching real apps
**Properties tested:** LIVENESS-001, SAFETY-005

#### MockSettingsStore
```swift
/// Configurable settings for testing behavior changes
class MockSettingsStore {
    var meetingAutoDetectEnabled: Bool = true
    var silenceTimeoutMinutes: Int = 15
    var ignoredAppBundleIDs: [String] = []
    var customMeetingAppBundleIDs: [String] = []
    var detectionLogEnabled: Bool = false
    
    var changeObservers: [() -> Void] = []
    
    func triggerChange() {
        changeObservers.forEach { $0() }
    }
}
```

**Purpose:** Test settings-driven behavior
**Properties tested:** SAFETY-004, SAFETY-006, INVARIANT-005

#### MockUNUserNotificationCenter
```swift
/// Captures notification requests for verification
class MockUNUserNotificationCenter {
    var notificationRequests: [UNNotificationRequest] = []
    var categories: [UNNotificationCategory] = []
    var authorizationGranted: Bool = true
    
    func add(_ request: UNNotificationRequest, withCompletionHandler completionHandler: ((Error?) -> Void)?) {
        notificationRequests.append(request)
        completionHandler?(nil)
    }
    
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
        self.categories = Array(categories)
    }
}
```

**Purpose:** Test notifications without displaying them
**Properties tested:** LIVENESS-001, INVARIANT-003

#### MockAppCoordinator
```swift
/// Captures coordinator callbacks for verification
class MockAppCoordinator {
    var startRecordingCalled: Bool = false
    var stopRecordingCalled: Bool = false
    var userAcceptedCalled: Bool = false
    var isRecording: Bool = false
    
    func userAcceptedMeetingDetection() {
        userAcceptedCalled = true
        startRecordingCalled = true
        isRecording = true
    }
}
```

**Purpose:** Test engine-coordinator integration
**Properties tested:** LIVENESS-002, SAFETY-005

#### StubTimer
```swift
/// Controllable timer for testing timeout behavior
class StubTimer {
    private var fireAction: (() -> Void)?
    var isValid: Bool = false
    var scheduledInterval: TimeInterval?
    
    func simulateFire() {
        fireAction?()
    }
    
    func invalidate() {
        isValid = false
    }
    
    static func scheduledTimer(withTimeInterval interval: TimeInterval, repeats: Bool, block: @escaping () -> Void) -> StubTimer {
        let timer = StubTimer()
        timer.scheduledInterval = interval
        timer.fireAction = block
        timer.isValid = true
        return timer
    }
}
```

**Purpose:** Test silence timeout deterministically
**Properties tested:** LIVENESS-003, LIVENESS-004, SAFETY-004

---

## Integration Test Approach

### Component Integration Tests

#### MeetingAppMonitor + Hardware Detection
**Goal:** Verify hardware polling integrates with app monitoring

**Test Cases:**
1. `testHardwareDetectionTriggersMeetingStartedCallback()`
   - Given: Meeting app running
   - When: Camera becomes active (mock returns lock failure)
   - Then: onMeetingStarted callback fires with correct app

2. `testMultipleAppsOneHardwareActive()`
   - Given: Zoom and Teams both running
   - When: Camera activates
   - Then: Only one meeting started event (first tracked app)

3. `testHardwarePollingStopsWhenNoAppsRunning()`
   - Given: All meeting apps terminated
   - When: 2 seconds pass
   - Then: No hardware checks performed (CPU optimization)

#### MeetingDetectionEngine + MeetingAppMonitor
**Goal:** Verify state machine responds to monitor events

**Test Cases:**
1. `testStateTransitionsFromMonitorCallbacks()`
   - Verify: monitoring → meetingDetected → awaitingUserResponse flow

2. `testIgnoredAppBlocksStateTransition()`
   - Given: App is in ignoredAppBundleIDs
   - When: onMeetingStarted fires for that app
   - Then: State remains monitoring, no notification

3. `testMonitorStopWhenEngineStops()`
   - Given: Engine in any non-idle state
   - When: stop() called
   - Then: appMonitor.stopMonitoring() called

#### MeetingDetectionEngine + Notifications
**Goal:** Verify notification actions trigger correct state changes

**Test Cases:**
1. `testAcceptActionTriggersRecording()`
   - Simulate ACCEPT_MEETING action
   - Verify state → .recording
   - Verify onRequestStartRecording callback

2. `testDeclineActionResetsMonitoring()`
   - Simulate DECLINE_MEETING action
   - Verify state → .monitoring
   - Verify currentMeetingApp = nil

3. `testIgnoreActionAddsToBlacklist()`
   - Simulate IGNORE_APP action
   - Verify bundle ID in ignoredAppBundleIDs
   - Verify state → .monitoring

#### MeetingDetectionEngine + AppCoordinator
**Goal:** Verify session lifecycle integration

**Test Cases:**
1. `testRecordingStartFlowsToCoordinator()`
   - Given: User accepts meeting
   - When: Engine transitions to .recording
   - Then: coordinator.startSession() called

2. `testRecordingStopFlowsToCoordinator()`
   - Given: Silence timeout reached
   - When: finalizeMeeting() executes
   - Then: coordinator.finalizeSession() called

3. `testSessionStateSynchronization()`
   - Verify coordinator.isRecording matches engine state

---

## End-to-End Test Scenarios

### Scenario 1: Happy Path Zoom Meeting
```
Preconditions:
  - Auto-detection enabled
  - Zoom not in ignored apps
  - 15-minute silence timeout

Steps:
  1. User launches Zoom
  2. User joins meeting (camera + mic activate)
  3. System detects hardware within 2 seconds
  4. System waits 5-second debounce
  5. System sends notification: "Meeting Detected - Zoom appears to be in a meeting. Start transcribing?"
  6. User clicks "Start Recording"
  7. Recording begins within 1 second
  8. Meeting ends, camera/mic deactivate
  9. 15-minute silence timer starts
  10. No hardware reactivation within 15 minutes
  11. Session finalizes automatically

Expected:
  - Transcript captured for full meeting duration
  - User received exactly 1 notification
  - Session appears in history
```

### Scenario 2: False Positive Prevention
```
Preconditions:
  - Auto-detection enabled

Steps:
  1. User opens Photo Booth
  2. Camera activates (but no microphone)
  3. System detects camera only
  4. Confidence calculated as 0.7 (app + camera)
  5. Wait 5-second debounce
  6. Notification sent (Photo Booth is a known non-meeting app)
  7. User clicks "Always Ignore This App"

Expected:
  - Photo Booth added to ignoredAppBundleIDs
  - Future Photo Booth sessions trigger no notifications
```

### Scenario 3: User Declines Once
```
Preconditions:
  - Auto-detection enabled

Steps:
  1. Zoom meeting detected
  2. Notification sent
  3. User clicks "Not Now"
  4. 5 minutes pass
  5. User starts another Zoom meeting

Expected:
  - Step 3: State returns to monitoring
  - Step 5: Notification sent again (temporary decline expired)
```

### Scenario 4: App Termination During Recording
```
Preconditions:
  - Recording active

Steps:
  1. Zoom force-quits or crashes
  2. NSWorkspace detects termination
  3. System immediately finalizes session

Expected:
  - No data loss
  - Transcript saved up to termination point
  - State returns to monitoring
```

### Scenario 5: Settings Change While Monitoring
```
Preconditions:
  - Monitoring active

Steps:
  1. User opens Settings
  2. User disables meetingAutoDetectEnabled
  3. User changes silenceTimeoutMinutes to 30

Expected:
  - Step 2: Monitoring stops immediately, state → idle
  - Step 3: New timeout applies to future sessions (no restart needed)
```

---

## Test Implementation Checklist

### Wave 1: Core Detection (Tasks 1-8)

| Test | Status | File | Properties |
|------|--------|------|------------|
| Mock infrastructure | ☐ | Mocks/*.swift | All |
| Hardware detection unit | ☐ | MeetingAppMonitorTests.swift | SAFETY-002, LIVENESS-005 |
| Hardware detection integration | ☐ | MeetingAppMonitorTests.swift | PERFORMANCE-001 |
| App lifecycle unit | ☐ | MeetingAppMonitorTests.swift | LIVENESS-001 |
| App lifecycle integration | ☐ | MeetingAppMonitorIntegrationTests.swift | SAFETY-005 |
| Registry contents | ☐ | MeetingAppRegistryTests.swift | LIVENESS-001 |
| End-to-end monitor | ☐ | MeetingAppMonitorIntegrationTests.swift | Multiple |

### Wave 2: Detection Engine (Tasks 9-14)

| Test | Status | File | Properties |
|------|--------|------|------------|
| State machine transitions | ☐ | MeetingDetectionEngineTests.swift | INVARIANT-001 |
| State machine invalid | ☐ | MeetingDetectionEngineTests.swift | INVARIANT-001 |
| Engine settings integration | ☐ | MeetingDetectionEngineTests.swift | SAFETY-006, INVARIANT-005 |
| Engine coordinator callbacks | ☐ | MeetingDetectionEngineTests.swift | LIVENESS-002 |
| Silence timeout unit | ☐ | SilenceTimeoutTests.swift | SAFETY-004, LIVENESS-003 |
| Silence timeout reset | ☐ | SilenceTimeoutTests.swift | LIVENESS-003 |
| Notification actions | ☐ | NotificationHandlingTests.swift | INVARIANT-003 |
| Notification content | ☐ | NotificationHandlingTests.swift | LIVENESS-001 |

### Wave 3: Integration & Polish (Tasks 15-27)

| Test | Status | File | Properties |
|------|--------|------|------------|
| Coordinator integration | ☐ | AppCoordinatorIntegrationTests.swift | LIVENESS-002, SAFETY-005 |
| Ignored apps unit | ☐ | IgnoredAppsTests.swift | SAFETY-003 |
| Ignored apps persistence | ☐ | IgnoredAppsTests.swift | INVARIANT-005 |
| Confidence calculation | ☐ | ConfidenceScoringTests.swift | INVARIANT-004 |
| Confidence filtering | ☐ | ConfidenceScoringTests.swift | LIVENESS-004 |
| Debouncing | ☐ | ConfidenceScoringTests.swift | LIVENESS-004 |
| State visibility | ☐ | StateVisibilityTests.swift | INVARIANT-006 |
| App termination cleanup | ☐ | AppTerminationTests.swift | SAFETY-005 |
| End-to-end scenario 1 | ☐ | EndToEndDetectionTests.swift | Multiple |
| End-to-end scenario 2 | ☐ | EndToEndDetectionTests.swift | Multiple |
| End-to-end scenario 3 | ☐ | EndToEndDetectionTests.swift | Multiple |
| End-to-end scenario 4 | ☐ | EndToEndDetectionTests.swift | Multiple |
| End-to-end scenario 5 | ☐ | EndToEndDetectionTests.swift | Multiple |
| Privacy verification | ☐ | MeetingAppMonitorTests.swift | SAFETY-002 |
| Settings UI verification | ☐ | (Manual) | SAFETY-006 |

---

## Coverage Targets

### Minimum Coverage Requirements

```
MeetingAppMonitor.swift          90% line coverage
MeetingDetectionEngine.swift     90% line coverage
AppCoordinator.swift (detection)   85% line coverage
SettingsStore.swift (detection)   80% line coverage
```

### Critical Path Coverage
The following paths must have 100% coverage:

1. **Detection to Notification:**
   - App launch → Hardware active → Debounce → Confidence check → Notification

2. **User Response to Recording:**
   - Notification action → State change → Coordinator callback → Session start

3. **Meeting End Detection:**
   - Hardware inactive → Timer start → Timeout → Finalize

4. **App Termination:**
   - Termination notification → State check → Immediate finalize (if recording)

5. **Settings Changes:**
   - Setting toggle → Engine state update → Behavior change

---

## Performance Test Specifications

### CPU Usage Test
```
Name: testPollingCPUUsage
Duration: 60 seconds
Measurement: CPU % sampled every 1 second
Criteria:
  - Average CPU < 5%
  - 99th percentile CPU < 10%
  - No samples > 15%
```

### Notification Latency Test
```
Name: testDetectionToNotificationLatency
Iterations: 50
Measurement: Time from mock hardware activation to notification request created
Criteria:
  - Average latency < 3 seconds
  - 95th percentile < 5 seconds
  - 99th percentile < 8 seconds
```

### State Transition Latency Test
```
Name: testUserActionToRecordingLatency
Iterations: 50
Measurement: Time from userAcceptedMeeting() to state == .recording
Criteria:
  - Average latency < 500ms
  - 99th percentile < 1 second
```

---

## Test Execution Order

### Phase 1: Foundation (Mocks + Unit Tests)
1. Compile mock infrastructure
2. Run MeetingAppRegistryTests (should pass immediately - registry exists)
3. Run MeetingAppMonitorTests (will fail - RED phase)

### Phase 2: Core Implementation
4. Implement MeetingAppMonitor (GREEN phase)
5. Re-run MeetingAppMonitorTests (should pass)
6. Run MeetingAppMonitorIntegrationTests

### Phase 3: Engine Unit Tests
7. Run MeetingDetectionEngineTests (will fail - RED phase)
8. Run SilenceTimeoutTests (will fail)
9. Run NotificationHandlingTests (will fail)

### Phase 4: Engine Implementation
10. Implement MeetingDetectionEngine (GREEN phase)
11. Re-run all engine tests (should pass)

### Phase 5: Integration
12. Run AppCoordinatorIntegrationTests
13. Run IgnoredAppsTests
14. Run ConfidenceScoringTests
15. Run AppTerminationTests

### Phase 6: End-to-End
16. Run EndToEndDetectionTests
17. Performance tests
18. Manual UI verification

---

## Debugging Failed Tests

### Common Failure Patterns

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| Tests pass individually, fail together | Shared state/mocks not reset | Add setUp/tearDown to reset all mocks |
| Async test failures | Missing await or expectation | Use XCTestExpectation or async/await properly |
| State machine test failures | Invalid transition allowed | Add guard checks in engine |
| Timer test failures | Real timer used instead of stub | Verify StubTimer injection |
| Notification test failures | UNUserNotificationCenter not mocked | Ensure mock is set as delegate |

### Test Debugging Tools

```swift
// Enable verbose logging in tests
var isVerbose = true
func debugLog(_ message: String) {
    if isVerbose { print("[TEST] \(message)") }
}

// State machine visualization
trackStateTransitions { from, to, event in
    debugLog("State: \(from.displayName) → \(to.displayName) via \(event)")
}
```

---

## Continuous Integration

### Pre-commit Checks
```bash
swift test --filter MeetingAppMonitorTests
swift test --filter MeetingDetectionEngineTests
swift test --filter "Detection/"
```

### Pull Request Requirements
- All detection tests pass
- Coverage targets met
- No new compiler warnings
- Static analysis clean

### Nightly Tests
- Full test suite with performance benchmarks
- Memory leak detection
- Thread sanitizer run
