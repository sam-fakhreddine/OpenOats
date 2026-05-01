# TASKS.md: Base Branch Compilation Fixes

**Plan ID**: plan_base-branch-fixes_20260430_221736  
**Source**: PRD-base-branch-fixes.md (12 MUST requirements)  
**Goal**: Achieve zero compilation errors on feat/mlx-audio-and-model-storage branch  
**Estimated Duration**: 6 days (Phases 1-4)

---

## Execution Wave Summary

| Wave | Tasks | Theme | Exit Criteria |
|------|-------|-------|---------------|
| **Wave 1** | TASK-001 to TASK-003 | Foundation - Restore deleted types | Type-level errors resolved |
| **Wave 2** | TASK-004 to TASK-009 | AppSettings Architecture | View compilation errors resolved |
| **Wave 3** | TASK-010 to TASK-012 | MLX Integration | MLX-specific errors resolved |
| **Wave 4** | TASK-013 to TASK-015 | Validation & Cleanup | Clean build, tests pass |

---

## Wave 1: Foundation (Restore Deleted Types)

### TASK-001: Restore AppSecretStore Type
- **Wave**: 1
- **Complexity**: M
- **Dependencies**: []
- **Canary**: true
- **Files**: 
  - `OpenOats/Sources/OpenOats/Settings/AppSecretStore.swift` (create)
- **Acceptance Criteria**:
  - [ ] File exists at specified path
  - [ ] Type compiles without errors
  - [ ] Keychain integration functional (if applicable)
- **Related Properties**: SAFETY-001
- **Rationale**: Unblocks SettingsStore references

### TASK-002: Restore CalendarEvent Type
- **Wave**: 1
- **Complexity**: M
- **Dependencies**: [TASK-001]
- **Files**:
  - `OpenOats/Sources/OpenOats/Domain/MeetingTypes.swift` (modify - check if exists)
  - OR `OpenOats/Sources/OpenOats/Settings/CalendarEvent.swift` (create)
- **Acceptance Criteria**:
  - [ ] CalendarEvent type exists with all required properties
  - [ ] Codable conformance implemented
  - [ ] Used by meeting detection without compilation errors
- **Related Properties**: SAFETY-002
- **Rationale**: Required for meeting history and calendar integration

### TASK-003: Restore SidecastPersona Type
- **Wave**: 1
- **Complexity**: S
- **Dependencies**: [TASK-001]
- **Files**:
  - `OpenOats/Sources/OpenOats/Settings/SidecastPersona.swift` (create)
  - OR add to existing types file
- **Acceptance Criteria**:
  - [ ] SidecastPersona type exists
  - [ ] Codable conformance implemented
  - [ ] Referenced by AppSettings without errors
- **Related Properties**: SAFETY-002
- **Rationale**: Required for AppSettings.personas property

---

## Wave 2: AppSettings Architecture

### TASK-004: Implement @Observable AppSettings Foundation
- **Wave**: 2
- **Complexity**: L
- **Dependencies**: [TASK-001, TASK-002, TASK-003]
- **Files**:
  - `OpenOats/Sources/OpenOats/Settings/AppSettings.swift` (rewrite)
- **Acceptance Criteria**:
  - [ ] Uses @Observable macro (not ObservableObject)
  - [ ] @MainActor annotated for Swift 6 concurrency
  - [ ] Compiles without @Observable-related errors
  - [ ] ObservationRegistrar properly configured
- **Related Properties**: SAFETY-003, INVARIANT-001
- **Rationale**: Foundation for all AppSettings properties

### TASK-005: Add meetingAutoDetectEnabled Property
- **Wave**: 2
- **Complexity**: S
- **Dependencies**: [TASK-004]
- **Files**:
  - `OpenOats/Sources/OpenOats/Settings/AppSettings.swift` (modify)
- **Acceptance Criteria**:
  - [ ] `meetingAutoDetectEnabled: Bool` property exists
  - [ ] Property is observable (changes trigger UI updates)
  - [ ] Default value is false
  - [ ] MenuBarPopoverView compiles with `settings.meetingAutoDetectEnabled`
- **Related Properties**: INVARIANT-001
- **Rationale**: Required by MenuBarPopoverView

