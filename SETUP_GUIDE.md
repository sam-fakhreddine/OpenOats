# OpenOats ASR Migration: AI Tooling Setup Guide

This guide configures OpenCode, Claude Code, and Codex for the OpenOats ASR migration project. Follow in order.

---

## Prerequisites

- macOS 15.0+ (Sequoia)
- Xcode 16.0+ with Swift 6.2
- Apple Silicon Mac (M1+, M4 Pro preferred)
- 16GB+ RAM (64GB for full M4 Pro experience)
- GitHub access to OpenOats repository

---

## 1. OpenCode Setup

### Installation
```bash
# Install via official installer
curl -fsSL https://get.opencode.ai/install.sh | bash

# Or via Homebrew
brew install opencode

# Verify
opencode --version  # Should show 1.x.x
```

### Project Configuration

Create `.opencode/config.yaml` in the OpenOats repository root:

```yaml
# .opencode/config.yaml
project:
  name: "OpenOats ASR Migration"
  language: swift
  framework: swiftui
  description: "MLX Swift Audio integration with hybrid ANE+GPU backend"
  
ai:
  provider: claude
  model: claude-sonnet-4
  temperature: 0.3
  max_tokens: 200000
  
context:
  include_patterns:
    - "**/*.swift"
    - "**/*.md"
    - "Package.swift"
    - "**/*.xcconfig"
    - "**/*.metal"
    - "asr_feasibility_report*.json"
  exclude_patterns:
    - ".build/"
    - "DerivedData/"
    - "*.caf"
    - "*.m4a"
    - "*.wav"
    - ".git/"
    - "*.xcodeproj/xcuserdata/"
    
build:
  command: "swift build"
  test_command: "swift test"
  clean_command: "swift package clean"
  
lint:
  command: "swift-format lint --recursive --strict Sources/"
  
skills:
  # WFC skills (already loaded)
  - concurrency-patterns
  - swiftui-debugging
  - tdd-workflow
  - logging-setup
  
rules:
  - "Use Swift 6.2 strict concurrency checking"
  - "All public APIs must be Sendable"
  - "Never ignore concurrency warnings"
  - "Run swift test before git commit"
  - "Audio files must not be committed"
```

### Safe Commands Allowlist

Create `.opencode/allowlist.json`:

```json
{
  "allowed_commands": [
    "swift build",
    "swift build -c release",
    "swift test",
    "swift test --filter {pattern}",
    "swift package resolve",
    "swift package clean",
    "swift package describe",
    "swift-format lint",
    "swift-format format",
    "xcodebuild -list",
    "xcodebuild -showBuildSettings",
    "git status",
    "git diff --stat",
    "git diff HEAD~1",
    "git log --oneline -20",
    "git branch -a",
    "find . -name '*.swift' | head -20",
    "ls -la Sources/OpenOats/Transcription/",
    "cat Package.swift | head -30"
  ],
  "allowed_paths": [
    "/Users/*/repos/OpenOats",
    "/Users/*/workspace/OpenOats",
    "/tmp/mlx-audio-spike",
    "/tmp/echo-analysis"
  ],
  "blocked_patterns": [
    "rm -rf /",
    "git push --force",
    "git reset --hard",
    "swift package unedit",
    "sudo",
    "curl | sh",
    "npm install -g"
  ]
}
```

### Initialize OpenCode in Project

```bash
cd /Users/samfakhreddine/repos/OpenOats

# Start OpenCode session
opencode init

# Verify context loading
opencode context check

# Test build
opencode build
```

### OpenCode Usage Patterns

**For strict concurrency work:**
```bash
opencode ask "Fix Swift 6.2 concurrency warnings in TranscriptionEngine.swift"
```

**For protocol conformance:**
```bash
opencode ask "Make MLXWhisperBackend conform to TranscriptionBackend protocol with full Sendable compliance"
```

**For TDD:**
```bash
opencode ask "Write failing test for echo cancellation first, then implement GPUAcousticEchoCanceller"
```

---

## 2. Claude Code Setup

### Installation

```bash
# Via npm
npm install -g @anthropic-ai/claude-code

# Or Homebrew
brew install claude-code

# Authenticate
claude auth
# Follow prompts to enter Anthropic API key
```

### Project Context (CLAUDE.md)

