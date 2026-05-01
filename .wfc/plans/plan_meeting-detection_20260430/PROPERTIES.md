# Meeting Detection Formal Properties

## Overview

This document specifies formal properties for the meeting detection system using SAFETY, LIVENESS, and INVARIANT patterns. These properties are verifiable through unit tests, integration tests, and runtime assertions.

## Property Categories

---

## SAFETY Properties (Nothing Bad Happens)

### SAFETY-001: Never Auto-Start Recording
**Formal Statement:**
```
□(¬recordingStartedAutomatically)
```
**Always:** Recording is never started without explicit user confirmation.

**Rationale:**
Legal compliance requirement (REQ-016 WONT). Auto-recording would violate two-party consent laws in many jurisdictions. User must explicitly opt-in per session.

**Priority:** Critical

**Verification:**
- Unit test: verify engine never calls onRequestStartRecording without user action
- Integration test: simulate full detection flow, verify recording only after notification action
- Runtime: log warning if startRecording called outside user action context

**Observable:**
- `state` transitions from `awaitingUserResponse` → `recording` only via `userAcceptedMeeting()`
- No direct path from `monitoring` or `meetingDetected` to `recording`

---

### SAFETY-002: Privacy-First Hardware Detection
**Formal Statement:**
```
□(detectionPhase → ¬audioCaptured ∧ ¬videoCaptured)
```
**Always:** During detection phase, no audio or video data is captured.

**Rationale:**
Privacy requirement (REQ-009). Detection only checks if hardware is in use via lock status, never accesses media streams. This is a key differentiator from cloud-based competitors.

**Priority:** Critical

**Verification:**
- Code review: no AVCaptureSession, no audio buffers in MeetingAppMonitor
- Unit test: verify only `lockForConfiguration()` is called
- Runtime: assert no media stream APIs invoked during detection

**Observable:**
- `checkMediaDeviceUsage()` only uses lock/unlock pattern
- No `AVCaptureSession.startRunning()` calls in detection code

---

### SAFETY-003: Ignored Apps Never Trigger Notifications
**Formal Statement:**
```
□(bundleID ∈ ignoredAppBundleIDs → ¬notificationSent(bundleID))
```
**Always:** Apps in the ignored list never trigger detection notifications.

**Rationale:**
User experience requirement (REQ-008, US-002). Prevents repeated false positives from apps like Photo Booth that user has marked as "not a meeting".

**Priority:** High

**Verification:**
- Unit test: add bundle ID to ignored list, verify no notification
- Integration test: simulate ignored app with hardware active, verify silent handling

**Observable:**
- `settings.ignoredAppBundleIDs.contains(app.bundleID)` checked before `sendMeetingDetectedNotification()`

---

### SAFETY-004: Silence Timeout Respects User Settings
**Formal Statement:**
```
□(silenceTimerDuration = silenceTimeoutMinutes × 60 seconds)
```
**Always:** Silence timeout duration exactly matches user-configured setting.

**Rationale:**
User control requirement (REQ-004). Timeout must be configurable (default 15, range 5-60) and changes take effect immediately.

**Priority:** High

**Verification:**
- Unit test: verify timer created with correct duration from settings
- Integration test: change setting mid-session, verify new timeout applies

**Observable:**
- `startSilenceTimeout()` reads `settings.silenceTimeoutMinutes`
- Timer interval calculation: `Double(timeoutMinutes) * 60`

---

### SAFETY-005: No Session Data Loss on App Termination
**Formal Statement:**
```
□(recordingState ∧ appTerminationDetected → sessionFinalized ∨ sessionContinuing)
```
**Always:** If app terminates during recording, session is either finalized properly or continues safely.

**Rationale:**
Data integrity requirement (REQ-007). User's transcript data must not be lost if meeting app crashes or is force-quit.

**Priority:** High

**Verification:**
- Unit test: simulate app termination during recording, verify finalize called
- Integration test: full flow with simulated termination

**Observable:**
- `handleAppTerminated()` calls `finalizeMeeting()` if state == `.recording`
- Session store receives finalize before state reset

---

### SAFETY-006: Settings Changes Applied Without Restart
**Formal Statement:**
```
□(settingsChange → ◇(newBehaviorEffective ∧ ¬appRestartRequired))
```
**Always:** Settings changes eventually take effect without requiring app restart.

