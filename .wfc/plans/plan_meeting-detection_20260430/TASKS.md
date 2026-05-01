# Meeting Detection Implementation Plan

## Overview

This plan implements automatic meeting detection for OpenOats using hardware monitoring, app detection, and user notifications. The implementation follows TDD principles with tests written before implementation.

**Requirements Summary:**
- 9 MUST requirements (REQ-001 to REQ-009)
- 3 SHOULD requirements (REQ-010 to REQ-012)
- 2 COULD requirements (REQ-013 to REQ-014)
- 2 WONT requirements (REQ-015 to REQ-016)

**TDD Approach:** All implementation tasks are preceded by test tasks. Each component has:
1. Write failing tests (RED)
2. Implement to pass tests (GREEN)
3. Refactor (REFACTOR)

## Execution Waves

### Wave 1: Core Detection Infrastructure (TDD Foundation)
- TASK-001 through TASK-008
- Foundation: Mocks, MeetingAppMonitor tests, and implementation
- Deliverable: Hardware detection with full test coverage

### Wave 2: Detection Engine State Machine
- TASK-009 through TASK-014
- Foundation: State machine, notifications, silence timeout
- Deliverable: Complete detection engine with user interaction

### Wave 3: Integration & Polish
- TASK-015 through TASK-020
- Foundation: AppCoordinator wiring, UI visibility, false positive reduction
- Deliverable: Production-ready feature with confidence scoring

## Task Registry

---

## TASK-001: Create Mock Infrastructure for Testing
- **Complexity**: M
- **Wave**: 1
- **Dependencies**: []
- **Canary**: true
- **Files**:
  - `OpenOats/Sources/OpenOats/Detection/Mocks/MockAVCaptureDevice.swift`
  - `OpenOats/Sources/OpenOats/Detection/Mocks/MockNSWorkspace.swift`
  - `OpenOats/Sources/OpenOats/Detection/Mocks/MockSettingsStore.swift`
  - `OpenOats/Sources/OpenOats/Detection/Mocks/MockUNUserNotificationCenter.swift`
  - `OpenOats/Sources/OpenOats/Detection/Mocks/MockAppCoordinator.swift`
  - `OpenOats/Sources/OpenOats/Detection/Mocks/StubTimer.swift`
- **Acceptance Criteria**:
  - [ ] MockAVCaptureDevice simulates lockForConfiguration() success/failure
  - [ ] MockNSWorkspace simulates app launch/termination notifications
  - [ ] MockSettingsStore provides observable settings values
  - [ ] MockUNUserNotificationCenter captures notification requests
  - [ ] MockAppCoordinator captures session start/stop calls
  - [ ] StubTimer provides controllable timer for silence timeout testing
  - [ ] All mocks compile without errors

---

## TASK-002: Write Tests for MeetingAppMonitor Hardware Detection
- **Complexity**: M
- **Wave**: 1
- **Dependencies**: [TASK-001]
- **Files**:
  - `OpenOats/Tests/OpenOatsTests/Detection/MeetingAppMonitorTests.swift`
- **Acceptance Criteria**:
  - [ ] Test detects camera in use when lockForConfiguration() fails
  - [ ] Test detects camera not in use when lock succeeds
  - [ ] Test detects microphone in use when lockForConfiguration() fails
  - [ ] Test detects microphone not in use when lock succeeds
  - [ ] Test handles multiple camera devices correctly
  - [ ] Test polls at 2-second intervals as specified
  - [ ] All tests fail before implementation (RED phase)

---

## TASK-003: Implement MeetingAppMonitor Hardware Detection
- **Complexity**: M
- **Wave**: 1
- **Dependencies**: [TASK-002]
- **Files**:
  - `OpenOats/Sources/OpenOats/Detection/MeetingAppMonitor.swift`
- **Acceptance Criteria**:
  - [ ] Replace placeholder checkMediaDeviceUsage with working implementation
  - [ ] Use AVCaptureDevice.lockForConfiguration() to detect hardware usage
  - [ ] Poll every 2.0 seconds with Timer
  - [ ] CPU usage stays below 5% during polling (measured in tests)
  - [ ] All TASK-002 tests now pass (GREEN phase)
  - [ ] Works with built-in and external cameras

---

## TASK-004: Write Tests for MeetingAppMonitor App Lifecycle
- **Complexity**: M
- **Wave**: 1
- **Dependencies**: [TASK-001]
- **Files**:
  - `OpenOats/Tests/OpenOatsTests/Detection/MeetingAppMonitorTests.swift` (append)
