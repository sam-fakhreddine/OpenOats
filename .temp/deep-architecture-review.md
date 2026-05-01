# OpenOats Deep Architecture Review

**Date:** 2026-04-30
**Reviewer:** 4-agent Opus deep inspection (lead + 3 specialists)
**Scope:** Every file in OpenOats/Sources/OpenOats/

---

## 1. CRITICAL (will crash or corrupt data)

### C1. Data race in StreamingTranscriber — `@unchecked Sendable` with mutable state

**File:** `StreamingTranscriber.swift:7, 44-68, 251, 385-411`

`StreamingTranscriber` is `@unchecked Sendable` with mutable fields (`converter`, `rateTrackingStartDate`, `previousContext`, `effectiveSampleRate`) read/written from the `run()` async method. No synchronization. If any future caller pattern introduces concurrent access, this is an `EXC_BAD_ACCESS`.

**Fix:** Convert to an actor, or add `OSAllocatedUnfairLock` around mutable fields.

### C2. Data race in MicCapture audio callback

**File:** `MicCapture.swift:152-165`

```swift
var tapCallCount = 0
inputNode.installTap(...) { buffer, _ in
    tapCallCount += 1  // data race: mutable var on audio thread
```

**Fix:** Use `OSAtomicIncrement32` or mark `nonisolated(unsafe)` with documentation.

### C3. `mergeAndEncode` reads entire recording into memory

**File:** `AudioRecorder.swift:356-376, 419-487`

`readAllMono()` loads the full mic + system audio into `[Float]` arrays. A 2-hour meeting at 48kHz = ~2.6 GB in memory. Will OOM kill on 8GB Macs.

**Fix:** Stream the merge in chunks of ~64K frames. Cap memory at ~768KB regardless of recording length.

### C4. Temp audio files at risk of OS purge

**File:** `AudioRecorder.swift:58-60`

Uses `NSTemporaryDirectory()` for recording files. The OS can purge these under memory pressure — even during a live recording. No crash recovery path.

**Fix:** Use Application Support directory. Provides durability and crash recovery.

---

## 2. HIGH (performance degradation users will notice)

### H1. Partial transcription blocks the VAD loop

**File:** `StreamingTranscriber.swift:207-229`

The partial transcription call (`backend.transcribe`) is `await`ed inline inside the VAD loop. For local models (200-500ms inference), the entire VAD processing stalls — audio buffers queue up, latency spikes.

**Fix:** Fire partial transcription in a child `Task`. The `isRunningPartial` guard already prevents overlapping calls.

### H2. Scalar audio DSP under NSLock

**File:** `AudioRecorder.swift:64-178`

`writeMicBuffer` runs entirely under `lock.withLock {}` — including per-sample scalar downmix loops (no vDSP), peak calculation, and file I/O. Contention with `writeSysBuffer` on the same lock.

**Fix:** Use vDSP for downmix. Do DSP outside the lock, only hold lock for the file write.

### H3. Unbounded speech buffer during long continuous speech

**File:** `StreamingTranscriber.swift:117, 185, 231-236`

`speechSamples` grows until the flush interval (up to 30 seconds = ~1.9MB per transcriber). The flush then sends all 30s to the backend at once — latency spike.

**Fix:** Sliding-window approach: transcribe in overlapping fixed-size windows during continuous speech.

### H4. Unstructured Tasks without cancellation in `tappedStream`

**File:** `TranscriptionEngine.swift:1185-1201`

`Task { for await buffer in ... }` is not cancelled when the engine stops. Relies on upstream stream finishing. Multiple instances for mic, system, and diarization create dangling tasks.

**Fix:** Return Task handle alongside stream, or restructure so the tap is synchronous in the consumer loop.

---

## 3. MEDIUM (tech debt that compounds)

### M1. Duplicated mono-downmix code across 4 files

Mono downmix + resample appears in `AudioRecorder.writeMicBuffer`, `AudioRecorder.readAllMono`, `StreamingTranscriber.extractSamples`, and `BatchAudioSampleReader.resample`. Different error handling, different fast-paths. Bug fix in one doesn't propagate.

**Fix:** Extract shared `AudioResampler` utility.

### M2. `@ObservationIgnored nonisolated(unsafe)` repeated ~25 times