**Rationale:**
User experience requirement (REQ-005). Detection enable/disable, timeout changes, and ignored apps updates must be dynamic.

**Priority:** Medium

**Verification:**
- Unit test: toggle meetingAutoDetectEnabled, verify engine stops/starts
- Unit test: change silenceTimeoutMinutes, verify new timeout used

**Observable:**
- Settings use `@Observable` pattern
- Engine observes settings changes via `@Published` properties

---

## LIVENESS Properties (Something Good Eventually Happens)

### LIVENESS-001: Meeting Detection Eventually Notifies
**Formal Statement:**
```
(meetingAppRunning ∧ hardwareActive ∧ confidence ≥ 0.7 ∧ ¬ignored) → ◇notificationSent
```
**Eventually:** When a non-ignored meeting app has hardware active with sufficient confidence, a notification is sent.

**Rationale:**
Core feature requirement (REQ-003, US-001). The system must reliably detect meetings and notify the user within 5 seconds.

**Priority:** Critical

**Verification:**
- Integration test: simulate Zoom + camera/mic, verify notification within 5 seconds
- Load test: verify notification under CPU load

**Observable:**
- `handleMeetingStarted()` called → `sendMeetingDetectedNotification()` executed
- UNNotificationRequest created with category "MEETING_DETECTED"

---

### LIVENESS-002: User Response Eventually Recorded
**Formal Statement:**
```
(notificationSent ∧ userAccepts) → ◇recordingStarted
```
**Eventually:** When user accepts meeting notification, recording eventually starts.

**Rationale:**
User story requirement (US-001). The "Start Recording" action must trigger transcription within 1 second.

**Priority:** Critical

**Verification:**
- Unit test: call `userAcceptedMeeting()`, verify state → `.recording`
- Unit test: verify `onRequestStartRecording` callback fired
- Integration test: end-to-end acceptance to recording state

**Observable:**
- `state` transitions to `.recording`
- `onRequestStartRecording?()` callback invoked
- `coordinator.isRecording` becomes true

---

### LIVENESS-003: Silence Eventually Ends Session
**Formal Statement:**
```
(recordingState ∧ hardwareInactiveFor(silenceTimeout)) → ◇sessionFinalized
```
**Eventually:** When hardware is inactive for the configured silence timeout, session is finalized.

**Rationale:**
Automation requirement (REQ-004, US-004). Prevents recording hours of post-meeting audio.

**Priority:** High

**Verification:**
- Unit test: stub timer fires, verify `finalizeMeeting()` called
- Integration test: simulate 15-minute silence, verify session ends

**Observable:**
- `silenceTimeoutReached()` called after timer fires
- `finalizeSession()` invoked on coordinator
- State returns to `.monitoring`

---

### LIVENESS-004: Debouncing Eventually Clears
**Formal Statement:**
```
(hardwareActive ∧ sustainedActivity(5s)) → ◇meetingDetectionConfirmed
```
**Eventually:** After 5 seconds of sustained hardware activity, meeting detection is confirmed.

**Rationale:**
False positive reduction (REQ-011). Short camera/mic usage (accidental activation) should not trigger notification.

**Priority:** High

**Verification:**
- Unit test: 4 seconds hardware active → no notification
- Unit test: 6 seconds hardware active → notification sent
- Uses StubTimer for controllable testing

**Observable:**
- Debounce timer tracks sustained activity
- `confidence >= 0.7` check after debounce completes

---

### LIVENESS-005: Polling Eventually Detects State Changes
**Formal Statement:**
```
□(hardwareStateChange → ◇(detectionWithin(2s)))
```
**Globally:** Hardware state changes are detected within 2 seconds.

**Rationale:**
Performance requirement (REQ-001). 2-second polling interval balances responsiveness with battery/CPU impact.

**Priority:** Medium

**Verification:**
- Unit test: verify `checkHardwareUsage()` called every 2.0 seconds
- Performance test: CPU usage < 5% during polling

**Observable:**
- `Timer.scheduledTimer(withTimeInterval: 2.0, ...)`
- Logger shows polling activity at 2s intervals

---

## INVARIANT Properties (Always True)

### INVARIANT-001: State Machine Validity
**Formal Statement:**
```
□(state ∈ ValidStates ∧ transitions ⊆ ValidTransitions)
```
**Always:** Detection state is always one of the valid states, and transitions follow valid edges.

