# OpenOats ASR Migration

**Status**: Environment setup complete → Beginning Investigation  
**Date**: 2024-06-XX  
**Tool**: OpenCode + Kimi K2.5 Turbo  

---

## Current Focus

**Phase 1**: Investigation - MLX Swift Audio API  
**Working on**: Create spike project, validate API compatibility  
**Next gate**: G1 - MLX Audio viable? (RTF < 0.3, API compatible)

---

## Critical Context

### The Bug (Priority: CRITICAL)
System audio capture includes mic audio echo → transcribed as "THEM" when it's actually "YOU"
- Current fix: Text-based `AcousticEchoFilter.swift` (post-hoc, insufficient)
- Needed fix: Real-time GPU FFT-based echo cancellation
- Typical delay: 50-300ms (headphones vs speakers)

### Target Architecture
Hybrid ANE + GPU for M4 Pro 64GB:
- Mic audio → WhisperKit CoreML → ANE (battery efficient)
- System audio → MLX Swift Audio → Metal GPU (Q4 quantization, zero-copy)
- Echo cancellation → Metal GPU FFT (real-time subtraction)

### Key Technical Facts
1. **TranscriptionBackend protocol** is LAW - all backends must conform
2. **Swift 6.2 strict concurrency** - everything must be Sendable
3. **16kHz Float32 mono** - standard audio format for all backends
4. **VAD**: Silero with 4096-sample chunks (256ms @ 16kHz)
5. **Never block audio thread** - capture is real-time

---

## File Map

### Core Protocol
- `Transcription/TranscriptionBackend.swift` - Backend interface (protocol)
- `Transcription/StreamingTranscriber.swift` - Audio/VAD pipeline
- `Transcription/TranscriptionEngine.swift` - Orchestrates backends

### Audio Capture
- `Audio/MicCapture.swift` - AVAudioEngine tap (YOU audio)
- `Audio/SystemAudioCapture.swift` - CATapDescription (THEM audio) [BUG SOURCE]
- `Audio/AudioRecorder.swift` - File recording

### Echo Handling (Current)
- `Transcription/AcousticEchoFilter.swift` - Post-hoc text similarity [INSUFFICIENT]
- `TranscriptStore.swift` - Text-level deduplication

### Existing Backends
- `Transcription/WhisperKitBackend.swift` - CoreML/ANE (reference)
- `Transcription/WhisperKitManager.swift` - CoreML wrapper
- `Transcription/Qwen3Backend.swift` - FluidAudio
- `Transcription/ParakeetBackend.swift` - FluidAudio

### To Create
- `Transcription/MLXWhisperBackend.swift` - NEW (MLX Swift)
- `Transcription/GPUAcousticEchoCanceller.swift` - NEW (Metal FFT)
- `Audio/MetalResampler.swift` - NEW (GPU resampling)

---

## Decisions Log

| Date | Decision | Rationale | Status |
|------|----------|-----------|--------|
| | | | |

---

## Today's Work

### Investigation 1: MLX Swift Audio
**Goal**: Verify API works with TranscriptionBackend protocol

Tasks:
- [ ] Create `investigations/mlx-audio-spike/`
- [ ] Add mlx-swift-audio dependency
- [ ] Test `STT.whisper(model: .largeTurbo, quantization: .q4)`
- [ ] Test `transcribe()` with `[Float]` samples at 16kHz
- [ ] Verify thread-safety (actor isolation)
- [ ] Measure RTF on M4 Pro

Success criteria:
- ✅ API compatible with TranscriptionBackend
- ✅ RTF < 0.3 (5x faster than real-time)
- ✅ Memory < 1.2GB for Large Turbo Q4
- ✅ Thread-safe for dual-stream use

---

## Blockers

**None currently** - starting investigation phase

---

## Next 3 Days

1. **Today**: MLX Audio spike (G1 validation)
2. **Tomorrow**: Echo analysis (G2 validation) 
3. **Day 3**: Metal resampler (G3 validation) → Hybrid backend test (G4)

---

## References

- `asr_feasibility_report_max_hw_accel.json` - Full technical analysis
- `SETUP_GUIDE.md` - Tool configuration
- `SIMPLIFIED_WORKFLOW.md` - This workflow

---

## Quick Commands

```bash
# Build
swift build

# Test
swift test

# Test specific
swift test --filter Transcription

# Strict mode
swift build -Xswiftc -strict-concurrency=complete
```

---

## Escape Hatches (Use Rarely)

| Situation | Tool | Command |
|-----------|------|---------|
| Stuck after 3 attempts | Claude | `claude "@CONTEXT.md Stuck on [problem]"` |
| Memory audit needed | Claude | `claude /axiom:audit memory` |
| Bulk refactor (20+ files) | Codex | `codex "[refactor task]"` |

---

## Update Log

| Date | What Changed | Author |
|------|--------------|--------|
| 2024-06-XX | Initial context | Setup |

---

**Next Action**: Create `investigations/mlx-audio-spike/` and begin API validation
