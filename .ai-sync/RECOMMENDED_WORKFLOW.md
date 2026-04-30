# OpenOats ASR Migration: Recommended Workflow

## The "Serial Phases with Validation" Approach

Based on the analysis of tool capabilities and context preservation, this is the **recommended workflow** for the OpenOats project.

---

## Phase Overview

```
┌─────────────────────────────────────────────────────────────────┐
│ PHASE 1: INVESTIGATION                                          │
│ Tool: Claude Code (primary)                                     │
│ Duration: 2-3 days                                              │
│ Output: 4x REPORT.md files                                     │
└──────────────────────────────┬──────────────────────────────────┘
                               │ Validation: G1-G4 decision gates
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│ PHASE 2: ARCHITECTURE                                          │
│ Tool: Claude Code (only)                                        │
│ Duration: 1 day                                                 │
│ Output: DECISIONS.md, INTERFACE_DEFS.md                        │
└──────────────────────────────┬──────────────────────────────────┘
                               │ Handoff: Claude → Codex
                               │ Artifact: handoff-claude-codex.md
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│ PHASE 3: IMPLEMENTATION                                         │
│ Tool: Codex (primary)                                           │
│ Duration: 2-3 days                                              │
│ Output: Working code (compile-able)                            │
└──────────────────────────────┬──────────────────────────────────┘
                               │ Handoff: Codex → OpenCode
                               │ Artifact: handoff-codex-opencode.md
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│ PHASE 4: VERIFICATION                                          │
│ Tool: OpenCode (primary)                                        │
│ Duration: 1-2 days                                              │
│ Output: Production code + tests                                │
└──────────────────────────────┬──────────────────────────────────┘
                               │ (Loop back to Codex if issues)
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│ PHASE 5: DEBUGGING (if needed)                                  │
│ Tool: Claude Code (only)                                        │
│ Duration: As needed                                             │
│ Output: Fixes, optimizations                                     │
└─────────────────────────────────────────────────────────────────┘
```

---

## Detailed Phase Workflows

### Phase 1: Investigation (Claude Code)

**Why Claude**: Complex reasoning, API analysis, performance estimation

#### Investigation 1: MLX Audio Spike
```bash
# Start session
claude

# Load context
claude "@CONTEXT.md Analyze MLX Swift Audio API for TranscriptionBackend compatibility"

# Expected output:
# - API surface documentation
# - Compatibility analysis
# - Sample code for initialization, transcribe, memory management
# - RTF estimate

# Create spike
claude "Create spike project in investigations/mlx-audio-spike/"

# Run spike
# ... manually run spike code ...

# Document findings
claude "Write REPORT.md summarizing findings, blockers, and recommendation"
```

**Output**: `investigations/mlx-audio-spike/REPORT.md`

#### Investigation 2: Echo Analysis
```bash
claude "@CONTEXT.md Design experiment to measure echo delay and spectral characteristics"

# Expected output:
# - Test protocol design
# - Measurement methodology
# - Analysis approach

# Run test (manual)
# Record controlled audio with echo

# Analyze
claude "Analyze recorded audio to measure delay and correlation"

# Document
claude "Write REPORT.md with measurements and cancellation strategy recommendation"
```

**Output**: `investigations/echo-analysis/REPORT.md`

#### Investigation 3: Metal Resampler
```bash
claude "@CONTEXT.md Design Metal Performance Shader for 48→16kHz resampling"

# Expected output:
# - Shader design
# - Benchmark methodology
# - Expected performance vs AVAudioConverter

# Implement spike
claude "Create spike project in investigations/metal-resampler/"

# Run benchmark
# ... manual benchmark ...

# Document
claude "Write REPORT.md with benchmark results and recommendation"
```

**Output**: `investigations/metal-resampler/REPORT.md`

#### Investigation 4: Hybrid Backend
```bash
claude "@CONTEXT.md Design test for concurrent WhisperKit (ANE) + MLX (GPU) execution"

# Expected output:
# - Test harness design
# - Deadlock detection approach
# - Memory bandwidth measurement

# Implement test
claude "Create test project in investigations/hybrid-backend/"

# Run test (manual)

# Document
claude "Write REPORT.md with stability findings"
```

**Output**: `investigations/hybrid-backend/REPORT.md`

#### Phase 1 Completion
```bash
# Update context
claude "Update .ai-sync/CONTEXT.md with investigation summaries"

# Gate review
# Manual review of G1-G4
```

