# TASKS.md: Meeting Start/End Detection for OpenOats

**Feature:** Automatic Meeting Detection  
**Created:** 2026-04-30  
**Source:** ba-output.json (4 MUST, 2 SHOULD, 2 COULD, 1 WONT)  
**Complexity:** Medium  

## Execution Waves

| Wave | Tasks | Description |
|------|-------|-------------|
| Wave 1 | TASK-001, TASK-002 | Foundation - Settings infrastructure |
| Wave 2 | TASK-003, TASK-004, TASK-005 | Core detection engine |
| Wave 3 | TASK-006, TASK-007, TASK-008 | UI integration and manual controls |
| Wave 4 | TASK-009, TASK-010 | Polish - Privacy indicators and false positive reduction |

## Wave 1: Foundation

### TASK-001: Add meeting detection settings to AppSettings model
- **Complexity**: S
- **Wave**: 1
- **Dependencies**: []
- **Canary**: true
- **Files**: ["OpenOats/Sources/OpenOats/Settings/AppSettings.swift"]
- **Acceptance Criteria**:
  - [ ] `meetingDetectionEnabled: Bool` property added with UserDefaults backing
  - [ ] `meetingDetectionSensitivity: DetectionSensitivity` enum property added (values: low, medium, high)
  - [ ] `meetingEndSilenceDuration: TimeInterval` property added with default 30.0
  - [ ] `manualOverrideEnabled: Bool` property added with default true
  - [ ] All properties have didSet handlers to persist to UserDefaults
  - [ ] `DetectionSensitivity` enum conforms to `String, CaseIterable, Identifiable`

---

### TASK-002: Create MeetingDetectionSettings enum types
- **Complexity**: S
- **Wave**: 1
- **Dependencies**: [TASK-001]
- **Canary**: false
- **Files**: ["OpenOats/Sources/OpenOats/Settings/SettingsTypes.swift"]
- **Acceptance Criteria**:
  - [ ] `DetectionSensitivity` enum added with cases: low, medium, high
  - [ ] `displayName` computed property returns user-friendly strings
  - [ ] `vadThreshold: Float` computed property returns appropriate thresholds (low: 0.3, medium: 0.5, high: 0.7)
  - [ ] `SilenceDuration` enum added with preset values: tenSeconds(10), thirtySeconds(30), oneMinute(60), fiveMinutes(300)
  - [ ] `displayName` computed property returns formatted strings ("10 seconds", "30 seconds", etc.)

---

## Wave 2: Core Detection Engine

### TASK-003: Create MeetingDetectionEngine actor
- **Complexity**: M
- **Wave**: 2
- **Dependencies**: [TASK-001, TASK-002]
- **Canary**: false
- **Files**: ["OpenOats/Sources/OpenOats/Audio/MeetingDetectionEngine.swift"]
- **Acceptance Criteria**:
  - [ ] New file `MeetingDetectionEngine.swift` created in Audio folder
  - [ ] `@Observable @MainActor final class MeetingDetectionEngine` declared
  - [ ] `isDetectionActive: Bool` published property
  - [ ] `meetingState: MeetingState` enum published property (idle, detecting, inMeeting, ending)
  - [ ] `startDetection()` method initiates monitoring
  - [ ] `stopDetection()` method halts monitoring
  - [ ] Uses `AudioDeviceID` from existing code for device selection

---

### TASK-004: Implement voice activity detection (VAD) integration
- **Complexity**: M
- **Wave**: 2
- **Dependencies**: [TASK-003]
- **Canary**: false
- **Files**: ["OpenOats/Sources/OpenOats/Audio/MeetingDetectionEngine.swift"]
- **Acceptance Criteria**:
  - [ ] `processAudioBuffer(_ buffer: AVAudioPCMBuffer)` method added
  - [ ] Uses existing `vadManager` from TranscriptionEngine pattern
  - [ ] Calculates RMS energy from buffer using existing `MicCapture.normalizedRMS`
  - [ ] Combines VAD confidence with energy threshold for speech detection
  - [ ] `isSpeechDetected: Bool` computed from buffer analysis
  - [ ] Respects sensitivity setting from AppSettings

---

### TASK-005: Implement meeting state machine with timers
- **Complexity**: M
- **Wave**: 2
- **Dependencies**: [TASK-003, TASK-004]
- **Canary**: false
- **Files**: ["OpenOats/Sources/OpenOats/Audio/MeetingDetectionEngine.swift"]
- **Acceptance Criteria**:
  - [ ] `startMeetingDetection()` triggers after sustained speech (>2 seconds)
  - [ ] `silenceTimer: Timer?` tracks consecutive silent buffers
  - [ ] Meeting end triggers after configured silence duration
  - [ ] State transitions: idle → detecting → inMeeting → ending → idle
  - [ ] `onMeetingStart: (() -> Void)?` callback property
  - [ ] `onMeetingEnd: (() -> Void)?` callback property
  - [ ] All timer invalidation handled properly in `stopDetection()`