Create `CLAUDE.md` in repository root:

```markdown
# CLAUDE.md - Agent Context for OpenOats ASR Migration

## Project Overview
OpenOats is a macOS meeting transcription app with local ASR (Automatic Speech Recognition).
Currently uses WhisperKit (CoreML), Parakeet, Qwen3, and cloud backends.

**Current Goal**: Add MLX Swift Audio backend for M4 Pro maximum hardware acceleration.

## Critical Technical Context

### Audio Pipeline Architecture
- **Dual-stream capture**: Mic (YOU) + System audio (THEM)
  - Mic: AVAudioEngine tap → 16kHz Float32 mono
  - System: CATapDescription process tap → 48kHz (resampled)
  
- **VAD**: Silero VAD with 4096-sample chunks (256ms @ 16kHz)

- **TranscriptionBackend Protocol**:
  ```swift
  protocol TranscriptionBackend: Sendable {
      var displayName: String { get }
      func checkStatus() -> BackendStatus
      func prepare(onStatus: @Sendable (String) -> Void, 
                   onProgress: @Sendable (Double) -> Void) async throws
      func transcribe(_ samples: [Float], locale: Locale, 
                     previousContext: String?) async throws -> String
      func clearModelCache()
  }
  ```

### Known Critical Bug
**Acoustic Echo Leak**: System audio capture includes mic audio echo.
- Current fix: Post-hoc text similarity (AcousticEchoFilter.swift)
- Needed fix: Real-time audio-level cancellation (GPU FFT-based)
- Delay: ~50-300ms (headphones vs speakers)

### Target Architecture: Hybrid ANE + GPU
| Component | Backend | Hardware | Use Case |
|-----------|---------|----------|----------|
| Mic transcription | WhisperKit CoreML | ANE | Low latency, battery |
| System transcription | MLX Swift Audio | Metal GPU | Q4 quantization, zero-copy |
| Echo cancellation | Custom Metal | GPU | FFT cross-correlation |
| Resampling | Metal Performance Shaders | GPU | 48→16kHz <1ms |

### MLX Swift Audio Patterns

**Model Loading with Q4 Quantization**:
```swift
import MLXAudio

let whisper = STT.whisper(model: .largeTurbo, quantization: .q4)
try await whisper.load { progress in
    // Report download progress 0.0...1.0
}
```

**Zero-Copy Buffer Transfer**:
```swift
// Wrap existing [Float] buffer directly
let mlxArray = MLXArray(
    shape: [samples.count],
    dtype: .float32,
    buffer: UnsafeMutableRawPointer(mutating: samples)
)
let result = try await whisper.transcribe(mlxArray)
```

**Wired Memory Management**:
```swift
import MLX

let policy = WiredSumPolicy()
let weightsTicket = policy.ticket(size: 800_000_000, kind: .reservation)
let inferenceTicket = policy.ticket(size: 200_000_000, kind: .active)
```

### Swift 6.2 Concurrency Requirements
- All `TranscriptionBackend` conformers must be `@Sendable`
- Use `actor` for shared mutable state (model managers)
- Prefer `AsyncStream` over delegation for audio buffers
- Use `Task.detached` with `priority: .userInitiated` for transcription

### Safety Rules (NEVER Violate)
1. **Audio Thread**: Never block audio capture thread with sync work
2. **Memory**: Never exceed 60GB wired memory (leave headroom for OS)
3. **Cancellation**: Always check `Task.isCancelled` in long loops
4. **Testing**: Never modify existing test expectations without review
5. **Git**: Never force push, never commit .caf/.m4a files

### Key Files Reference
- `Transcription/TranscriptionBackend.swift` - Protocol definition
- `Transcription/StreamingTranscriber.swift` - VAD + resampling pipeline
- `Transcription/AcousticEchoFilter.swift` - Post-hoc echo suppression
- `Audio/SystemAudioCapture.swift` - Process tap implementation
- `Audio/MicCapture.swift` - AVAudioEngine tap
- `Transcription/TranscriptionEngine.swift` - Backend orchestration

### Build Commands
```bash
swift build                           # Debug
swift build -c release               # Release  
swift test                           # All tests
swift test --filter Transcription    # Specific tests
swift test --filter Audio            # Audio tests
swift package resolve               # Update deps
```

### Investigation Spike Directories
- `investigations/mlx-audio-spike/` - MLX Audio API validation
- `investigations/echo-analysis/` - Echo delay measurement
- `investigations/metal-resampler/` - GPU resampler benchmark
- `investigations/hybrid-backend/` - ANE+GPU concurrency test
```