**Valid States:**
- `.idle`
- `.monitoring`
- `.meetingDetected`
- `.awaitingUserResponse`
- `.recording`
- `.meetingEnding`

**Valid Transitions:**
```
idle → monitoring (on start())
monitoring → meetingDetected (on meeting started)
meetingDetected → awaitingUserResponse (on notification sent)
awaitingUserResponse → recording (on user accepted)
awaitingUserResponse → monitoring (on user declined/app terminated)
recording → meetingEnding (on hardware inactive)
meetingEnding → monitoring (on silence timeout)
any → idle (on stop())
```

**Priority:** Critical

**Verification:**
- Unit test: verify all invalid transitions rejected
- State machine fuzzing: random event sequences

**Observable:**
- `state` property type-safe via `DetectionState` enum
- State changes logged with `logger.info("State: \(state.displayName)")`

---

### INVARIANT-002: Single Active Meeting Session
**Formal Statement:**
```
□(recordingState → (currentMeetingApp ≠ nil ∧ singleSessionActive))
```
**Always:** When recording, there is exactly one tracked meeting app.

**Rationale:**
Scope requirement (REQ-015 WONT). System handles one meeting at a time; subsequent apps ignored during active session.

**Priority:** High

**Verification:**
- Unit test: simulate second app launch during recording, verify ignored
- State machine test: verify no concurrent recording states

**Observable:**
- `currentMeetingApp` is Optional, only set during active session
- Second `onMeetingStarted` callback ignored if `state != .monitoring`

---

### INVARIANT-003: Notification Actions Always Available
**Formal Statement:**
```
□(notificationCategoryRegistered → actions = [start, decline, ignore])
```
**Always:** Meeting detected notification category always has all 3 actions.

**Rationale:**
UX requirement (REQ-003). User must have full choice: start recording, decline once, or ignore permanently.

**Priority:** High

**Verification:**
- Unit test: verify UNNotificationCategory has 3 actions
- UI test: verify all buttons present in notification

**Observable:**
- `UNNotificationCategory(identifier: "MEETING_DETECTED", actions: [acceptAction, declineAction, ignoreAction], ...)`
- Action identifiers: `ACCEPT_MEETING`, `DECLINE_MEETING`, `IGNORE_APP`

---

### INVARIANT-004: Confidence Calculation Correctness
**Formal Statement:**
```
□(confidence = f(appRunning, cameraActive, micActive))
where:
  app only = 0.3
  app + camera = 0.7
  app + camera + mic = 1.0
  else = 0.0
```
**Always:** Confidence score calculated correctly based on signals.

**Rationale:**
False positive reduction (REQ-011). Confidence scoring must be deterministic and accurate.

**Priority:** Medium

**Verification:**
- Unit test: verify all 4 confidence levels
- Property-based test: random input combinations

**Observable:**
- `calculateConfidence()` method returns correct value
- Only confidence >= 0.7 triggers notification

---

### INVARIANT-005: Settings Store Synchronization
**Formal Statement:**
```
□(settingsChange → settingsPersisted ∧ engineNotified)
```
**Always:** Settings changes are persisted and detection engine is notified.

**Rationale:**
Consistency requirement (REQ-005). Settings must be durable and reactive.

**Priority:** Medium

**Verification:**
- Unit test: change setting, verify UserDefaults updated
- Unit test: verify engine callback fired on settings change

**Observable:**
- `SettingsStore` uses `@Observable` with `@ObservationIgnored` backing
- UserDefaults keys: `meetingAutoDetectEnabled`, `silenceTimeoutMinutes`, etc.

---

### INVARIANT-006: Logger Subsystem Consistency
**Formal Statement:**
```
□(detectionLogEnabled → loggerSubsystem = "com.opengranola.app")
```
**Always:** Detection logging uses consistent subsystem for filtering.

**Rationale:**
Debuggability requirement (US-005). Users can view detection logs in Console app.

**Priority:** Low

**Verification:**
- Code review: all detection loggers use `Logger(subsystem: "com.opengranola.app", ...)`
- Log inspection: verify subsystem consistency

**Observable:**
- `Logger(subsystem: "com.opengranola.app", category: "MeetingDetectionEngine")`
- `Logger(subsystem: "com.opengranola.app", category: "MeetingAppMonitor")`