---

## Wave 3: UI Integration and Manual Controls

### TASK-006: Add detection toggle to ControlBar
- **Complexity**: S
- **Wave**: 3
- **Dependencies**: [TASK-001, TASK-003]
- **Canary**: false
- **Files**: ["OpenOats/Sources/OpenOats/Views/ControlBar.swift"]
- **Acceptance Criteria**:
  - [ ] Auto-detect toggle button added to ControlBar when not recording
  - [ ] Toggle reflects `AppSettings.meetingDetectionEnabled`
  - [ ] Visual state shows when detection is active (pulsing icon)
  - [ ] Button disabled when transcription is manually running
  - [ ] Tooltip explains toggle function

---

### TASK-007: Create MeetingDetectionSettingsView
- **Complexity**: M
- **Wave**: 3
- **Dependencies**: [TASK-001, TASK-002]
- **Canary**: false
- **Files**: ["OpenOats/Sources/OpenOats/Views/MeetingDetectionSettingsView.swift"]
- **Acceptance Criteria**:
  - [ ] New SwiftUI view file created
  - [ ] Form with sections: General, Sensitivity, Silence Timeout
  - [ ] Toggle for `meetingDetectionEnabled`
  - [ ] Picker for `meetingDetectionSensitivity` with descriptive labels
  - [ ] Picker for `meetingEndSilenceDuration` with time options
  - [ ] Help text explaining each setting
  - [ ] Preview provider included

---

### TASK-008: Integrate detection settings into SettingsView
- **Complexity**: S
- **Wave**: 3
- **Dependencies**: [TASK-007]
- **Canary**: false
- **Files**: ["OpenOats/Sources/OpenOats/Views/SettingsView.swift"]
- **Acceptance Criteria**:
  - [ ] "Meeting Detection" section added to SettingsView
  - [ ] NavigationLink to MeetingDetectionSettingsView
  - [ ] Summary text showing current settings (e.g., "Auto-detect: On")
  - [ ] Maintains existing SettingsView layout and styling

---

## Wave 4: Privacy and Polish

### TASK-009: Add privacy indicators and menu bar controls
- **Complexity**: M
- **Wave**: 4
- **Dependencies**: [TASK-003, TASK-006]
- **Canary**: false
- **Files**: ["OpenOats/Sources/OpenOats/Audio/MeetingDetectionEngine.swift", "OpenOats/Sources/OpenOats/Views/ControlBar.swift"]
- **Acceptance Criteria**:
  - [ ] Visual indicator in ControlBar when detection is monitoring (not just active)
  - [ ] Status bar/menu bar icon option for detection state
  - [ ] Privacy badge/text showing "Listening for meetings..."
  - [ ] Quick-disable button accessible from main UI
  - [ ] Help tooltip explaining privacy protection (local processing only)

---

### TASK-010: Implement false positive reduction heuristics
- **Complexity**: M
- **Wave**: 4
- **Dependencies**: [TASK-004, TASK-005]
- **Canary**: false
- **Files**: ["OpenOats/Sources/OpenOats/Audio/MeetingDetectionEngine.swift"]
- **Acceptance Criteria**:
  - [ ] Ignore utterances shorter than 2 seconds for meeting start
  - [ ] Track speech duration counter in detection state
  - [ ] Require minimum 3 seconds of continuous speech before triggering start
  - [ ] Background noise filtering via VAD confidence threshold
  - [ ] `consecutiveSpeechBuffers: Int` counter for validation
  - [ ] Reset counter on significant silence gaps (>1 second)

---

## Dependency Graph

```
TASK-001 (Settings model)
    └── TASK-002 (Enum types)
            └── TASK-003 (DetectionEngine)
                    ├── TASK-004 (VAD integration)
                    │       └── TASK-010 (False positive reduction)
                    └── TASK-005 (State machine)
                            ├── TASK-006 (ControlBar toggle)
                            └── TASK-009 (Privacy indicators)
            ├── TASK-007 (SettingsView)
                    └── TASK-008 (Settings integration)
```

## Acceptance Criteria Summary

| Task | Criteria Count | Verification Method |
|------|---------------|---------------------|
| TASK-001 | 6 | grep property definitions |
| TASK-002 | 5 | grep enum cases |
| TASK-003 | 7 | grep class definition |
| TASK-004 | 6 | grep method signatures |
| TASK-005 | 7 | grep state transitions |
| TASK-006 | 5 | grep button/toggle code |
| TASK-007 | 7 | grep view body content |
| TASK-008 | 4 | grep NavigationLink |
| TASK-009 | 5 | grep privacy indicators |
| TASK-010 | 6 | grep validation logic |

**Total Tasks:** 10  
**Estimated Effort:** 2-3 engineering days  
**Risk Areas:** TASK-004 (VAD accuracy), TASK-009 (privacy UX)
