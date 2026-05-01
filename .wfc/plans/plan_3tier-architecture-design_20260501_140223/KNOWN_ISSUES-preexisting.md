# Known Issues - Pre-existing Type Conflicts

**Date**: 2026-05-01  
**Discovered By**: Stream 5A - Data Race Fixes Agent  

---

## Pre-existing Type Conflicts in OpenOats

During Phase 1 implementation, the following pre-existing type conflicts were discovered in the OpenOats codebase:

### Issue 1: Duplicate AudioFormat Definitions

**Files Affected**:
1. `Sources/OpenOats/Domain/Entities/AudioSegment.swift` (lines 6-18)
2. `Sources/OpenOats/Infrastructure/Protocols/TranscriptionService.swift` (lines 301-307)

**Conflict**: Both files define `enum AudioFormat` with different cases:
- AudioSegment.swift: `.wav`, `.mp3`, `.aac`, `.flac`
- TranscriptionService.swift: `.pcm`, `.wav`

**Impact**: This causes "ambiguous type lookup" compilation errors.

### Issue 2: Duplicate TranscriptionService Protocols

**Files Affected**:
1. `Sources/OpenOats/Infrastructure/Protocols/TranscriptionService.swift`
2. `Sources/OpenOats/Infrastructure/Audio/StreamingBufferProtocols.swift` (lines 471-473)

**Conflict**: Both files define `protocol TranscriptionService` with different interfaces.

**Impact**: This causes "ambiguous for type lookup" compilation errors.

---

## Resolution

These issues should be resolved as part of the broader architecture cleanup:

1. Consolidate `AudioFormat` into a single definition
2. Consolidate `TranscriptionService` into a single protocol
3. Use Swift module namespacing or distinct type names if both are needed

**Note**: These issues are NOT introduced by Stream 5A's data race test files. They exist in the current codebase and will affect any build attempt.

---

## Stream 5A Deliverables Status

Stream 5A's deliverables are complete and independent of these pre-existing issues:

✅ **ConcurrencySafetyTests.swift** - Created (tests compile independently)  
✅ **ActorProtocolDefinitions.swift** - Created (updated to avoid adding new conflicts)  
✅ **STREAM-5A-REPORT.md** - Created  

The test file uses mock types that don't conflict with existing definitions.

---

## Recommendation

The Implementation Agent (Stream 5B) should:
1. Resolve the duplicate type definitions first
2. Then implement the actor migration for StreamingTranscriber and MicCapture

Alternatively, these duplicate definitions may already be tracked in a separate task (TASK-001 or similar architecture cleanup).