---

### Phase 2: Architecture (Claude Code)

**Why Claude**: Complex tradeoff analysis, protocol design, interaction patterns

**Entry Condition**: G1-G4 gates passed

```bash
# Load all investigation findings
claude "@CONTEXT.md @investigations/mlx-audio-spike/REPORT.md ..."

# Architecture decisions
claude "Design MLXWhisperBackend interface conforming to TranscriptionBackend"
claude "Design GPUAcousticEchoCanceller with Metal FFT"
claude "Design MetalResampler integration point"
claude "Design hybrid backend orchestration (ANE + GPU)"

# Write decisions
claude "Create .ai-sync/DECISIONS.md with all architecture decisions and rationale"

# Define interfaces
claude "Write .ai-sync/INTERFACE_DEFS.md with protocol extensions and method signatures"
```

**Output**: 
- `.ai-sync/DECISIONS.md`
- `.ai-sync/INTERFACE_DEFS.md`

**Handoff Preparation**:
```bash
# Create handoff document
claude "Using HANDOFF_TEMPLATE.md, create .ai-sync/handoffs/claude-codex-phase2.md"
```

---

### Phase 3: Implementation (Codex)

**Why Codex**: Fast code generation, pattern matching, bulk implementation

**Entry Condition**: Handoff document ready

```bash
# Start Codex with context
codex --context .ai-sync/CONTEXT.md \
      --context .ai-sync/DECISIONS.md \
      --context .ai-sync/INTERFACE_DEFS.md \
      --context .ai-sync/handoffs/claude-codex-phase2.md

# Implement MLXWhisperBackend
codex "Implement MLXWhisperBackend.swift conforming to TranscriptionBackend protocol, following DECISIONS.md patterns"

# Implement GPUAcousticEchoCanceller
codex "Implement GPUAcousticEchoCanceller.swift with Metal FFT, following DECISIONS.md algorithm"

# Implement MetalResampler
codex "Implement MetalResampler.swift with Metal Performance Shader, following INTERFACE_DEFS.md"

# Build verification
codex build
```

**Expected**: Code compiles, may have warnings

**Output**:
- `Transcription/MLXWhisperBackend.swift`
- `Transcription/GPUAcousticEchoCanceller.swift`
- `Audio/MetalResampler.swift`
- `Audio/MetalResampler.metal`

**Handoff Preparation**:
```bash
# Create handoff document
codex "Write .ai-sync/handoffs/codex-opencode-phase3.md summarizing implementation status and warnings"
```

---

### Phase 4: Verification (OpenCode)

**Why OpenCode**: Strict concurrency, TDD discipline, WFC skills integration

**Entry Condition**: Implementation compiles, handoff ready

```bash
# Start OpenCode
opencode

# Load context
opencode load .ai-sync/CONTEXT.md
opencode load .ai-sync/handoffs/codex-opencode-phase3.md

# Strict mode verification
opencode ask "Enable Swift 6.2 strict concurrency checking and identify all warnings"

# Fix concurrency
opencode ask "Fix all Sendable warnings in MLXWhisperBackend.swift, use actors where possible"

# TDD: Write tests
opencode ask "Write comprehensive tests for MLXWhisperBackend following TDD workflow"

# TDD: Write tests
opencode ask "Write tests for GPUAcousticEchoCanceller with controlled echo scenarios"

# Run tests
opencode test

# Fix failures
opencode ask "Fix failing tests while maintaining implementation intent"

# Final verification
opencode build
opencode test
opencode lint
```

**Output**:
- Production-ready code
- Comprehensive test suite
- Zero warnings in strict mode

**Validation Criteria**:
- [ ] All tests pass
- [ ] No Sendable warnings
- [ ] No linter warnings
- [ ] Code follows project patterns

---

### Phase 5: Debugging (Claude Code - if needed)

**Why Claude**: Complex debugging, performance profiling, root cause analysis

**Entry Condition**: Performance issues, memory leaks, or integration failures found

```bash
# Load current state
claude "@CONTEXT.md @.ai-sync/handoffs/codex-opencode-phase3.md"

# Debug
claude "Memory leak investigation: Profile MLXWhisperBackend memory usage"
claude "Performance issue: ANE context switching causing latency"
claude "Integration failure: Hybrid backend deadlock scenario"

# Fix
claude "Implement fix for [issue]"

# Update handoff for return to verification
claude "Write .ai-sync/handoffs/claude-opencode-phase5.md"

# Return to Phase 4 (OpenCode) for verification
```

