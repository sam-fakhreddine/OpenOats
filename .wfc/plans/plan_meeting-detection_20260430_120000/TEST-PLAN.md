# TEST-PLAN.md: Meeting Detection Test Strategy

**Feature:** Automatic Meeting Detection  
**Created:** 2026-04-30  
**Source:** TASKS.md, PROPERTIES.md  

## Testing Approach

| Level | Focus | Tools |
|-------|-------|-------|
| Unit | Individual components in isolation | XCTest, mocking |
| Integration | Component interactions | XCTest, real audio buffers |
| UI | User interface and flows | XCUITest |
| Performance | Latency and resource usage | XCTMetric, Instruments |
| Manual | Real-world validation | Human verification |

## Test Coverage by Task

### TASK-001: Settings Model Tests

**TEST-001-A: UserDefaults persistence**
```swift
// Test that settings persist across app launches
func testMeetingDetectionEnabledPersists() {
    let settings = AppSettings()
    settings.meetingDetectionEnabled = true
    // Simulate app restart by creating new instance
    let newSettings = AppSettings()
    XCTAssertTrue(newSettings.meetingDetectionEnabled)
}
```

**TEST-001-B: Property defaults**
```swift
func testDefaultValues() {
    let settings = AppSettings()
    XCTAssertTrue(settings.meetingDetectionEnabled) // or false per product decision
    XCTAssertEqual(settings.meetingDetectionSensitivity, .medium)
    XCTAssertEqual(settings.meetingEndSilenceDuration, 30.0)
}
```

---

### TASK-002: Enum Types Tests

**TEST-002-A: DetectionSensitivity thresholds**
```swift
func testVADThresholds() {
    XCTAssertEqual(DetectionSensitivity.low.vadThreshold, 0.3)
    XCTAssertEqual(DetectionSensitivity.medium.vadThreshold, 0.5)
    XCTAssertEqual(DetectionSensitivity.high.vadThreshold, 0.7)
}
```

**TEST-002-B: Enum case count**
```swift
func testAllCasesPresent() {
    XCTAssertEqual(DetectionSensitivity.allCases.count, 3)
    XCTAssertEqual(SilenceDuration.allCases.count, 4)
}
```

---

### TASK-003: DetectionEngine Tests

**TEST-003-A: Initialization**
```swift
func testInitialState() {
    let engine = MeetingDetectionEngine()
    XCTAssertFalse(engine.isDetectionActive)
    XCTAssertEqual(engine.meetingState, .idle)
}
```

**TEST-003-B: Start/stop detection**
```swift
func testStartStopDetection() async {
    let engine = MeetingDetectionEngine()
    await engine.startDetection()
    XCTAssertTrue(engine.isDetectionActive)
    await engine.stopDetection()
    XCTAssertFalse(engine.isDetectionActive)
}
```

---

### TASK-004: VAD Integration Tests

**TEST-004-A: Speech detection accuracy**
```swift
func testSpeechDetection() {
    let engine = MeetingDetectionEngine()
    let speechBuffer = createMockSpeechBuffer() // RMS > 0.5
    let result = engine.processAudioBuffer(speechBuffer)
    XCTAssertTrue(result.isSpeechDetected)
}
```

**TEST-004-B: Silence detection**
```swift
func testSilenceDetection() {
    let engine = MeetingDetectionEngine()
    let silenceBuffer = createMockSilenceBuffer() // RMS < 0.1
    let result = engine.processAudioBuffer(silenceBuffer)
    XCTAssertFalse(result.isSpeechDetected)
}
```

**TEST-004-C: Sensitivity threshold adherence**
```swift
func testLowSensitivityRequiresHigherEnergy() {
    // Low sensitivity = higher threshold = harder to trigger
    let engine = MeetingDetectionEngine(sensitivity: .low)
    let mediumEnergyBuffer = createMockBuffer(rms: 0.4)
    let result = engine.processAudioBuffer(mediumEnergyBuffer)
    XCTAssertFalse(result.isSpeechDetected) // 0.4 < 0.5 (low threshold)
}
```

---

### TASK-005: State Machine Tests

**TEST-005-A: State transition validation**
```swift
func testValidTransitions() {
    let engine = MeetingDetectionEngine()
    
    // idle → detecting
    engine.startDetection()
    XCTAssertEqual(engine.meetingState, .detecting)
    
    // detecting → inMeeting (simulated speech)
    engine.simulateSpeechDetected()
    XCTAssertEqual(engine.meetingState, .inMeeting)
    
    // inMeeting → ending (simulated silence timeout)
    engine.simulateSilenceTimeout()
    XCTAssertEqual(engine.meetingState, .ending)
    
    // ending → idle
    engine.completeMeetingEnd()
    XCTAssertEqual(engine.meetingState, .idle)
}
```

**TEST-005-B: Invalid transitions prevented**
```swift
func testInvalidTransitionsBlocked() {
    let engine = MeetingDetectionEngine()
    // Cannot go from idle directly to inMeeting
    XCTAssertThrowsError(try engine.forceState(.inMeeting))
}
```