---

## Performance Properties

### PERFORMANCE-001: CPU Usage Bound
**Formal Statement:**
```
□(cpuUsageDuringPolling < 5%)
```
**Always:** Hardware polling consumes less than 5% CPU.

**Rationale:**
Battery/performance requirement (REQ-001, RISK-003).

**Priority:** High

**Verification:**
- Performance test: measure CPU during 60s polling
- Assert average < 5%, peaks < 10%

---

### PERFORMANCE-002: Notification Latency Bound
**Formal Statement:**
```
□(detectionToNotificationLatency < 5s)
```
**Always:** Time from hardware activation to notification is under 5 seconds.

**Rationale:**
UX requirement (US-001). User expects near-instant notification.

**Priority:** High

**Verification:**
- Integration test: measure end-to-end latency
- Assert p95 < 5s, p99 < 8s

---

### PERFORMANCE-003: State Transition Latency
**Formal Statement:**
```
□(userActionToStateChange < 1s)
```
**Always:** State changes (accept/decline) apply within 1 second.

**Rationale:**
Responsiveness requirement. UI must feel immediate.

**Priority:** Medium

**Verification:**
- Unit test: measure time from `userAcceptedMeeting()` to state change
- Assert < 1s on target hardware

---

## Traceability Matrix

| Property | REQ | Test File | Test Count |
|----------|-----|-----------|------------|
| SAFETY-001 | REQ-016 | MeetingDetectionEngineTests.swift | 2 |
| SAFETY-002 | REQ-009 | MeetingAppMonitorTests.swift | 3 |
| SAFETY-003 | REQ-008 | IgnoredAppsTests.swift | 4 |
| SAFETY-004 | REQ-004 | SilenceTimeoutTests.swift | 3 |
| SAFETY-005 | REQ-007 | AppTerminationTests.swift | 3 |
| SAFETY-006 | REQ-005 | MeetingDetectionEngineTests.swift | 2 |
| LIVENESS-001 | REQ-003 | MeetingAppMonitorIntegrationTests.swift | 2 |
| LIVENESS-002 | REQ-003 | AppCoordinatorIntegrationTests.swift | 2 |
| LIVENESS-003 | REQ-004 | SilenceTimeoutTests.swift | 2 |
| LIVENESS-004 | REQ-011 | ConfidenceScoringTests.swift | 2 |
| LIVENESS-005 | REQ-001 | MeetingAppMonitorTests.swift | 1 |
| INVARIANT-001 | REQ-003 | MeetingDetectionEngineTests.swift | 8 |
| INVARIANT-002 | REQ-015 | MeetingDetectionEngineTests.swift | 1 |
| INVARIANT-003 | REQ-003 | NotificationHandlingTests.swift | 3 |
| INVARIANT-004 | REQ-011 | ConfidenceScoringTests.swift | 4 |
| INVARIANT-005 | REQ-005 | MeetingDetectionEngineTests.swift | 2 |
| INVARIANT-006 | REQ-012 | MeetingAppMonitorTests.swift | 1 |

## Property Verification Strategy

### Unit Tests (Properties per Component)
- **MeetingAppMonitor**: SAFETY-002, LIVENESS-005, INVARIANT-006
- **MeetingDetectionEngine**: SAFETY-001, SAFETY-003, SAFETY-004, SAFETY-005, SAFETY-006, LIVENESS-001, LIVENESS-002, LIVENESS-003, LIVENESS-004, INVARIANT-001, INVARIANT-002, INVARIANT-004, INVARIANT-005
- **AppCoordinator**: LIVENESS-002, SAFETY-005
- **NotificationHandler**: INVARIANT-003, LIVENESS-001

### Integration Tests (Cross-Component Properties)
- End-to-End Detection: LIVENESS-001, LIVENESS-002, LIVENESS-003
- False Positive Prevention: SAFETY-003, LIVENESS-004, INVARIANT-004
- Settings Integration: SAFETY-004, SAFETY-006, INVARIANT-005

### Runtime Assertions (Debug Builds)
- State machine validity: INVARIANT-001
- Confidence bounds: INVARIANT-004
- Single session: INVARIANT-002

### Performance Tests
- CPU monitoring: PERFORMANCE-001
- Latency measurement: PERFORMANCE-002, PERFORMANCE-003