- **Acceptance Criteria**:
  - [ ] Test detects meeting app launch via NSWorkspace notification
  - [ ] Test detects meeting app termination via NSWorkspace notification
  - [ ] Test onMeetingStarted callback fires when hardware activates
  - [ ] Test onMeetingEnded callback fires when hardware deactivates
  - [ ] Test onAppTerminated callback fires when app terminates
  - [ ] Test maintains runningMeetingApps list accurately
  - [ ] All tests fail before implementation (RED phase)

---

## TASK-005: Implement MeetingAppMonitor App Lifecycle
- **Complexity**: M
- **Wave**: 1
- **Dependencies**: [TASK-004, TASK-003]
- **Files**:
  - `OpenOats/Sources/OpenOats/Detection/MeetingAppMonitor.swift`
- **Acceptance Criteria**:
  - [ ] Subscribe to NSWorkspace.didLaunchApplicationNotification
  - [ ] Subscribe to NSWorkspace.didTerminateApplicationNotification
  - [ ] Filter apps by known meeting app bundle IDs + custom IDs
  - [ ] Call onMeetingStarted when hardware activates for tracked app
  - [ ] Call onMeetingEnded when hardware deactivates for tracked app
  - [ ] Call onAppTerminated when tracked app terminates
  - [ ] All TASK-004 tests now pass (GREEN phase)

---

## TASK-006: Write Tests for Known Meeting App Registry
- **Complexity**: S
- **Wave**: 1
- **Dependencies**: [TASK-001]
- **Files**:
  - `OpenOats/Tests/OpenOatsTests/Detection/MeetingAppRegistryTests.swift`
- **Acceptance Criteria**:
  - [ ] Test registry includes Zoom bundle ID (us.zoom.xos)
  - [ ] Test registry includes Teams bundle IDs (com.microsoft.teams, com.microsoft.teams2)
  - [ ] Test registry includes FaceTime bundle ID
  - [ ] Test registry includes Google Meet Chrome PWA bundle ID
  - [ ] Test registry includes Webex bundle ID
  - [ ] Test registry includes Slack bundle ID (com.tinyspeck.slackmacgap)
  - [ ] Test registry includes Discord bundle ID
  - [ ] Test registry is extensible with custom bundle IDs
  - [ ] All tests fail before implementation (RED phase)

---

## TASK-007: Verify MeetingAppRegistry Contents
- **Complexity**: S
- **Wave**: 1
- **Dependencies**: [TASK-006]
- **Files**:
  - `OpenOats/Sources/OpenOats/Detection/MeetingAppMonitor.swift` (verify)
- **Acceptance Criteria**:
  - [ ] knownMeetingApps dictionary contains all required bundle IDs
  - [ ] App name resolution falls back to bundle ID if not in registry
  - [ ] Registry allows runtime addition of custom bundle IDs
  - [ ] All TASK-006 tests pass (registry already correct)

---

## TASK-008: Write Integration Tests for MeetingAppMonitor
- **Complexity**: M
- **Wave**: 1
- **Dependencies**: [TASK-003, TASK-005, TASK-007]
- **Files**:
  - `OpenOats/Tests/OpenOatsTests/Detection/MeetingAppMonitorIntegrationTests.swift`
- **Acceptance Criteria**:
  - [ ] Test end-to-end: app launch → hardware active → onMeetingStarted fires
  - [ ] Test end-to-end: hardware inactive → silence → onMeetingEnded fires
  - [ ] Test end-to-end: app terminates during meeting → onAppTerminated fires
  - [ ] Test handles multiple apps: starts with Zoom, ignores Teams
  - [ ] All integration tests fail before complete integration (RED phase)

---

## TASK-009: Write Tests for MeetingDetectionEngine State Machine
- **Complexity**: L
- **Wave**: 2
- **Dependencies**: [TASK-008]
- **Files**:
  - `OpenOats/Tests/OpenOatsTests/Detection/MeetingDetectionEngineTests.swift`
- **Acceptance Criteria**:
  - [ ] Test state transition: idle → monitoring on start()
  - [ ] Test state transition: monitoring → meetingDetected on meeting start
  - [ ] Test state transition: meetingDetected → awaitingUserResponse on notification
  - [ ] Test state transition: awaitingUserResponse → recording on userAcceptedMeeting()
  - [ ] Test state transition: recording → meetingEnding on hardware deactivation
  - [ ] Test state transition: meetingEnding → monitoring on silence timeout
  - [ ] Test state transition: awaitingUserResponse → monitoring on user declined
  - [ ] Test state: idle on stop() from any state
  - [ ] Test does not start when meetingAutoDetectEnabled is false
  - [ ] All tests fail before implementation (RED phase)