---

## Parallel Track Exception

For independent workstreams, use parallel tracks with daily sync:

### Track A: Backend Implementation (Claude → Codex → OpenCode)
- MLXWhisperBackend
- Hybrid orchestration

### Track B: Audio Processing (Claude → Codex → OpenCode)
- GPUAcousticEchoCanceller
- MetalResampler

**Daily Sync**:
```bash
# End of day, each track
[Tool] "Update .ai-sync/DAILY_SYNC.md with progress and blockers"

# Next day start
[Tool] "Load .ai-sync/DAILY_SYNC.md and .ai-sync/CONTEXT.md"
```

---

## Anti-Patterns (Don't Do This)

### ❌ Anti-Pattern 1: Bounce Within a Task
```
You: "Claude, design echo cancellation"
Claude: [Produces design]
You: "Codex, implement this"
[30 minutes later]
You: "Wait, Claude, I have a question about the design"
Claude: [Has lost context, needs re-explanation]
```
**Result**: 30 minutes of context rebuilding

### ✅ Correct: Complete phase before switching
```
You: "Claude, design echo cancellation and WRITE IT DOWN"
Claude: [Produces design + DECISIONS.md entry]
[Next day]
You: "Codex, implement per DECISIONS.md"
Codex: [Reads file, implements]
```

### ❌ Anti-Pattern 2: No Handoff Document
```
You: [Switch from Claude to Codex mid-task]
Codex: "What were the constraints again?"
You: "Uh, I think we decided..."
[Incorrect implementation]
```
**Result**: Wrong implementation, needs rework

### ✅ Correct: Explicit handoff
```
You: "Claude, write handoff document before I switch to Codex"
Claude: [Produces handoff-claude-codex.md]
You: "Codex, read this handoff document"
Codex: [Correctly understands context]
```

### ❌ Anti-Pattern 3: All Tools Active
```
You: "Everyone work on this together!"
[Chaos, conflicting implementations, context fragmentation]
```
**Result**: Unmergeable code, lost work

### ✅ Correct: One tool per phase
```
You: "Claude: architecture. Codex: implementation. OpenCode: verification."
[Sequential, tracked, mergeable]
```

---

## Tool Selection Quick Reference

| Task | Use | Don't Use |
|------|-----|-----------|
| API research | Claude | Codex |
| Architecture decision | Claude | OpenCode |
| Algorithm design | Claude | Codex |
| Protocol conformance | OpenCode | Codex |
| Bulk implementation | Codex | OpenCode |
| Refactoring | Codex | OpenCode |
| Strict mode fixes | OpenCode | Codex |
| Test writing | OpenCode | Codex |
| Debug complex issue | Claude | Codex |
| Performance analysis | Claude | OpenCode |
| Memory leak hunt | Claude | Codex |
| Build warning cleanup | OpenCode | Claude |

---

## Success Metrics

| Metric | Target |
|--------|--------|
| Context loss events | 0 per phase |
| Handoff documents | 1 per phase transition |
| Tool switches per phase | 1 (entry only) |
| Re-work due to context loss | 0 |
| Phase completion time | Within estimate |
| Final code quality | Production-ready |

---

## Checklist: Starting a Phase

- [ ] Previous phase handoff document exists
- [ ] CONTEXT.md is up to date
- [ ] Tool configuration validated
- [ ] Relevant files accessible to tool
- [ ] Test question asked and validated
- [ ] Success criteria defined

## Checklist: Completing a Phase

- [ ] All deliverables produced
- [ ] Quality criteria met
- [ ] Handoff document written
- [ ] CONTEXT.md updated
- [ ] Next phase tool ready
- [ ] Validation test passed

---

## Summary

**Core Principle**: One tool per phase, explicit handoffs, no bouncing.

**OpenOats Phases**:
1. Investigation → **Claude** (reasoning, analysis)
2. Architecture → **Claude** (design, decisions)
3. Implementation → **Codex** (code generation)
4. Verification → **OpenCode** (strict mode, TDD)
5. Debugging → **Claude** (if needed)

**Files to Maintain**:
- `.ai-sync/CONTEXT.md` (master state)
- `.ai-sync/DECISIONS.md` (architecture)
- `.ai-sync/handoffs/*.md` (phase transitions)

**Result**: Maximum context preservation, minimum rework, consistent code quality.
