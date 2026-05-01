# PROPERTIES.md: Base Branch Compilation Fixes

**Plan ID**: plan_base-branch-fixes_20260430_221736  
**Source**: PRD-base-branch-fixes.md  
**Purpose**: Formal properties for verification and testing

---

## Safety Properties (What Must Never Happen)

### SAFETY-001: No Missing Type References
**Statement**: The codebase must never reference types that do not exist or are not defined.

**Rationale**: Compilation errors occur when Views or other code reference deleted or undefined types (AppSecretStore, CalendarEvent, SidecastPersona).

**Formal Expression**:
```
∀ type ∈ {AppSecretStore, CalendarEvent, SidecastPersona}:
  type.isDefined() ∧ type.isAccessible()
```

**Priority**: CRITICAL

**Suggested Observables**:
- Build error count for "Cannot find type" errors
- Import resolution success rate

---

### SAFETY-002: No Missing Property or Method References
**Statement**: The codebase must never reference properties or methods on AppSettings that do not exist.

**Rationale**: Views expect specific AppSettings properties (meetingAutoDetectEnabled, notesFolders, etc.) and methods (meetingFamilyPreferences, etc.). Missing these causes compilation errors.

**Formal Expression**:
```
∀ property ∈ {meetingAutoDetectEnabled, notesFolders, meetingHistoryAliasesByKey}:
  AppSettings.hasProperty(property) ∧ property.isObservable()

∀ method ∈ {meetingFamilyPreferences, canonicalMeetingHistoryKey, setMeetingFamilyFolderPreference}:
  AppSettings.hasMethod(method) ∧ method.isCallable()
```

**Priority**: CRITICAL

**Suggested Observables**:
- View compilation error count
- Property access success in View files

---

### SAFETY-003: No ObservableObject Pattern Violations
**Statement**: AppSettings must use @Observable macro correctly and must not violate Swift 6 observation patterns.

**Rationale**: @Observable requires different patterns than ObservableObject. Using @Published or objectWillChange with @Observable causes warnings or errors.

**Formal Expression**:
```
AppSettings.usesObservableMacro() ∧
¬AppSettings.usesPublishedWrapper() ∧
¬AppSettings.usesObjectWillChange()
```

**Priority**: HIGH

**Suggested Observables**:
- Swift 6 concurrency warnings count
- @Observable macro usage verification

---

### SAFETY-004: No MLX-Audio Feature Regression
**Statement**: The mlx-audio feature must continue to function correctly after base branch fixes.

**Rationale**: MLX-audio is a critical feature using ParakeetBackend. Compilation fixes must not break runtime functionality.

**Formal Expression**:
```
MLXWhisperBackend.canInitialize() ∧
MLXWhisperBackend.canTranscribe() ∧
ParakeetBackend.hasDecoderStateParameter()
```

**Priority**: CRITICAL

**Suggested Observables**:
- MLX initialization success rate
- Transcription test pass rate
- ParakeetBackend API compatibility

---

### SAFETY-005: No Exhaustive Switch Violations
**Statement**: All switch statements on enums must be exhaustive, covering all cases including tdtJa.

**Rationale**: Swift requires exhaustive switches. Missing cases cause compilation errors.

**Formal Expression**:
```
∀ switchStmt ∈ codebase:
  switchStmt.isExhaustive() ∧
  (switchStmt.enumType.hasCase("tdtJa") → switchStmt.coversCase("tdtJa"))
```

**Priority**: HIGH

**Suggested Observables**:
- Exhaustive switch error count
- Enum coverage analysis

---

## Liveness Properties (What Must Eventually Happen)

### LIVENESS-001: Clean Build Achievement
**Statement**: The build process must eventually complete successfully with zero errors.

**Rationale**: The primary goal is achieving a clean build.

**Formal Expression**:
```
◇ (build.errorCount == 0 ∧ build.exitCode == 0)
```

**Priority**: CRITICAL

**Suggested Observables**:
- Build duration
- Build exit code
- Error count trend over time

---

### LIVENESS-002: Test Suite Passage
**Statement**: All tests must eventually pass without regressions.

**Rationale**: Fixes must not break existing functionality.

**Formal Expression**:
```
◇ (test.passCount == test.totalCount ∧ test.regressionCount == 0)
```

**Priority**: HIGH

**Suggested Observables**:
- Test pass rate
- Test execution time
- Regression detection

---

### LIVENESS-003: Property Observation Functionality
**Statement**: Changes to AppSettings properties must eventually trigger observation notifications.

**Rationale**: @Observable properties must notify observers for SwiftUI updates.

**Formal Expression**:
```
∀ property ∈ observableProperties:
  □ (property.valueChanges() → ◇ observation.notificationFires())
```

**Priority**: MEDIUM

**Suggested Observables**:
- Observation notification latency
- UI update responsiveness

---