---

## TASK-010: Implement MeetingDetectionEngine State Machine Core
- **Complexity**: L
- **Wave**: 2
- **Dependencies**: [TASK-009]
- **Files**:
  - `OpenOats/Sources/OpenOats/Detection/MeetingDetectionEngine.swift`
- **Acceptance Criteria**:
  - [ ] Replace placeholder state machine with complete implementation
  - [ ] All state transitions from TASK-009 tests work correctly
  - [ ] @Published state property reflects current DetectionState
  - [ ] Engine coordinates with injected MeetingAppMonitor
  - [ ] All TASK-009 tests now pass (GREEN phase)

---

## TASK-011: Write Tests for Silence Timeout
- **Complexity**: M
- **Wave**: 2
- **Dependencies**: [TASK-001]
- **Files**:
  - `OpenOats/Tests/OpenOatsTests/Detection/SilenceTimeoutTests.swift`
- **Acceptance Criteria**:
  - [ ] Test timer starts with configured timeout (silenceTimeoutMinutes)
  - [ ] Test timer resets if hardware reactivates before timeout
  - [ ] Test finalizeMeeting() called on timeout completion
  - [ ] Test timer duration respects settings changes
  - [ ] Test timer invalidates on stop() or early meeting end
  - [ ] All tests use StubTimer for controllable time (RED phase)

---

## TASK-012: Implement Silence Timeout
- **Complexity**: M
- **Wave**: 2
- **Dependencies**: [TASK-011, TASK-010]
- **Files**:
  - `OpenOats/Sources/OpenOats/Detection/MeetingDetectionEngine.swift`
- **Acceptance Criteria**:
  - [ ] Timer starts when hardware deactivates (state: meetingEnding)
  - [ ] Timer duration reads from settings.silenceTimeoutMinutes (default 15, range 5-60)
  - [ ] Timer resets if hardware reactivates before timeout
  - [ ] finalizeMeeting() called on timeout completion
  - [ ] Timer invalidates on stop() or userStoppedRecording()
  - [ ] All TASK-011 tests now pass (GREEN phase)

---

## TASK-013: Write Tests for Notification Handling
- **Complexity**: M
- **Wave**: 2
- **Dependencies**: [TASK-001]
- **Files**:
  - `OpenOats/Tests/OpenOatsTests/Detection/NotificationHandlingTests.swift`
- **Acceptance Criteria**:
  - [ ] Test notification sent with app name and "Start transcribing?" prompt
  - [ ] Test notification has 3 actions: Start Recording, Not Now, Always Ignore
  - [ ] Test ACCEPT_MEETING action calls userAcceptedMeeting()
  - [ ] Test DECLINE_MEETING action calls userDeclinedMeeting()
  - [ ] Test IGNORE_APP action calls markAsNotMeeting()
  - [ ] Test notification appears even when app is in foreground
  - [ ] All tests fail before implementation (RED phase)

---

## TASK-014: Implement Notification Handling
- **Complexity**: M
- **Wave**: 2
- **Dependencies**: [TASK-013, TASK-010]
- **Files**:
  - `OpenOats/Sources/OpenOats/Detection/MeetingDetectionEngine.swift`
- **Acceptance Criteria**:
  - [ ] UNUserNotificationCenter category registered with 3 actions
  - [ ] Notification content shows app name from RunningMeetingApp
  - [ ] Notification body: "Start transcribing?"
  - [ ] UNUserNotificationCenterDelegate handles all action identifiers
  - [ ] Notification presents when app is foreground (willPresent delegate)
  - [ ] All TASK-013 tests now pass (GREEN phase)

---

## TASK-015: Write Tests for AppCoordinator Integration
- **Complexity**: M
- **Wave**: 3
- **Dependencies**: [TASK-001, TASK-009]
- **Files**:
  - `OpenOats/Tests/OpenOatsTests/Detection/AppCoordinatorIntegrationTests.swift`
- **Acceptance Criteria**:
  - [ ] Test userAcceptedMeeting() calls coordinator.userAcceptedMeetingDetection()
  - [ ] Test userAcceptedMeeting() triggers onRequestStartRecording callback
  - [ ] Test finalizeMeeting() calls onRequestStopRecording callback
  - [ ] Test engine receives SettingsStore and AppCoordinator on init
  - [ ] Test session state synchronized between engine and coordinator
  - [ ] All tests fail before implementation (RED phase)