### TASK-006: Add notesFolders Property
- **Wave**: 2
- **Complexity**: M
- **Dependencies**: [TASK-004]
- **Files**:
  - `OpenOats/Sources/OpenOats/Settings/AppSettings.swift` (modify)
  - `OpenOats/Sources/OpenOats/Domain/NotesFolderDefinition.swift` (verify exists)
- **Acceptance Criteria**:
  - [ ] `notesFolders: [NotesFolderDefinition]` property exists
  - [ ] Property is observable
  - [ ] Default value is empty array
  - [ ] IdleHomeDashboardView compiles with `settings.notesFolders`
- **Related Properties**: INVARIANT-001
- **Rationale**: Required by IdleHomeDashboardView

### TASK-007: Add meetingFamilyPreferences Method
- **Wave**: 2
- **Complexity**: M
- **Dependencies**: [TASK-004, TASK-002]
- **Files**:
  - `OpenOats/Sources/OpenOats/Settings/AppSettings.swift` (modify)
- **Acceptance Criteria**:
  - [ ] `meetingFamilyPreferences(for event: CalendarEvent) -> MeetingFamilyPreference` method exists
  - [ ] Method signature matches View call sites
  - [ ] Returns correct type
  - [ ] IdleHomeDashboardView compiles with `settings.meetingFamilyPreferences(for: event)`
- **Related Properties**: INVARIANT-002
- **Rationale**: Required by IdleHomeDashboardView

### TASK-008: Add meetingHistoryAliasesByKey Property
- **Wave**: 2
- **Complexity**: S
- **Dependencies**: [TASK-004]
- **Files**:
  - `OpenOats/Sources/OpenOats/Settings/AppSettings.swift` (modify)
- **Acceptance Criteria**:
  - [ ] `meetingHistoryAliasesByKey: [String: String]` property exists
  - [ ] Property is observable
  - [ ] Default value is empty dictionary
  - [ ] IdleHomeDashboardView compiles with `settings.meetingHistoryAliasesByKey`
- **Related Properties**: INVARIANT-001
- **Rationale**: Required by IdleHomeDashboardView

### TASK-009: Add Remaining AppSettings Methods
- **Wave**: 2
- **Complexity**: M
- **Dependencies**: [TASK-004, TASK-002]
- **Files**:
  - `OpenOats/Sources/OpenOats/Settings/AppSettings.swift` (modify)
- **Acceptance Criteria**:
  - [ ] `canonicalMeetingHistoryKey(for event: CalendarEvent) -> String` method exists
  - [ ] `setMeetingFamilyFolderPreference(_ folderPath: String, forHistoryKey historyKey: String)` method exists
  - [ ] Both methods match View call site signatures
  - [ ] IdleHomeDashboardView compiles with all method calls
- **Related Properties**: INVARIANT-002
- **Rationale**: Required by IdleHomeDashboardView

---

## Wave 3: MLX Integration

### TASK-010: Fix ParakeetBackend Decoder State API
- **Wave**: 3
- **Complexity**: M
- **Dependencies**: [TASK-004]
- **Files**:
  - `OpenOats/Sources/OpenOats/Transcription/ParakeetBackend.swift` (modify)
- **Acceptance Criteria**:
  - [ ] Decoder state parameter added to relevant methods
  - [ ] Compiles with mlx-audio-swift dependency
  - [ ] No API mismatch errors
  - [ ] MLXWhisperBackend still functional (runtime test)
- **Related Properties**: SAFETY-004
- **Rationale**: Required for mlx-audio compatibility

### TASK-011: Fix Exhaustive Switch for tdtJa Case
- **Wave**: 3
- **Complexity**: S
- **Dependencies**: []
- **Files**:
  - Find and modify file with missing tdtJa case (likely in mlx-audio related code)
- **Acceptance Criteria**:
  - [ ] Switch statement includes tdtJa case
  - [ ] Compiles without exhaustive switch errors
  - [ ] All enum cases handled
- **Related Properties**: SAFETY-005
- **Rationale**: Swift exhaustive switch requirement

### TASK-012: Resolve SettingsStore vs AppSettings Conflicts
- **Wave**: 3
- **Complexity**: L
- **Dependencies**: [TASK-004, TASK-005, TASK-006, TASK-007, TASK-008, TASK-009]
- **Files**:
  - `OpenOats/Sources/OpenOats/Settings/SettingsStore.swift` (modify)
  - All View files using SettingsStore/AppSettings
