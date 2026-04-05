# Camera-Based Meeting Detection

**Date:** 2026-04-05
**Status:** Draft

## Problem

OpenOats detects meetings by monitoring microphone activation status via CoreAudio (`kAudioDevicePropertyDeviceIsRunningSomewhere`). This triggers false positives from dictation apps (Almond, SuperWhisper), voice messages (WhatsApp), and other non-meeting mic usage. The current code emits `.detected(app)` even when no meeting app is found (`app == nil`), so any mic activation fires a detection notification.

## Solution

Add camera-based detection as the strongest meeting signal using CoreMediaIO property listeners. Restructure `MeetingDetector` to use priority-based multi-signal evaluation:

| Priority | Condition | Debounce | Rationale |
|----------|-----------|----------|-----------|
| 0 (strongest) | Camera ON | None (instant) | Nobody turns on camera outside meetings |
| 1 | Mic ON + meeting app running | 5s | Current behavior, but now requires app presence |
| 2 | Mic ON alone | — | **No detection** (this is the fix) |

The notification UX stays identical — all signals still prompt the user before starting transcription.

## Architecture

### New: CameraSignalSource

**File:** `Sources/OpenOats/Meeting/CameraActivityMonitor.swift`

**Protocol:** `CameraSignalSource` — mirrors existing `AudioSignalSource`:
```swift
protocol CameraSignalSource: Sendable {
    var signals: AsyncStream<Bool> { get }
}
```

**Implementation:** `CoreMediaIOSignalSource`

Uses CoreMediaIO C APIs for event-driven camera status monitoring:
1. Enumerate video devices via `AVCaptureDevice.DiscoverySession` (`.builtInWideAngleCamera`, `.external`, media type `.video`)
2. Register system-level listener on `kCMIOHardwarePropertyDevices` for hot-plug (cameras added/removed)
3. Register per-device listener on `kCMIODevicePropertyDeviceIsRunningSomewhere` for running state
4. On callback: check all devices, deduplicate state changes, yield to `AsyncStream`

Same architectural pattern as existing `CoreAudioSignalSource`: `DispatchQueue` for thread safety, `Unmanaged` pointers for C callback bridging, dedup via `lastEmittedValue`.

**No new entitlements required.** `kCMIODevicePropertyDeviceIsRunningSomewhere` is a status read ("is the camera running in any process?"), not a capture. Confirmed against SDK headers. App is not sandboxed.

### Modified: MeetingDetector

**File:** `Sources/OpenOats/Meeting/MeetingDetector.swift`

Changes to the existing actor:

1. **New init parameter:** `cameraSource: (any CameraSignalSource)?` — defaults to `CoreMediaIOSignalSource()`
2. **New state:** `isCameraActive: Bool`, `detectionTrigger: DetectionTrigger?`
3. **Separate camera monitoring task** in `start()` — runs independently from the mic monitoring task so camera signals aren't blocked behind a 5s mic debounce sleep
4. **Priority evaluation replaces `handleMicSignal`:**
   - Camera ON → immediate `.detected(app)` (scan for app name, but detection fires regardless)
   - Mic ON → debounce 5s, then scan for meeting app. If app found → `.detected(app)`. If no app → no detection.
   - Mic OFF → if trigger was `.micAndApp`, emit `.ended`
   - Camera OFF → if trigger was `.camera`, emit `.ended`
5. **Overlap handling:** If already active, new signals don't re-emit `.detected`. The `detectionTrigger` tracks the *strongest* active signal. End condition: meeting ends only when *all* active signals are off. Specifically:
   - Camera ON + mic+app active → trigger is `.camera`. Camera turns off → check if mic+app still active. If yes, downgrade trigger to `.micAndApp`, meeting continues. If no, emit `.ended`.
   - Mic+app active → trigger is `.micAndApp`. Camera turns on → upgrade trigger to `.camera`. Mic turns off → meeting continues (camera still on).
   - Both off → emit `.ended`.

```swift
enum DetectionTrigger: Sendable {
    case camera
    case micAndApp
}
```

### Modified: DetectionSignal

**File:** `Sources/OpenOats/Domain/MeetingTypes.swift`

Add new case:
```swift
case cameraActivated
```

This flows through `DetectionContext` → `MeetingMetadata` for logging/UI purposes.

### Modified: MeetingDetectionController

**File:** `Sources/OpenOats/App/MeetingDetectionController.swift`

Minimal changes:
- In `handleDetectionAccepted()`: set signal to `.cameraActivated` when the detector's trigger is `.camera` (instead of `.audioActivity` fallback)
- Dismiss tracking: when `app?.bundleID` is `nil` (camera-only detection with no identifiable meeting app), use `"__camera__"` as the dismiss key

### Modified: AppCoordinator

**File:** `Sources/OpenOats/App/AppCoordinator.swift`

In `startDetectionEventLoop()`, lines 240-246: currently only starts silence/exit monitoring when signal is `.appLaunched`. Expand to also handle `.cameraActivated`:
- For `.cameraActivated`: start silence monitoring (same as app-launched)
- For `.cameraActivated` with a detected app: also start app exit monitoring
- For `.cameraActivated` without a detected app: skip app exit monitoring (no bundle ID to watch)

Similarly in the `.meetingAppExited` handler (lines 247-253): also check for `.cameraActivated` signal.

### Modified: SettingsView

**File:** `Sources/OpenOats/Views/SettingsView.swift`

Update the detection description text (line 98, 123) to mention camera monitoring alongside microphone monitoring.

## Tests

### New: MockCameraSignalSource

Same pattern as existing `MockAudioSignalSource` — controllable `AsyncStream` for tests.

### New test cases in MeetingDetectorTests:

- Camera ON → instant `.detected` (no debounce wait)
- Mic ON alone → no detection emitted
- Mic ON + meeting app → `.detected` after 5s debounce
- Camera ON then OFF → `.ended`
- Camera ON, then mic+app → no duplicate `.detected`
- Camera OFF while mic+app still active → meeting continues
- Mic OFF while camera still active → meeting continues
- Both OFF → `.ended`

### Updated existing tests:

- Tests that expected mic-only to trigger detection now need a meeting app running, or need to be updated to verify no detection occurs.

## What doesn't change

- `CoreAudioSignalSource` — untouched
- `NotificationService` — same UX, same notification flow
- `LiveSessionController` — no changes
- `AppContainer` — no changes (detector is created inside controller)
- Known meeting apps list — kept as-is
- Settings storage — no new preferences
- Session storage / JSONL format — unchanged
- Build scripts, CI — unchanged (CoreMediaIO is a system framework, no new dependencies)