---

## TASK-016: Implement AppCoordinator Integration
- **Complexity**: M
- **Wave**: 3
- **Dependencies**: [TASK-015, TASK-014, TASK-012]
- **Files**:
  - `OpenOats/Sources/OpenOats/App/AppCoordinator.swift`
  - `OpenOats/Sources/OpenOats/Detection/MeetingDetectionEngine.swift`
- **Acceptance Criteria**:
  - [ ] AppCoordinator.initializeMeetingDetection() creates engine with dependencies
  - [ ] userAcceptedMeetingDetection() starts recording session via onRequestStartRecording
  - [ ] finalizeMeeting() stops recording via coordinator.finalizeSession()
  - [ ] Session state (isRecording) synchronized between engine and coordinator
  - [ ] All TASK-015 tests now pass (GREEN phase)

---

## TASK-017: Write Tests for Ignored Apps Feature
- **Complexity**: M
- **Wave**: 3
- **Dependencies**: [TASK-001]
- **Files**:
  - `OpenOats/Tests/OpenOatsTests/Detection/IgnoredAppsTests.swift`
- **Acceptance Criteria**:
  - [ ] Test ignored apps trigger no notifications
  - [ ] Test markAsNotMeeting() adds bundle ID to ignoredAppBundleIDs
  - [ ] Test ignored apps list persisted via SettingsStore
  - [ ] Test removing app from ignored list restores notifications
  - [ ] Test SettingsView shows ignored apps list
  - [ ] All tests fail before implementation (RED phase)

---

## TASK-018: Implement Ignored Apps Integration
- **Complexity**: M
- **Wave**: 3
- **Dependencies**: [TASK-017, TASK-010]
- **Files**:
  - `OpenOats/Sources/OpenOats/Detection/MeetingDetectionEngine.swift`
  - `OpenOats/Sources/OpenOats/Views/SettingsView.swift`
- **Acceptance Criteria**:
  - [ ] Engine checks settings.ignoredAppBundleIDs before notifying
  - [ ] markAsNotMeeting() persists to settings.ignoredAppBundleIDs
  - [ ] Ignored apps list visible in Settings UI
  - [ ] User can remove apps from ignored list in Settings
  - [ ] All TASK-017 tests now pass (GREEN phase)

---

## TASK-019: Write Tests for False Positive Reduction (Confidence Scoring)
- **Complexity**: L
- **Wave**: 3
- **Dependencies**: [TASK-001]
- **Files**:
  - `OpenOats/Tests/OpenOatsTests/Detection/ConfidenceScoringTests.swift`
- **Acceptance Criteria**:
  - [ ] Test confidence 0.3 when only app is running (no hardware)
  - [ ] Test confidence 0.7 when app + camera active
  - [ ] Test confidence 1.0 when app + camera + mic active
  - [ ] Test notification only fires when confidence >= 0.7
  - [ ] Test debouncing: 5+ seconds of hardware activity before notification
  - [ ] Test camera-only apps (Photo Booth) get 0.3 confidence
  - [ ] All tests fail before implementation (RED phase)

---

## TASK-020: Implement Confidence Scoring and Debouncing
- **Complexity**: L
- **Wave**: 3
- **Dependencies**: [TASK-019, TASK-014]
- **Files**:
  - `OpenOats/Sources/OpenOats/Detection/MeetingDetectionEngine.swift`
- **Acceptance Criteria**:
  - [ ] Confidence calculated: appOnly=0.3, app+camera=0.7, app+camera+mic=1.0
  - [ ] Debounce timer: 5 seconds of sustained hardware activity
  - [ ] Notification only sent when confidence >= 0.7 AND debounce elapsed
  - [ ] Camera-only usage (Photo Booth) filtered by low confidence
  - [ ] All TASK-019 tests now pass (GREEN phase)

---

## TASK-021: Write Tests for Detection State Visibility
- **Complexity**: S
- **Wave**: 3
- **Dependencies**: [TASK-001, TASK-009]
- **Files**:
  - `OpenOats/Tests/OpenOatsTests/Detection/StateVisibilityTests.swift`
- **Acceptance Criteria**:
  - [ ] Test state property shows: Idle, Monitoring, Meeting Detected, etc.
  - [ ] Test state is @Published for SwiftUI observation
  - [ ] Test detection log enabled writes to Logger with correct subsystem
  - [ ] All tests fail before implementation (RED phase)

---

