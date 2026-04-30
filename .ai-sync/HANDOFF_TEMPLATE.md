# Handoff Document Template

Use this template when switching between AI tools to preserve context.

---

## Handoff From: [SOURCE_TOOL] To: [TARGET_TOOL]

**Date**: YYYY-MM-DD  
**Session ID**: [optional]  
**Previous Tool Output**: `.ai-sync/handoffs/[source]-[date]-[topic].md`

---

## What Was Accomplished

### Completed Tasks
- [ ] Task 1: [Description]
- [ ] Task 2: [Description]

### Code Changes
| File | Change Type | Summary |
|------|-------------|---------|
| `Path/File.swift` | New/Modified/Deleted | [One-line summary] |

### Key Decisions Made
1. **Decision**: [What was decided]
   - **Rationale**: [Why]
   - **Alternatives Rejected**: [What else was considered]
   - **Implications**: [What this affects]

2. **Decision**: [Another decision]
   - **Rationale**: [Why]

---

## Current State

### Architecture Understanding
[Describe the mental model of the system as it exists now]

```
[ASCII diagram or bullet points showing current state]
```

### Open Issues / Blockers
1. **[BLOCKER]** [Description] - [Impact] - [Next step]
2. **[WARNING]** [Description] - [Potential issue]

### Questions for Next Tool
1. [Specific question about implementation detail]
2. [Question about tradeoff]

---

## Context Given to Next Tool

### Files Loaded
- `File1.swift` - [Why this file matters]
- `File2.swift` - [Why this file matters]

### Explicit Instructions
- [Specific constraint or requirement]
- [Pattern to follow]
- [Anti-pattern to avoid]

### Code Patterns Established
```swift
// Pattern 1: [Name]
// Use when: [Situation]
// Rationale: [Why]
[Code example]

// Pattern 2: [Name]
// Use when: [Situation]
// Rationale: [Why]
[Code example]
```

---

## Validation Checklist for Next Tool

Before proceeding, verify:
- [ ] Next tool has loaded `.ai-sync/CONTEXT.md`
- [ ] Next tool has loaded this handoff document
- [ ] Next tool can see relevant source files
- [ ] Next tool understands the constraints

**Test Question**: "Summarize what the previous tool accomplished and what you're supposed to do next."  
**Expected Answer**: [What they should say]

---

## Handoff Signature

**Source Tool**: [Tool name and version]  
**Output Quality**: [High/Medium/Low]  
**Confidence**: [High/Medium/Low]  
**Recommended Next Tool**: [Which tool should take over]

---

## Example Handoff (Claude → Codex)

### Handoff From: Claude To: Codex

**Date**: 2024-06-15  
**Topic**: MLXWhisperBackend Implementation  

#### What Was Accomplished
- Designed MLXWhisperBackend architecture
- Verified MLX Swift Audio API compatibility with TranscriptionBackend
- Established memory management patterns (WiredSumPolicy)

#### Code Changes
| File | Change Type | Summary |
|------|-------------|---------|
| N/A | Design doc | Architecture in `.ai-sync/DECISIONS.md` |

#### Key Decisions
1. **Decision**: Use MLX Q4 quantization for 4x memory bandwidth reduction
   - **Rationale**: Large Turbo Q4 = 200MB vs 800MB CoreML
   - **Rejected**: FP16 (too slow), Q8 (compromise, no need)
   - **Implications**: Slight quality loss acceptable for RTF gain

2. **Decision**: Thread-safe via actor isolation (MLX is actor-based)
   - **Rationale**: MLX STT.whisper uses @MainActor for load()
   - **Rejected**: Manual locking (complex), unchecked Sendable (unsafe)
   - **Implications**: Backend operations serialized, but GPU parallel

#### Current State
MLXWhisperBackend needs implementation. Interface defined:

```swift
final class MLXWhisperBackend: TranscriptionBackend, @unchecked Sendable {
    private let variant: MLXWhisperVariant
    private let quantization: MLXQuantization
    private var engine: STT.WhisperEngine?
    
    func prepare(...) async throws
    func transcribe(_ samples: [Float], ...) async throws -> String
}
```

#### Open Issues
1. **[WARNING]** MLXArray initialization from [Float] may copy - verify zero-copy path

#### Context for Codex
- **Files to load**: `TranscriptionBackend.swift`, `WhisperKitBackend.swift` (reference)
- **Pattern to follow**: Mimic WhisperKitBackend structure exactly
- **Use**: `import MLXAudio`, `STT.whisper(model:quantization:)`

#### Validation
- [ ] Codex has loaded `CONTEXT.md`
- [ ] Codex has loaded `DECISIONS.md`
- [ ] Codex can see `TranscriptionBackend.swift`

**Test**: "How should MLXWhisperBackend conform to TranscriptionBackend?"  
**Expected**: Actor-isolated properties, async transcribe, MLXArray zero-copy

#### Signature
**Source**: Claude Sonnet 4  
**Quality**: High  
**Confidence**: High  
**Next Tool**: Codex (implementation)

---

## Example Handoff (Codex → OpenCode)

### Handoff From: Codex To: OpenCode

**Date**: 2024-06-15  
**Topic**: Swift 6.2 Concurrency Verification  

#### What Was Accomplished
- Implemented MLXWhisperBackend.swift
- Implemented GPUAcousticEchoCanceller.swift
- All files compile

#### Code Changes
| File | Change Type | Summary |
|------|-------------|---------|
| `MLXWhisperBackend.swift` | New | MLX backend implementation |
| `GPUAcousticEchoCanceller.swift` | New | Metal FFT echo cancellation |

#### Key Decisions
- Used `@unchecked Sendable` with manual verification for performance
- Used `MLXArray` direct buffer wrapping (zero-copy confirmed)

#### Current State
Code compiles but has 47 Sendable warnings. Need strict concurrency compliance.

#### Open Issues
1. **[BLOCKER]** Sendable warnings prevent strict mode build

#### Context for OpenCode
- **Files**: `MLXWhisperBackend.swift`, `GPUAcousticEchoCanceller.swift`
- **Goal**: Fix all warnings, maintain functionality
- **Constraint**: Use actors where possible, @_unsafeSendable with justification if needed

#### Signature
**Source**: Codex  
**Quality**: Medium (needs cleanup)  
**Confidence**: Medium (warnings present)  
**Next Tool**: OpenCode (strict mode fix)

---

## Usage Instructions

1. **Fill out this template** at the end of each tool session
2. **Save to** `.ai-sync/handoffs/[source]-[date]-[brief-topic].md`
3. **Update** `.ai-sync/CURRENT_FOCUS.md` with new handoff location
4. **Next tool**: Load both `CONTEXT.md` and the handoff document
5. **Validate**: Ask "What was accomplished and what's next?"
6. **Proceed**: Only if validation answer matches expected

---

## Quick Handoff (Minimal)

For simple switches, use this minimal format:

```markdown
# Handoff: [Source] → [Target]
**Date**: YYYY-MM-DD

## Done
- [X] [What was done]

## Next
- [ ] [What to do]

## Files
- `Path/File.swift`

## Key Point
[One critical thing to know]
```

Example:
```markdown
# Handoff: Claude → Codex
**Date**: 2024-06-15

## Done
- [X] Decided to use FFT not LMS for echo cancellation

## Next
- [ ] Implement FFT-based correlation in Metal

## Files
- `.ai-sync/DECISIONS.md` (see Echo Cancellation section)

## Key Point
Use radix-2 Cooley-Tukey FFT, 4096-sample frames, overlap 50%
```