**TEST-005-C: Callback invocation**
```swift
func testMeetingStartCallback() {
    let engine = MeetingDetectionEngine()
    var callbackFired = false
    engine.onMeetingStart = { callbackFired = true }
    
    engine.startDetection()
    engine.simulateSustainedSpeech(duration: 3.0)
    
    XCTAssertTrue(callbackFired)
}
```

---

### TASK-006: ControlBar UI Tests

**TEST-006-A: Toggle visibility**
```swift
func testDetectionToggleVisibleWhenNotRecording() {
    let app = XCUIApplication()
    app.launch()
    // Ensure not recording
    XCTAssertTrue(app.buttons["autoDetectToggle"].exists)
}
```

**TEST-006-B: Toggle state reflects settings**
```swift
func testToggleReflectsSettings() {
    let app = XCUIApplication()
    app.launch()
    // Pre-set UserDefaults
    let toggle = app.switches["autoDetectToggle"]
    XCTAssertEqual(toggle.value as? String, "1") // On
}
```

---

### TASK-007: SettingsView UI Tests

**TEST-007-A: Navigation to detection settings**
```swift
func testSettingsNavigation() {
    let app = XCUIApplication()
    app.launch()
    app.buttons["settingsButton"].tap()
    app.cells["meetingDetectionSection"].tap()
    XCTAssertTrue(app.navigationBars["Meeting Detection"].exists)
}
```

**TEST-007-B: Sensitivity picker values**
```swift
func testSensitivityPickerOptions() {
    let app = XCUIApplication()
    app.launch()
    // Navigate to settings
    app.segmentedControls["sensitivityPicker"].buttons["High"].tap()
    // Verify selection persisted
}
```

---

### TASK-010: False Positive Reduction Tests

**TEST-010-A: Short utterance ignored**
```swift
func testShortUtteranceIgnored() {
    let engine = MeetingDetectionEngine()
    engine.startDetection()
    
    // Simulate 1 second of speech (below 2s threshold)
    engine.simulateSpeech(duration: 1.0)
    
    XCTAssertEqual(engine.meetingState, .detecting) // Still detecting, not inMeeting
}
```

**TEST-010-B: Sustained speech triggers**
```swift
func testSustainedSpeechTriggersMeeting() {
    let engine = MeetingDetectionEngine()
    engine.startDetection()
    
    // Simulate 3 seconds of continuous speech
    engine.simulateSpeech(duration: 3.0)
    
    XCTAssertEqual(engine.meetingState, .inMeeting)
}
```

**TEST-010-C: Reset on silence gap**
```swift
func testSpeechCounterResetsOnSilence() {
    let engine = MeetingDetectionEngine()
    engine.startDetection()
    
    // 1.5s speech, 1.5s silence, then more speech
    engine.simulateSpeech(duration: 1.5)
    engine.simulateSilence(duration: 1.5)
    engine.simulateSpeech(duration: 1.5)
    
    // Counter should have reset, not reached 3s threshold
    XCTAssertEqual(engine.meetingState, .detecting)
}
```

---

## Performance Tests

**PERF-001: Buffer processing latency**
```swift
func testBufferProcessingPerformance() throws {
    let engine = MeetingDetectionEngine()
    let buffer = createMockSpeechBuffer()
    
    measure {
        for _ in 0..<1000 {
            _ = engine.processAudioBuffer(buffer)
        }
    }
    // XCTAssert median < 10ms
}
```

**PERF-002: Memory footprint**
```swift
func testMemoryUsage() throws {
    let engine = MeetingDetectionEngine()
    // Run detection for simulated 1 hour
    // Assert memory delta < 10MB
}
```

---

## Integration Test Scenarios

**SCENARIO-001: Full meeting detection flow**
```
GIVEN: App launched with auto-detection enabled
WHEN: Simulated meeting audio plays (speech 5s, silence 35s)
THEN: Meeting starts automatically, ends automatically, transcript saved
```

**SCENARIO-002: Manual override during auto-detection**
```
GIVEN: Auto-detection active and listening
WHEN: User presses manual start button
THEN: Recording starts immediately, auto-detection state updates correctly
```

**SCENARIO-003: Settings change during meeting**
```
GIVEN: Meeting in progress (detected automatically)
WHEN: User changes silence timeout from 30s to 60s
THEN: New timeout takes effect immediately, meeting doesn't end prematurely
```

---

## Test Data Requirements

| Data Type | Format | Purpose |
|-----------|--------|---------|
| Mock speech buffers | AVAudioPCMBuffer | VAD accuracy testing |
| Mock silence buffers | AVAudioPCMBuffer | Silence detection testing |
| Real meeting samples | .wav/.m4a files | Integration testing |
| Noise profiles | AVAudioPCMBuffer | False positive testing |

---

## Coverage Targets

| Metric | Target |
|--------|--------|
| Line coverage | > 80% |
| Branch coverage | > 75% |
| Property coverage | 100% of documented properties |
| UI flow coverage | All critical paths |