### Claude Skills Loading

```bash
# Install Axiom skills (concurrency, memory, performance)
claude /plugin marketplace add CharlesWiltgen/Axiom

# Verify installation
claude /skills list

# Expected output shows:
# - Axiom:concurrency-audit
# - Axiom:memory-audit
# - Axiom:performance-audit
```

### Custom Skill Installation

Create `.claude/skills/metal-audio-ml.md`:

```bash
mkdir -p .claude/skills
cat > .claude/skills/metal-audio-ml.md << 'EOF'
---
name: metal-audio-ml
description: Metal Performance Shaders and MLX Swift for real-time audio processing
triggers:
  - "Metal audio"
  - "MLX Swift"
  - "FFT echo cancellation"
  - "GPU resampling"
  - "unified memory"
---

## MLX Swift Audio API

### STT Initialization
```swift
import MLXAudio

let engine = STT.whisper(
    model: .largeTurbo,      // .base, .small, .largeTurbo, .large
    quantization: .q4        // .q4, .q8, .fp16
)

try await engine.load { progress in
    // progress.fractionCompleted: 0.0...1.0
}
```

### Transcription Methods
```swift
// From audio file
let result = try await engine.transcribe(audioFileURL)

// From raw samples (16kHz Float32)
let mlxArray = MLXArray(samples)
let result = try await engine.transcribe(mlxArray)

// With language hint
let result = try await engine.transcribe(audioFileURL, language: .english)
```

### Memory Management
```swift
import MLX

// Unified memory coordination for M4 Pro
let policy = WiredSumPolicy()

// Reservation: model weights stay resident
let weightsTicket = policy.ticket(
    size: 800_000_000,  // 800MB for Large Turbo Q4
    kind: .reservation
)
await weightsTicket.start()

// Active: inference working memory
let inferenceTicket = policy.ticket(
    size: 200_000_000,  // 200MB per inference
    kind: .active
)

try await inferenceTicket.withWiredLimit {
    let result = try await engine.transcribe(buffer)
}
```

### Metal GPU Resampler
```swift
import Metal

let device = MTLCreateSystemDefaultDevice()!
let commandQueue = device.makeCommandQueue()!
let library = try! device.makeLibrary(source: """
#include <metal_stdlib>
using namespace metal;

kernel void resample48to16(
    device const float *input [[buffer(0)]],
    device float *output [[buffer(1)]],
    constant uint &inputLength [[buffer(2)]],
    uint id [[thread_position_in_grid]]
) {
    float srcIdx = float(id) * 3.0;  // 48kHz / 16kHz = 3
    uint i0 = uint(floor(srcIdx));
    float frac = srcIdx - float(i0);
    
    if (i0 + 1 < inputLength) {
        output[id] = input[i0] * (1.0 - frac) + input[i0 + 1] * frac;
    }
}
""", options: nil)

let pipeline = try! device.makeComputePipelineState(
    function: library.makeFunction(name: "resample48to16")!
)
```

### FFT Echo Cancellation
```swift
import MLX

func cancelEcho(mic: [Float], system: [Float]) -> [Float] {
    // Convert to MLX arrays (zero-copy if possible)
    let mlxMic = MLXArray(mic)
    let mlxSystem = MLXArray(system)
    
    // Cross-correlation via FFT
    let fftMic = fft(mlxMic)
    let fftSystem = fft(mlxSystem)
    let correlation = ifft(fftMic * fftSystem.conjugate())
    
    // Find delay
    let delay = argmax(abs(correlation)).item(Int.self)
    
    // Align and subtract
    let alignedMic = roll(mlxMic, shift: -delay)
    return (mlxSystem - alignedMic * 0.8).asArray(Float.self)
}
```

## Safety Constraints
- Always use `.high` priority for real-time audio GPU work
- Verify buffer alignment to 64-byte cache lines
- Never block audio thread on GPU completion
- Test thermal fallback when ProcessInfo.thermalState > .fair
EOF

# Verify skill is detected
claude /skills refresh
```

