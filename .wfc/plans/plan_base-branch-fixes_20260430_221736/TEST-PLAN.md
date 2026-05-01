# TEST-PLAN.md: Base Branch Compilation Fixes

**Plan ID**: plan_base-branch-fixes_20260430_221736  
**Source**: PRD-base-branch-fixes.md, PROPERTIES.md  
**Goal**: Verify zero compilation errors and no functional regressions

---

## Testing Approach

### Unit Tests
- Test individual type definitions compile correctly
- Test AppSettings properties are accessible and observable
- Test method signatures match expected interfaces

### Integration Tests
- Test Views compile with AppSettings bindings
- Test SettingsStore/AppSettings integration
- Test meeting detection integration with restored types

### Build Verification
- Clean build from scratch
- Incremental build after changes
- CI/CD pipeline verification

### Runtime Verification
- MLX-audio feature functionality
- Property observation notifications
- UI update responsiveness

---

## Test Coverage Targets

| Category | Target Coverage | Measurement |
|----------|-----------------|-------------|
| Type definitions | 100% | All restored types compile |
| AppSettings properties | 100% | All properties accessible |
| View compilation | 100% | All Views compile |
| Build success | 100% | Zero errors |
| Test pass rate | 100% | No regressions |

---

## Test Cases

### TC-001: AppSecretStore Type Compilation
**Related Task**: TASK-001  
**Related Property**: SAFETY-001

**Steps**:
1. Attempt to compile file containing AppSecretStore type
2. Verify no "Cannot find type" errors

**Expected Outcome**:
- Compilation succeeds
- Type is accessible from SettingsStore

**Verification**:
```bash
grep -r "AppSecretStore" OpenOats/Sources/OpenOats/Settings/
swift build 2>&1 | grep -i "AppSecretStore" || echo "No errors"
```

---

### TC-002: CalendarEvent Type Compilation
**Related Task**: TASK-002  
**Related Property**: SAFETY-001

**Steps**:
1. Attempt to compile file containing CalendarEvent type
2. Verify Codable conformance
3. Verify usage in meeting detection

**Expected Outcome**:
- Type compiles with all properties
- Codable synthesis works
- Meeting detection can reference type

**Verification**:
```bash
grep -r "CalendarEvent" OpenOats/Sources/OpenOats/
swift build 2>&1 | grep -i "CalendarEvent" || echo "No errors"
```

---

### TC-003: SidecastPersona Type Compilation
**Related Task**: TASK-003  
**Related Property**: SAFETY-001

**Steps**:
1. Attempt to compile file containing SidecastPersona type
2. Verify Codable conformance
3. Verify AppSettings.personas property works

**Expected Outcome**:
- Type compiles
- Can be used in AppSettings

---

### TC-004: @Observable AppSettings Compilation
**Related Task**: TASK-004  
**Related Property**: SAFETY-003

**Steps**:
1. Verify AppSettings uses @Observable macro
2. Verify @MainActor annotation
3. Verify no ObservableObject patterns

**Expected Outcome**:
- @Observable macro present
- No @Published usage
- No objectWillChange references

**Verification**:
```bash
grep "@Observable" OpenOats/Sources/OpenOats/Settings/AppSettings.swift
grep -c "@Published" OpenOats/Sources/OpenOats/Settings/AppSettings.swift || echo "No @Published (good)"
```

---

### TC-005: meetingAutoDetectEnabled Property
**Related Task**: TASK-005  
**Related Property**: SAFETY-002, INVARIANT-001

**Steps**:
1. Verify property exists in AppSettings
2. Verify property type is Bool
3. Verify MenuBarPopoverView compiles with property access
4. Test observation (if runtime test available)

**Expected Outcome**:
- `settings.meetingAutoDetectEnabled` compiles
- Property is observable
- Default value is false

**Verification**:
```bash
grep "meetingAutoDetectEnabled" OpenOats/Sources/OpenOats/Settings/AppSettings.swift
grep "meetingAutoDetectEnabled" OpenOats/Sources/OpenOats/Views/MenuBarPopoverView.swift
```

---

### TC-006: notesFolders Property
**Related Task**: TASK-006  
**Related Property**: SAFETY-002, INVARIANT-001

**Steps**:
1. Verify property exists
2. Verify type is [NotesFolderDefinition]
3. Verify IdleHomeDashboardView compiles

**Expected Outcome**:
- Property accessible
- Array operations compile

---

### TC-007: meetingFamilyPreferences Method
**Related Task**: TASK-007  
**Related Property**: SAFETY-002, INVARIANT-002

**Steps**:
1. Verify method exists with correct signature
2. Verify IdleHomeDashboardView call sites compile
3. Test with sample CalendarEvent (if runtime test available)

**Expected Outcome**:
- Method signature matches: `meetingFamilyPreferences(for event: CalendarEvent) -> MeetingFamilyPreference`
- Call sites compile without errors

---

### TC-008: meetingHistoryAliasesByKey Property
**Related Task**: TASK-008  
**Related Property**: SAFETY-002, INVARIANT-001

**Steps**:
1. Verify property exists
2. Verify type is [String: String]
3. Verify IdleHomeDashboardView compiles

---