## TASK-022: Implement Detection State Visibility
- **Complexity**: S
- **Wave**: 3
- **Dependencies**: [TASK-021, TASK-020]
- **Files**:
  - `OpenOats/Sources/OpenOats/Detection/MeetingDetectionEngine.swift`
  - `OpenOats/Sources/OpenOats/Views/SettingsView.swift`
- **Acceptance Criteria**:
  - [ ] DetectionState enum has displayName for UI
  - [ ] @Published state property observable by SwiftUI
  - [ ] Optional status shown in Settings or ContentView
  - [ ] detectionLogEnabled writes to Logger(subsystem: "com.opengranola.app")
  - [ ] All TASK-021 tests now pass (GREEN phase)

---

## TASK-023: Write Tests for App Termination Handling
- **Complexity**: M
- **Wave**: 3
- **Dependencies**: [TASK-001, TASK-004]
- **Files**:
  - `OpenOats/Tests/OpenOatsTests/Detection/AppTerminationTests.swift`
- **Acceptance Criteria**:
  - [ ] Test app termination during awaitingUserResponse resets to monitoring
  - [ ] Test app termination during recording finalizes session immediately
  - [ ] Test app termination during meetingEnding finalizes session immediately
  - [ ] Test onAppTerminated callback received from MeetingAppMonitor
  - [ ] All tests fail before implementation (RED phase)

---

## TASK-024: Implement App Termination Handling
- **Complexity**: M
- **Wave**: 3
- **Dependencies**: [TASK-023, TASK-022]
- **Files**:
  - `OpenOats/Sources/OpenOats/Detection/MeetingDetectionEngine.swift`
- **Acceptance Criteria**:
  - [ ] handleAppTerminated() resets state to monitoring if awaitingUserResponse
  - [ ] handleAppTerminated() calls finalizeMeeting() if recording
  - [ ] handleAppTerminated() calls finalizeMeeting() if meetingEnding
  - [ ] Proper cleanup of currentMeetingApp reference
  - [ ] All TASK-023 tests now pass (GREEN phase)

---

## TASK-025: Write End-to-End Integration Tests
- **Complexity**: L
- **Wave**: 3
- **Dependencies**: [TASK-008, TASK-015, TASK-023]
- **Files**:
  - `OpenOats/Tests/OpenOatsTests/Detection/EndToEndDetectionTests.swift`
- **Acceptance Criteria**:
  - [ ] Test full flow: app launch → hardware active → notification → user accept → recording
  - [ ] Test full flow: recording → hardware inactive → timeout → session finalize
  - [ ] Test full flow: app launch → hardware active → user decline → no recording
  - [ ] Test full flow: Photo Booth camera only → no notification (false positive rejected)
  - [ ] Test settings change (disable auto-detect) → monitoring stops
  - [ ] All tests pass with fully integrated system

---

## TASK-026: Verify Privacy-First Implementation
- **Complexity**: S
- **Wave**: 3
- **Dependencies**: [TASK-025]
- **Files**:
  - `OpenOats/Sources/OpenOats/Detection/MeetingAppMonitor.swift` (verify)
- **Acceptance Criteria**:
  - [ ] No audio or video data captured during detection phase
  - [ ] Only lockForConfiguration() used to detect usage (no media streams)
  - [ ] Privacy explanation shown in onboarding (hasShownCameraDetectExplanation check)
  - [ ] Detection can be disabled via meetingAutoDetectEnabled toggle
  - [ ] REQ-009 fully satisfied

---

## TASK-027: Add Detection Settings UI Verification
- **Complexity**: S
- **Wave**: 3
- **Dependencies**: [TASK-025]
- **Files**:
  - `OpenOats/Sources/OpenOats/Views/SettingsView.swift` (verify)
- **Acceptance Criteria**:
  - [ ] meetingAutoDetectEnabled toggle exists and works
  - [ ] silenceTimeoutMinutes picker exists (5-60 range)
  - [ ] ignoredAppBundleIDs management UI exists
  - [ ] customMeetingAppBundleIDs management UI exists
  - [ ] detectionLogEnabled toggle exists
  - [ ] Settings changes take effect without app restart

---

## Dependency Graph