### Claude Usage Patterns

**Architecture decisions:**
```bash
claude "Should we use FFT-based or LMS adaptive filter for echo cancellation? Analyze tradeoffs for M4 Pro"
```

**Complex debugging:**
```bash
claude "Why is WhisperKit ANE context switching causing 50ms latency when SpeakerKit also uses ANE?"
```

**Performance investigation:**
```bash
claude "Profile memory bandwidth usage during concurrent WhisperKit + MLX execution. Identify bottlenecks."
```

**Code review:**
```bash
claude /axiom:audit memory  # Run Axiom memory audit
claude /axiom:audit concurrency  # Run Axiom concurrency audit
```

---

## 3. Codex Setup

### Installation

```bash
# Install Codex CLI
npm install -g @openai/codex

# Or use with OpenRouter for Claude API
export OPENROUTER_API_KEY="sk-or-v1-..."

# Configure default model
codex config set model claude-sonnet-4
```

### Configuration File

Create `.codex/config.json`:

```json
{
  "project": {
    "name": "OpenOats ASR Migration",
    "language": "swift",
    "framework": "swiftui",
    "description": "MLX Swift Audio integration with hybrid ANE+GPU backend"
  },
  "ai": {
    "provider": "openrouter",
    "model": "anthropic/claude-sonnet-4",
    "temperature": 0.2,
    "max_tokens": 150000
  },
  "context": {
    "files": [
      "CLAUDE.md",
      "asr_feasibility_report_max_hw_accel.json",
      "OpenOats/Package.swift",
      "OpenOats/Sources/OpenOats/Transcription/TranscriptionBackend.swift"
    ],
    "auto_load": [
      "**/*.swift"
    ]
  },
  "rules": [
    "Swift 6.2 strict concurrency: complete",
    "All types must be Sendable or @unchecked Sendable with justification",
    "Use MLX for GPU-accelerated audio, CoreML for ANE",
    "Never block audio capture thread",
    "Maintain TranscriptionBackend protocol conformance",
    "Run swift test before any git commit"
  ],
  "commands": {
    "build": "swift build",
    "test": "swift test",
    "test-filter": "swift test --filter",
    "lint": "swift-format lint --recursive Sources/",
    "format": "swift-format format --recursive Sources/ -i"
  },
  "git": {
    "require_tests_pass": true,
    "allowed_branches": ["feature/*", "fix/*", "investigation/*"],
    "blocked_patterns": [
      "*.caf",
      "*.m4a", 
      "*.wav",
      "DerivedData/",
      ".build/"
    ]
  }
}
```

### Codex Agent Mode

```bash
# Start research session
codex agent --mode research \
  --task "Investigate MLX Swift Audio integration patterns for OpenOats TranscriptionBackend"

# Or task-specific with context
codex agent --mode architect \
  --context CLAUDE.md \
  --task "Design GPUAcousticEchoCanceller with Metal FFT"
```

### Codex Usage Patterns

**Quick implementation:**
```bash
codex "Implement MLXWhisperBackend conforming to TranscriptionBackend protocol"
```

**Pattern matching:**
```bash
codex "Find all places where [Float] samples are copied and suggest zero-copy MLX alternatives"
```

**Refactoring:**
```bash
codex "Extract Metal resampler from StreamingTranscriber into separate MetalAudioResampler class"
```

---

## 4. Cross-Tool Integration

### Shared Context File

Create `.ai-sync/context.md`:

```markdown
# AI Tool Shared Context

## Active Investigation
- [ ] MLX Audio API surface validation
- [ ] Echo delay measurement and analysis
- [ ] Metal resampler performance benchmark
- [ ] Hybrid ANE+GPU concurrency test

## Decisions Log
| Date | Decision | Tool | Rationale |
|------|----------|------|-----------|
| | | | |

## Current Blockers
None - in setup phase

## Tool Assignments
- **OpenCode**: Swift 6.2 strict concurrency, TDD workflow
- **Claude**: Architecture decisions, complex debugging, MLX integration
- **Codex**: Implementation patterns, refactoring, code generation
```

### Workflow: Investigation → Implementation