### TC-009: Remaining AppSettings Methods
**Related Task**: TASK-009  
**Related Property**: SAFETY-002, INVARIANT-002

**Steps**:
1. Verify `canonicalMeetingHistoryKey(for:)` method
2. Verify `setMeetingFamilyFolderPreference(_:forHistoryKey:)` method
3. Verify all IdleHomeDashboardView call sites compile

---

### TC-010: ParakeetBackend Decoder State
**Related Task**: TASK-010  
**Related Property**: SAFETY-004

**Steps**:
1. Verify decoder state parameter added
2. Verify compilation with mlx-audio-swift
3. Test MLXWhisperBackend initialization (runtime)

**Expected Outcome**:
- No API mismatch errors
- MLX feature still functional

---

### TC-011: Exhaustive Switch tdtJa Case
**Related Task**: TASK-011  
**Related Property**: SAFETY-005

**Steps**:
1. Find switch statement with tdtJa case
2. Verify case is handled
3. Verify compilation

**Verification**:
```bash
swift build 2>&1 | grep -i "switch must be exhaustive" || echo "All switches exhaustive"
```

---

### TC-012: SettingsStore/AppSettings Integration
**Related Task**: TASK-012  
**Related Property**: INVARIANT-003

**Steps**:
1. Verify single settings type used throughout
2. Verify no type mismatches in View initializers
3. Verify @Bindable usage is consistent

**Expected Outcome**:
- All Views use @Bindable AppSettings
- No SettingsStore references remain (or properly delegated)

---

### TC-013: Clean Build Verification
**Related Task**: TASK-013  
**Related Property**: LIVENESS-001

**Steps**:
1. Clean build directory: `swift package clean`
2. Run build: `swift build`
3. Verify exit code 0
4. Verify zero errors

**Expected Outcome**:
- Build completes successfully
- No compilation errors
- Build time < 60 seconds

**Verification**:
```bash
swift package clean
swift build 2>&1 | tee build.log
echo "Exit code: $?"
grep -c "error:" build.log || echo "Zero errors"
```

---

### TC-014: Test Suite Execution
**Related Task**: TASK-014  
**Related Property**: LIVENESS-002

**Steps**:
1. Run full test suite: `swift test`
2. Verify all tests pass
3. Check for regressions

**Expected Outcome**:
- All tests pass
- No new test failures
- Test execution time < 120 seconds

**Verification**:
```bash
swift test 2>&1 | tee test.log
echo "Exit code: $?"
grep -E "Test Suite.*passed" test.log
```

---

### TC-015: MLX-Audio Feature Preservation
**Related Task**: TASK-015  
**Related Property**: SAFETY-004

**Steps**:
1. Verify MLXWhisperBackend compiles
2. Check ParakeetBackend API compatibility
3. Runtime test: Initialize backend (if Metal available)

**Expected Outcome**:
- MLX backend initializes without errors
- No runtime crashes

---

## Test Execution Order

### Phase 1: Foundation Tests (Wave 1)
- TC-001: AppSecretStore
- TC-002: CalendarEvent
- TC-003: SidecastPersona

### Phase 2: Architecture Tests (Wave 2)
- TC-004: @Observable AppSettings
- TC-005 through TC-009: Properties and methods

### Phase 3: Integration Tests (Wave 3)
- TC-010: ParakeetBackend
- TC-011: Exhaustive switch
- TC-012: SettingsStore integration

### Phase 4: Verification Tests (Wave 4)
- TC-013: Clean build
- TC-014: Test suite
- TC-015: MLX preservation

---

## Regression Detection

### Known Good State
- Commit: `57e4e10` (main branch) - Clean build
- Commit: `ed3f879` (feat/meeting-detection) - Meeting detection working

### Regression Indicators
- Build errors in previously working files
- Test failures in existing tests
- MLX initialization failures
- UI binding failures

### Rollback Plan
If regressions detected:
1. Identify offending task
2. Revert specific task changes
3. Re-run verification tests
4. Re-approach with alternative implementation

---

## CI/CD Integration

### GitHub Actions Workflow
```yaml
name: Build and Test
on: [push, pull_request]
jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - name: Build
        run: swift build
      - name: Test
        run: swift test
```

### Required Checks
- [ ] Build succeeds (exit code 0)
- [ ] Zero compilation errors
- [ ] All tests pass
- [ ] No Swift 6 concurrency warnings (or documented)

---

## Manual Testing Checklist

- [ ] App launches without crashes
- [ ] Settings view opens
- [ ] Meeting detection toggle works (if UI available)
- [ ] Notes folder selection works
- [ ] MLX transcription initializes (if Metal available)

---

## Test Data Requirements

No special test data required for compilation fixes. Runtime tests may require:
- Sample audio file for MLX transcription test
- Mock CalendarEvent for meeting detection test

---

## Success Criteria Summary

| Criterion | Target | Verification |
|-----------|--------|--------------|
| Build errors | 0 | TC-013 |
| Test pass rate | 100% | TC-014 |
| Type compilation | 100% | TC-001, TC-002, TC-003 |
| Property accessibility | 100% | TC-005 through TC-009 |
| MLX functionality | Preserved | TC-015 |
| Build time | < 60s | TC-013 |