```
TASK-001 (Mocks)
    ├── TASK-002 (Monitor Hardware Tests)
    │       └── TASK-003 (Monitor Hardware Impl)
    │               └── TASK-008 (Integration Tests Wave 1)
    ├── TASK-004 (Monitor Lifecycle Tests)
    │       └── TASK-005 (Monitor Lifecycle Impl)
    │               └── TASK-008
    ├── TASK-006 (Registry Tests)
    │       └── TASK-007 (Registry Verify)
    │               └── TASK-008
    ├── TASK-011 (Timeout Tests)
    │       └── TASK-012 (Timeout Impl)
    ├── TASK-013 (Notification Tests)
    │       └── TASK-014 (Notification Impl)
    ├── TASK-015 (Coordinator Tests)
    │       └── TASK-016 (Coordinator Impl)
    ├── TASK-017 (Ignored Apps Tests)
    │       └── TASK-018 (Ignored Apps Impl)
    ├── TASK-019 (Confidence Tests)
    │       └── TASK-020 (Confidence Impl)
    ├── TASK-021 (Visibility Tests)
    │       └── TASK-022 (Visibility Impl)
    └── TASK-023 (Termination Tests)
            └── TASK-024 (Termination Impl)

TASK-008
    └── TASK-009 (State Machine Tests)
            └── TASK-010 (State Machine Impl)
                    └── TASK-016, TASK-018, TASK-020, TASK-022, TASK-024
                            └── TASK-025 (End-to-End Tests)
                                    └── TASK-026, TASK-027 (Verification)
```

## Files Likely Affected

### New Files (16)
1. `OpenOats/Sources/OpenOats/Detection/Mocks/MockAVCaptureDevice.swift`
2. `OpenOats/Sources/OpenOats/Detection/Mocks/MockNSWorkspace.swift`
3. `OpenOats/Sources/OpenOats/Detection/Mocks/MockSettingsStore.swift`
4. `OpenOats/Sources/OpenOats/Detection/Mocks/MockUNUserNotificationCenter.swift`
5. `OpenOats/Sources/OpenOats/Detection/Mocks/MockAppCoordinator.swift`
6. `OpenOats/Sources/OpenOats/Detection/Mocks/StubTimer.swift`
7. `OpenOats/Tests/OpenOatsTests/Detection/MeetingAppMonitorTests.swift`
8. `OpenOats/Tests/OpenOatsTests/Detection/MeetingAppRegistryTests.swift`
9. `OpenOats/Tests/OpenOatsTests/Detection/MeetingAppMonitorIntegrationTests.swift`
10. `OpenOats/Tests/OpenOatsTests/Detection/MeetingDetectionEngineTests.swift`
11. `OpenOats/Tests/OpenOatsTests/Detection/SilenceTimeoutTests.swift`
12. `OpenOats/Tests/OpenOatsTests/Detection/NotificationHandlingTests.swift`
13. `OpenOats/Tests/OpenOatsTests/Detection/AppCoordinatorIntegrationTests.swift`
14. `OpenOats/Tests/OpenOatsTests/Detection/IgnoredAppsTests.swift`
15. `OpenOats/Tests/OpenOatsTests/Detection/ConfidenceScoringTests.swift`
16. `OpenOats/Tests/OpenOatsTests/Detection/EndToEndDetectionTests.swift`

### Modified Files (5)
1. `OpenOats/Sources/OpenOats/Detection/MeetingAppMonitor.swift`
2. `OpenOats/Sources/OpenOats/Detection/MeetingDetectionEngine.swift`
3. `OpenOats/Sources/OpenOats/App/AppCoordinator.swift`
4. `OpenOats/Sources/OpenOats/Views/SettingsView.swift`
5. `OpenOats/Sources/OpenOats/OpenOatsApp.swift` (if needed for initialization)

## Total Estimated Hours

| Wave | Tasks | Estimated Hours |
|------|-------|-----------------|
| Wave 1: Core Detection | 8 tasks | 20 hours |
| Wave 2: Engine State Machine | 6 tasks | 18 hours |
| Wave 3: Integration & Polish | 13 tasks | 28 hours |
| **Total** | **27 tasks** | **66 hours** |

## Risk Mitigation Tasks

Based on BA risk analysis:
- **RISK-001** (False negatives): Addressed by TASK-003 hardware detection + TASK-020 confidence scoring
- **RISK-002** (False positives): Addressed by TASK-019/TASK-020 confidence + debouncing
- **RISK-003** (Battery/CPU): Addressed by TASK-002/TASK-003 2-second polling + <5% CPU requirement
- **RISK-004** (Permissions): Addressed by TASK-026 privacy-first verification
- **RISK-005** (Legal compliance): Addressed by REQ-016 WONT + explicit user confirmation flow
- **RISK-007** (App updates): Addressed by TASK-007 extensible registry + custom bundle IDs