```bash
# Phase 1: Investigation (use Claude for complex analysis)
claude "Analyze MLX Swift Audio API for compatibility with TranscriptionBackend protocol"
# → Output: investigations/mlx-audio-spike/REPORT.md

# Phase 2: Validation (use OpenCode for strict code)
opencode ask "Create spike project validating MLX audio transcription with [Float] buffers"
# → Validates: API works, RTF < 0.3, memory ~1GB

# Phase 3: Implementation (use Codex for patterns)
codex "Generate MLXWhisperBackend implementation based on REPORT.md findings"

# Phase 4: Review (use Claude + Axiom)
claude /axiom:audit memory
claude /axiom:audit concurrency
claude "Review MLXWhisperBackend for production readiness"

# Phase 5: Test (use OpenCode for TDD)
opencode ask "Write comprehensive tests for MLXWhisperBackend following TDD"
```

---

## 5. Validation Checklist

### OpenCode Validation
```bash
# Verify configuration
opencode config check

# Test build integration
opencode build

# Test context loading
opencode context check | grep -E "Transcription|Audio"

# Verify skills
opencode skills list | grep -E "concurrency|tdd"
```

### Claude Validation
```bash
# Verify authentication
claude whoami

# Test context loading
claude "What is the TranscriptionBackend protocol in this project?"

# Verify skills
claude /skills list | grep -E "Axiom|metal-audio"

# Test custom skill
claude "How do I use MLXArray for zero-copy audio buffer transfer?"
# Should reference .claude/skills/metal-audio-ml.md
```

### Codex Validation
```bash
# Verify configuration
codex config validate

# Test context loading
codex "What are the key files for audio transcription in this project?"

# Test build integration
codex build
```

### Full Integration Test

```bash
# Run the validation script
chmod +x scripts/validate-ai-tools.sh
./scripts/validate-ai-tools.sh

# Expected output:
# ✅ OpenCode: 1.x.x
# ✅ Claude Code: 0.x.x  
# ✅ Codex: installed
# ✅ Custom skill: metal-audio-ml
# ✅ All configurations valid
```

---

## 6. Troubleshooting

### OpenCode: "Context too large"
```bash
# Reduce context in .opencode/config.yaml
context:
  max_files: 50  # Limit concurrent files
  exclude_patterns:
    - "Tests/**"  # Exclude test files from context
```

### Claude: "Skill not loading"
```bash
# Refresh skills
claude /skills refresh

# Check skill syntax
claude /skills validate .claude/skills/metal-audio-ml.md

# Alternative: inline skill in CLAUDE.md
```

### Codex: "API rate limit"
```bash
# Switch to local model or reduce batch size
codex config set request_timeout 120
codex config set max_concurrent_requests 3
```

### Swift Build Failures
```bash
# Clean and rebuild
swift package clean
swift package resolve
swift build

# Check Xcode command line tools
xcode-select -p
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

---

## 7. Next Steps

1. ✅ **Complete this setup** - All 3 tools configured
2. ✅ **Run validation** - `scripts/validate-ai-tools.sh` passes
3. 🔄 **Begin Investigation Phase**:
   - `investigations/mlx-audio-spike/` (Claude + OpenCode)
   - `investigations/echo-analysis/` (Claude)
   - `investigations/metal-resampler/` (Claude + Codex)
   - `investigations/hybrid-backend/` (All tools)
4. 📋 **Decision Gates G1-G4** - Review findings
5. 🚀 **Implementation Phase** - Begin with MLXWhisperBackend

---

## Quick Reference Card

| Task | Tool | Command |
|------|------|---------|
| Swift 6.2 concurrency fix | OpenCode | `opencode ask "Fix Sendable warnings"` |
| Architecture decision | Claude | `claude "Should we use ANE or GPU for X?"` |
| MLX integration help | Claude | `claude "How do I wire MLXArray to TranscriptionBackend?"` |
| Generate implementation | Codex | `codex "Implement MLXWhisperBackend"` |
| Memory audit | Claude | `claude /axiom:audit memory` |
| Concurrency audit | Claude | `claude /axiom:audit concurrency` |
| TDD cycle | OpenCode | `opencode ask "Write failing test for X"` |
| Refactoring | Codex | `codex "Extract Metal resampler class"` |

---

**Setup Complete!** Proceed to Phase 3: Project Investigation.