- **Acceptance Criteria**:
  - [ ] Single source of truth for settings (AppSettings)
  - [ ] No type mismatches in View initializers
  - [ ] SettingsStore either removed or properly delegates to AppSettings
  - [ ] All Views use consistent type (@Bindable AppSettings)
- **Related Properties**: INVARIANT-003
- **Rationale**: Final integration cleanup

---

## Wave 4: Validation & Cleanup

### TASK-013: Run Full Build Verification
- **Wave**: 4
- **Complexity**: S
- **Dependencies**: [TASK-010, TASK-011, TASK-012]
- **Files**: N/A (verification task)
- **Acceptance Criteria**:
  - [ ] `swift build` completes with exit code 0
  - [ ] Zero compilation errors
  - [ ] Zero compilation warnings (or documented exceptions)
- **Related Properties**: LIVENESS-001
- **Rationale**: Verify all fixes work together

### TASK-014: Run Test Suite
- **Wave**: 4
- **Complexity**: S
- **Dependencies**: [TASK-013]
- **Files**: N/A (verification task)
- **Acceptance Criteria**:
  - [ ] `swift test` completes successfully
  - [ ] All existing tests pass
  - [ ] No test regressions
- **Related Properties**: LIVENESS-002
- **Rationale**: Verify no functional regressions

### TASK-015: Verify MLX-Audio Feature Preservation
- **Wave**: 4
- **Complexity**: M
- **Dependencies**: [TASK-013, TASK-014]
- **Files**: N/A (runtime verification)
- **Acceptance Criteria**:
  - [ ] MLXWhisperBackend initializes without errors
  - [ ] Can load and run transcription (if testable in CI)
  - [ ] No runtime crashes related to mlx-audio
- **Related Properties**: SAFETY-004
- **Rationale**: Critical stakeholder requirement

---

## Dependency Graph

```
TASK-001 (AppSecretStore)
    ↓
TASK-002 (CalendarEvent) ←──────┐
    ↓                           │
TASK-003 (SidecastPersona)      │
    ↓                           │
TASK-004 (AppSettings @Observable)
    ↓
    ├──→ TASK-005 (meetingAutoDetectEnabled)
    ├──→ TASK-006 (notesFolders)
    ├──→ TASK-007 (meetingFamilyPreferences) ←── Uses TASK-002
    ├──→ TASK-008 (meetingHistoryAliasesByKey)
    ├──→ TASK-009 (remaining methods) ←──────── Uses TASK-002
    └──→ TASK-010 (ParakeetBackend)
             ↓
    TASK-011 (tdtJa case) ───────┐
                                 │
    TASK-012 (SettingsStore) ←─┴── Depends on all Wave 2
             ↓
    TASK-013 (Build verification)
             ↓
    TASK-014 (Test suite)
             ↓
    TASK-015 (MLX verification)
```

---

## Risk Mitigation Tasks

These tasks address specific risks from the risk register:

### RISK-MIT-001: MLX Regression Prevention
- **Wave**: 4 (parallel with TASK-015)
- **Complexity**: S
- **Dependencies**: [TASK-015]
- **Acceptance Criteria**:
  - [ ] Coordinate with MLX owner for validation
  - [ ] Document MLX-specific test commands
  - [ ] Verify Metal GPU runtime requirements

### RISK-MIT-002: @Observable Runtime Verification
- **Wave**: 4 (parallel with TASK-014)
- **Complexity**: S
- **Dependencies**: [TASK-005, TASK-006, TASK-007, TASK-008, TASK-009]
- **Acceptance Criteria**:
  - [ ] Test observation notifications fire correctly
  - [ ] SwiftUI updates react to property changes
  - [ ] No memory leaks from ObservationRegistrar

---

## Notes

- **Canary Task**: TASK-001 is the canary. It must succeed before parallel execution of Wave 1 continues.
- **Critical Path**: TASK-004 → TASK-012 → TASK-013 (AppSettings foundation → integration → verification)
- **Parallel Opportunities**: Wave 2 tasks (TASK-005 through TASK-009) can run in parallel after TASK-004 completes.
- **Blocked Until**: Wave 3 tasks should not start until Wave 2 is complete to avoid integration conflicts.