## Invariants (What Must Always Be True)

### INVARIANT-001: AppSettings Property Observability
**Statement**: All AppSettings properties accessed by Views must always be observable.

**Rationale**: Views rely on observation to update UI when settings change.

**Formal Expression**:
```
□ (property ∈ {meetingAutoDetectEnabled, notesFolders, meetingHistoryAliasesByKey} →
   property.isObservable())
```

**Priority**: HIGH

**Suggested Observables**:
- Property observation registration
- SwiftUI binding functionality

---

### INVARIANT-002: Method Signature Consistency
**Statement**: AppSettings method signatures must always match their call sites in Views.

**Rationale**: Method calls in Views expect specific parameter types and return types.

**Formal Expression**:
```
□ ∀ callSite ∈ ViewFiles:
  callSite.methodSignature == AppSettings.method(callSite.methodName).signature
```

**Priority**: HIGH

**Suggested Observables**:
- Method call compilation success
- Signature mismatch errors

---

### INVARIANT-003: Single Settings Source of Truth
**Statement**: There must always be exactly one source of truth for application settings.

**Rationale**: Multiple settings types (SettingsStore vs AppSettings) cause confusion and type conflicts.

**Formal Expression**:
```
□ (settingsSourceCount == 1 ∧ settingsSource == AppSettings)
```

**Priority**: HIGH

**Suggested Observables**:
- Settings type usage count
- Type consistency across Views

---

### INVARIANT-004: Swift 6 Concurrency Compliance
**Statement**: The codebase must always comply with Swift 6 strict concurrency checking.

**Rationale**: Swift 6 concurrency warnings indicate potential data race issues.

**Formal Expression**:
```
□ (concurrencyWarningCount == 0 ∨
   ∀ warning ∈ concurrencyWarnings:
     warning.isDocumentedException() ∧ warning.hasMitigation())
```

**Priority**: MEDIUM

**Suggested Observables**:
- Swift 6 concurrency warning count
- @MainActor usage correctness
- Sendable conformance

---

### INVARIANT-005: Supply Chain Security
**Statement**: All dependencies must always be pinned to specific git hashes.

**Rationale**: Supply chain security requires reproducible builds with verified dependencies.

**Formal Expression**:
```
□ ∀ dependency ∈ Package.swift:
  dependency.hasExactRevision() ∧
  dependency.revision.isValidGitHash()
```

**Priority**: MEDIUM

**Suggested Observables**:
- Dependency resolution reproducibility
- Git hash verification

---

## Performance Properties

### PERFORMANCE-001: Build Time
**Statement**: Clean build time must be less than 60 seconds.

**Target**: < 60 seconds
**Measurement**: `time swift build`

---

### PERFORMANCE-002: Test Execution Time
**Statement**: Full test suite execution must complete in reasonable time.

**Target**: < 120 seconds
**Measurement**: `time swift test`

---

## Property Verification Matrix

| Property | Verification Method | Test Case | Priority |
|----------|---------------------|-----------|----------|
| SAFETY-001 | Compilation | `swift build` | CRITICAL |
| SAFETY-002 | Compilation | View file compilation | CRITICAL |
| SAFETY-003 | Static analysis | Swift 6 warning check | HIGH |
| SAFETY-004 | Runtime test | MLX initialization test | CRITICAL |
| SAFETY-005 | Compilation | Switch statement analysis | HIGH |
| LIVENESS-001 | Build script | Exit code verification | CRITICAL |
| LIVENESS-002 | Test runner | Test pass verification | HIGH |
| LIVENESS-003 | UI test | Observation notification test | MEDIUM |
| INVARIANT-001 | Unit test | Property observation test | HIGH |
| INVARIANT-002 | Compilation | Method signature check | HIGH |
| INVARIANT-003 | Code review | Settings type audit | HIGH |
| INVARIANT-004 | Static analysis | Swift 6 warning count | MEDIUM |
| INVARIANT-005 | Dependency check | Package.resolved audit | MEDIUM |

---

## Property-to-Task Mapping

| Property | Related Tasks |
|----------|---------------|
| SAFETY-001 | TASK-001, TASK-002, TASK-003 |
| SAFETY-002 | TASK-005, TASK-006, TASK-007, TASK-008, TASK-009 |
| SAFETY-003 | TASK-004 |
| SAFETY-004 | TASK-010, TASK-015 |
| SAFETY-005 | TASK-011 |
| LIVENESS-001 | TASK-013 |
| LIVENESS-002 | TASK-014 |
| LIVENESS-003 | RISK-MIT-002 |
| INVARIANT-001 | TASK-005, TASK-006, TASK-008 |
| INVARIANT-002 | TASK-007, TASK-009 |
| INVARIANT-003 | TASK-012 |
| INVARIANT-004 | All tasks (ongoing) |
| INVARIANT-005 | N/A (already satisfied) |
