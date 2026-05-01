# PROPERTIES.md: Meeting Detection Formal Properties

**Feature:** Automatic Meeting Detection  
**Created:** 2026-04-30  
**Related:** TASKS.md, ba-output.json  

## Safety Properties

### SAFETY-001: Never record without user consent
**Statement:** The system SHALL NOT start audio recording/transcription without explicit user action OR auto-detection with prior user opt-in.

**Rationale:** Privacy is paramount. Auto-detection must be opt-in, and manual controls must always override.

**Priority:** critical

**Observable:**
- `AppSettings.meetingDetectionEnabled` must be `true` for auto-detection
- `TranscriptionEngine.isRunning` must remain `false` until `start()` called
- Manual start button must work regardless of detection state

**Related Tasks:** TASK-001, TASK-004, TASK-006

---

### SAFETY-002: Never continue recording after meeting end detection
**Statement:** The system SHALL terminate transcription within 5 seconds of meeting end detection.

**Rationale:** Prevents accidental recording of post-meeting conversations.

**Priority:** critical

**Observable:**
- `MeetingDetectionEngine.meetingState` transition to `.ending` triggers stop
- `TranscriptionEngine.isRunning` becomes `false` within 5s of silence timeout
- Final transcript is saved before transcription stops

**Related Tasks:** TASK-005

---

### SAFETY-003: Visual indication of monitoring state
**Statement:** When detection is active, the system SHALL provide continuous visual indication of monitoring status.

**Rationale:** Users must always know when the app is listening for meetings.

**Priority:** high

**Observable:**
- UI element shows "Listening..." or equivalent when `MeetingDetectionEngine.isDetectionActive && meetingState == .detecting`
- Menu bar icon or badge reflects detection state

**Related Tasks:** TASK-006, TASK-009

---

## Liveness Properties

### LIVENESS-001: Meeting start detection within 5 seconds
**Statement:** If continuous speech (>2 seconds) occurs and detection is enabled, the system SHALL detect meeting start within 5 seconds.

**Rationale:** User expectation for responsive auto-detection.

**Priority:** high

**Observable:**
- Time between first speech buffer and `onMeetingStart` callback <= 5s
- `meetingState` transitions to `.inMeeting` within timeout

**Related Tasks:** TASK-004, TASK-005

---

### LIVENESS-002: Meeting end detection within silence timeout + 5 seconds
**Statement:** If silence persists for the configured duration, the system SHALL detect meeting end within (silenceDuration + 5) seconds.

**Rationale:** Timely meeting finalization without premature cutoff.

**Priority:** high

**Observable:**
- Timer accuracy: silence duration matches configured value
- `onMeetingEnd` callback fires within grace period
- Transcript is finalized and persisted

**Related Tasks:** TASK-005

---

### LIVENESS-003: Settings changes take effect immediately
**Statement:** Changes to detection settings SHALL take effect without requiring app restart.

**Rationale:** Fluid user experience for configuration tuning.

**Priority:** medium

**Observable:**
- Modifying `AppSettings.meetingDetectionSensitivity` affects next buffer processing
- Modifying `meetingEndSilenceDuration` updates active timer

**Related Tasks:** TASK-001, TASK-003

---

## Invariants

### INVARIANT-001: Manual controls always available
**Statement:** Manual start/stop controls MUST remain functional regardless of auto-detection state.

**Rationale:** User must retain ultimate control over recording.

**Priority:** critical

**Invariant:** `TranscriptionEngine.start()` and `stop()` are always callable and effective.

**Related Tasks:** TASK-006

---

### INVARIANT-002: Sensitivity settings bounded
**Statement:** Detection sensitivity thresholds MUST remain within valid bounds (0.0 - 1.0).

**Rationale:** Prevent invalid VAD configurations that break detection.

**Priority:** medium

**Invariant:** `DetectionSensitivity.vadThreshold` returns values in [0.0, 1.0]

**Related Tasks:** TASK-002

---

### INVARIANT-003: State machine consistency
**Statement:** `MeetingDetectionEngine.meetingState` MUST always be a valid state and transitions MUST follow the defined graph.

**Rationale:** Prevent undefined behavior from invalid state transitions.

**Priority:** high

**Invariant:**
- Valid states: `.idle`, `.detecting`, `.inMeeting`, `.ending`
- Valid transitions:
  - `.idle` → `.detecting` (when detection starts)
  - `.detecting` → `.inMeeting` (speech detected)
  - `.detecting` → `.idle` (detection stopped)
  - `.inMeeting` → `.ending` (silence timeout)
  - `.inMeeting` → `.idle` (manual stop)
  - `.ending` → `.idle` (cleanup complete)

**Related Tasks:** TASK-005

---

## Performance Properties

### PERFORMANCE-001: Audio buffer processing < 10ms
**Statement:** Audio buffer processing in `MeetingDetectionEngine` MUST complete within 10ms per buffer.

**Rationale:** Maintain real-time performance without audio dropouts.

**Target:** < 10ms p99 per buffer

**Related Tasks:** TASK-004

---

### PERFORMANCE-002: Battery impact < 5% per hour
**Statement:** Continuous detection monitoring MUST consume less than 5% battery per hour on modern MacBooks.

**Rationale:** User acceptance of background monitoring feature.

**Target:** < 5% battery/hour when idle monitoring

**Related Tasks:** TASK-003, TASK-004

---

### PERFORMANCE-003: Settings persistence < 100ms
**Statement:** Settings changes MUST persist to UserDefaults within 100ms.

**Rationale:** Responsive settings UI.

**Target:** < 100ms p99

**Related Tasks:** TASK-001

---

## Property Verification Matrix

| Property | Type | Priority | Test Approach | Coverage Task |
|----------|------|----------|---------------|---------------|
| SAFETY-001 | Safety | critical | Unit test + UI test | TEST-001 |
| SAFETY-002 | Safety | critical | Unit test + Integration | TEST-002 |
| SAFETY-003 | Safety | high | UI test | TEST-003 |
| LIVENESS-001 | Liveness | high | Performance test | TEST-004 |
| LIVENESS-002 | Liveness | high | Integration test | TEST-005 |
| LIVENESS-003 | Liveness | medium | Unit test | TEST-006 |
| INVARIANT-001 | Invariant | critical | Unit test | TEST-007 |
| INVARIANT-002 | Invariant | medium | Unit test | TEST-008 |
| INVARIANT-003 | Invariant | high | State machine test | TEST-009 |
| PERFORMANCE-001 | Performance | high | Benchmark | TEST-010 |
| PERFORMANCE-002 | Performance | medium | Battery profiling | TEST-011 |
| PERFORMANCE-003 | Performance | low | Unit test | TEST-012 |