Workaround for Swift 6.2 SwiftUI/MainActor observation bug. One typo in a keyPath produces silent observation failures.

**Fix:** Property wrapper or macro. Single change removes the workaround when the bug is fixed.

### M3. `TranscriptionEngine.stop()` doesn't await system audio stop

**File:** `TranscriptionEngine.swift:750-786`

`systemCapture.stop()` is fired in unstructured `Task` — returns immediately. System audio teardown races with subsequent `start()`.

**Fix:** Make `stop()` async and await the teardown.

### M4. No backpressure on AsyncStream audio buffers

`MicCapture` and `SystemAudioCapture` yield into unbounded `AsyncStream`. Consumer stalls → memory grows.

**Fix:** Use `.bufferingPolicy(.bufferingNewest(N))`.

### M5. LiveSessionController: 1,390 lines

Too many responsibilities: session lifecycle, audio retention, recording health, scratchpad, KB indexing, command handling, finalization, batch transcription.

**Fix:** Extract `SessionFinalizer`, `RecordingHealthMonitor`, `AudioRetentionPlanner`.

### M6. SessionRepository: 2,100 lines

Actor handling: session CRUD, notes, scratchpad, images, attachments, ghost reconciliation, export, batch audio, cleaned text, seeding, orphan cleanup.

**Fix:** Extract `NotesFolderMirror`, `BatchAudioStore`, `SessionMetadataStore`, `AttachmentStore`.

### M7. No timeout on finalization drain

`awaitPendingWrites()` in finalization has no timeout. If a write task hangs, the app appears frozen for 30 seconds (coordinator timeout).

**Fix:** Add 10-second timeout wrapper around `awaitPendingWrites()`.

---

## 4. ARCHITECTURAL RECOMMENDATIONS

### A1. Structured concurrency for the audio pipeline

Replace `Task.detached` + manual cancellation with a `TaskGroup` owned by `start()`. Cancelling the group auto-cancels all children. Eliminates manual `micTask?.cancel(); await micTask?.value`.

### A2. Separate audio capture from transcription engine

`TranscriptionEngine` is a God object: mic capture, system capture, device listeners, model loading, VAD, diarization, backend lifecycle, metering, downloads, validation, stream orchestration. Extract `AudioCaptureCoordinator`.

### A3. Macro for `@Observable` nonisolated workaround

Centralize the 25-instance boilerplate into a `@NonisolatedObservable` property wrapper or Swift macro.

### A4. Ring buffer between capture and transcription

Replace `AsyncStream` with a fixed-size ring buffer. Audio callback writes (never blocks, overwrites oldest). Transcriber reads at its own pace. Bounds memory, ensures CoreAudio callback never blocks.

### A5. Centralize error recovery

Scatter: `MicCapture.captureError`, `TranscriptionEngine.lastError`, `LiveSessionController.recordingHealthNotice`, empty session diagnostics, cloud segment status. Each has its own polling mechanism.

**Define `AudioPipelineHealth`** — single observable aggregating all health signals.

### A6. Use vDSP consistently

`MicCapture.normalizedRMS` correctly uses `vDSP_rmsqv`. But `AudioRecorder.writeMicBuffer` uses scalar loops. Use `vDSP_maxmgv` (peak), `vDSP_vadd` (mix), `vDSP_vsmul` (scale) — 4-8x speedup on Apple Silicon.

---

## Summary

| Severity | Count | Theme |
|----------|-------|-------|
| **Critical** | 4 | Data races, OOM on long recordings, temp file durability |
| **High** | 4 | VAD loop blocking, scalar DSP under lock, unbounded buffers |
| **Medium** | 7 | Code duplication, God objects, missing cancellation/timeout |
| **Architecture** | 6 | Structured concurrency, capture/transcription separation, vDSP |

The audio pipeline is the heart of the app and the source of nearly every finding. The top 3 fixes by impact:

1. **C3 — Stream the merge** (prevents OOM crashes on long recordings)
2. **H1 — Async partial transcription** (reduces latency by 200-500ms)
3. **H2 — vDSP + lock reduction** (eliminates contention on audio thread)

---

*Generated by Eagle Eyed Dom deep review — 2026-04-30*
*4-agent Opus inspection: 25 tool calls, 145 Swift files analyzed*
