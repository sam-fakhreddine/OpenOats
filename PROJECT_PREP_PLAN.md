# OpenOats ASR Migration: Project Preparation Plan

## Phase 1: Development Environment Setup

### 1.1 macOS & Hardware Prerequisites
| Component | Requirement | Verification Command |
|-----------|-------------|---------------------|
| **macOS Version** | macOS 15.0+ (Sequoia) | `sw_vers -productVersion` |
| **Xcode** | Xcode 16.0+ with Swift 6.2 | `xcodebuild -version` |
| **Hardware** | Apple Silicon (M1+), M4 Pro preferred | `sysctl -n machdep.cpu.brand_string` |
| **Memory** | 16GB minimum, 64GB preferred | `system_profiler SPHardwareDataType` |
| **Storage** | 50GB free (models + build artifacts) | `df -h /` |

### 1.2 Xcode Configuration
```bash
# Verify Swift 6.2 toolchain
swift --version  # Should show 6.2.x

# Enable strict concurrency checking
# In Xcode: Build Settings → Swift Compiler - Language → Strict Concurrency Check = Complete

# Install CoreML Tools for model conversion (optional)
pip install coremltools
```

### 1.3 Repository Setup
```bash
# Clone OpenOats repository
git clone https://github.com/yazinsai/OpenOats.git
cd OpenOats

# Verify Package.swift dependencies resolve
swift package resolve

# Build the project to verify environment
swift build

# Run existing tests to establish baseline
swift test
```

### 1.4 Audio System Verification
```bash
# Verify CoreAudio access permissions
# System Settings → Privacy & Security → Microphone (grant to terminal/IDE)
# System Settings → Privacy & Security → System Audio Recording (grant to terminal/IDE)

# Test audio device enumeration (build and run diagnostic)
swift run --package-path OpenOats -Xswiftc -DDEBUG AudioDeviceList
```

---

## Phase 2: AI Tooling Setup (First Artifact)

### 2.1 OpenCode Configuration

#### Installation
```bash
# Install OpenCode CLI
curl -fsSL https://get.opencode.ai/install.sh | bash

# Or via Homebrew
brew install opencode

# Verify installation
opencode --version
```

#### OpenCode Project Configuration
Create `.opencode/config.yaml` in OpenOats repository:
```yaml
# .opencode/config.yaml
project:
  name: "OpenOats ASR Migration"
  language: swift
  framework: swiftui
  
ai:
  provider: claude
  model: claude-sonnet-4
  temperature: 0.3  # Lower for code generation
  
context:
  max_tokens: 200000
  include_patterns:
    - "**/*.swift"
    - "**/*.md"
    - "Package.swift"
    - "**/*.xcconfig"
  exclude_patterns:
    - ".build/"
    - "DerivedData/"
    - "*.caf"
    - "*.m4a"
    - ".git/"
    
skills:
  - wfc-concurrency-patterns
  - wfc-swiftui-debugging
  - wfc-tdd-workflow
  
commands:
  build: "swift build"
  test: "swift test"
  lint: "swift-format lint --strict"
  format: "swift-format"
```

#### OpenCode Safe Commands
Create `.opencode/allowlist.json`:
```json
{
  "allowed_commands": [
    "swift build",
    "swift test",
    "swift package resolve",
    "swift package clean",
    "xcodebuild -list",
    "git status",
    "git diff",
    "git log --oneline -10"
  ],
  "allowed_paths": [
    "/Users/*/repos/OpenOats",
    "/tmp"
  ]
}
```

### 2.2 Claude Code Configuration

#### Claude Code Installation
```bash
# Install Claude Code CLI
npm install -g @anthropic-ai/claude-code

# Or via Homebrew
brew install claude-code

# Authenticate
claude auth
```

#### Claude Project Setup
Create `CLAUDE.md` in repository root:
```markdown
# CLAUDE.md - Agent Context for OpenOats

## Project Overview
OpenOats is a macOS meeting transcription app with local ASR (Automatic Speech Recognition).
- **Language**: Swift 6.2
- **Platform**: macOS 15.0+
- **Architecture**: MVVM with AsyncStream audio pipeline

## Critical Context
1. **Audio Pipeline**: Dual-stream capture (mic + system audio)
   - Mic: AVAudioEngine tap → 16kHz Float32
   - System: CATapDescription process tap → 48kHz (resampled to 16kHz)
   
2. **Current Backends**: 
   - WhisperKit (CoreML/ANE) - preferred for battery
   - Parakeet/Qwen3 (FluidAudio) - existing
   - Cloud: AssemblyAI, ElevenLabs
   
3. **Target Addition**: MLX Swift Audio (Metal GPU)
   - For M4 Pro maximum hardware utilization
   - Hybrid ANE+GPU execution
   
4. **Known Bug**: Acoustic echo - mic audio leaks into system audio stream
   - Currently post-hoc text filter (insufficient)
   - Needs real-time audio-level cancellation

## Architecture Patterns
- **TranscriptionBackend Protocol**: All ASR engines conform
- **StreamingTranscriber**: AsyncStream consumer with VAD (Silero)
- **TranscriptionEngine**: Orchestrates dual backends (mic + system)

## Safety Rules
- NEVER modify existing protocol conformance tests
- ALWAYS run swift test before git operations
- NEVER commit without git diff review
- Audio files (.caf, .m4a) must be gitignored

## Build Commands
```bash
swift build                    # Debug build
swift build -c release         # Release build
swift test                     # Run tests
swift test --filter Audio      # Run audio-specific tests
```

## Key Files
- `Transcription/TranscriptionBackend.swift` - Protocol definition
- `Transcription/StreamingTranscriber.swift` - Audio/VAD pipeline
- `Audio/SystemAudioCapture.swift` - Process tap implementation
- `Audio/MicCapture.swift` - AVAudioEngine implementation
```

#### Claude Skills Loading
```bash
# Install Axiom skills (concurrency, memory auditing)
claude /plugin marketplace add CharlesWiltgen/Axiom

# Install audio-production plugin (VAD, denoising)
claude /plugin marketplace add danielrosehill/claude-code-plugins --plugin audio-production

# Verify skill installation
claude /skills list
```

#### Claude Custom Skills for OpenOats
Create `.claude/skills/metal-audio-ml.md`:
```markdown
---
name: metal-audio-ml
description: Metal Performance Shaders and MLX Swift for real-time audio processing on Apple Silicon
triggers:
  - "Metal audio"
  - "FFT"
  - "echo cancellation"
  - "MLX Swift"
  - "GPU resampling"
  - "unified memory"
  - "real-time audio"
---

## MLX Swift Audio Integration

### Model Loading
```swift
import MLXAudio

// Q4 quantization for 4x memory bandwidth reduction
let whisper = STT.whisper(model: .largeTurbo, quantization: .q4)
try await whisper.load { progress in
    print("Loading: \(Int(progress.fractionCompleted * 100))%")
}
```

### Zero-Copy Buffer Transfer
```swift
// Wrap existing Float32 buffer without copy
let mlxArray = MLXArray(
    shape: [samples.count], 
    dtype: .float32,
    buffer: UnsafeMutableRawPointer(mutating: samples)
)
```

### FFT-Based Echo Cancellation
```swift
import MLX

// Cross-correlation via FFT
let fftMic = fft(mlxMicBuffer)
let fftSystem = fft(mlxSystemBuffer)
let correlation = ifft(fftMic * fftSystem.conjugate())
let delay = argmax(correlation)
```

### Metal Performance Shaders Audio
```swift
import Metal

// Resample 48kHz → 16kHz on GPU
let resampleShader = """
#include <metal_stdlib>
kernel void resample(
    device const float *input [[buffer(0)]],
    device float *output [[buffer(1)]],
    uint id [[thread_position_in_grid]]
) {
    float srcIdx = float(id) * 3.0; // 48kHz/16kHz = 3
    // Linear interpolation
    float frac = srcIdx - floor(srcIdx);
    uint i0 = uint(floor(srcIdx));
    output[id] = input[i0] * (1.0 - frac) + input[i0+1] * frac;
}
"""
```

## Safety Constraints
- ALWAYS verify buffer alignment (64-byte cache line)
- NEVER block audio thread with Metal completion handlers
- Use .high priority command queue for real-time audio
- Validate sample rate before Metal buffer creation
```

### 2.3 Codex (GitHub Copilot/Codex CLI) Configuration

#### Codex CLI Setup
```bash
# Install Codex CLI
npm install -g @openai/codex

# Configure with OpenAI API key
export OPENAI_API_KEY="sk-..."

# Or use Claude API via OpenRouter
export OPENROUTER_API_KEY="sk-or-..."
```

#### Codex Configuration File
Create `.codex/config.json`:
```json
{
  "project": {
    "name": "OpenOats ASR Migration",
    "language": "swift",
    "framework": "swiftui"
  },
  "context": {
    "files": [
      "CLAUDE.md",
      "asr_feasibility_report_max_hw_accel.json",
      "OpenOats/Package.swift"
    ]
  },
  "rules": [
    "Always use Swift 6.2 concurrency patterns",
    "Never ignore Sendable warnings",
    "Use MLX for GPU-accelerated audio, CoreML for ANE",
    "Maintain TranscriptionBackend protocol conformance"
  ],
  "commands": {
    "build": "swift build",
    "test": "swift test",
    "lint": "swift-format lint"
  }
}
```

#### Codex Agent Mode for Investigation
```bash
# Start investigation session
codex agent --mode research

# Or task-specific
codex agent --task "Investigate MLX Swift Audio integration patterns for real-time transcription"
```

### 2.4 Unified AI Tooling Workflow

#### Recommended Tool Assignment
| Task Type | Primary Tool | Secondary | Why |
|-----------|--------------|-----------|-----|
| Architecture Planning | Claude Code | Codex | Complex reasoning, protocol design |
| Swift 6.2 Concurrency | OpenCode | Claude | Strict concurrency compliance |
| MLX/Metal Audio | Claude (custom skill) | OpenCode | Specialized domain knowledge |
| Testing & TDD | OpenCode | Claude | Red-green-refactor discipline |
| Performance Audit | Claude + Axiom | Codex | Memory leak detection |
| Code Review | Codex | Claude | Pattern matching, style |

#### Cross-Tool Context Sync
Create `.ai-sync/context.md`:
```markdown
# AI Tool Shared Context

## Current Investigation Focus
- [ ] Acoustic echo cancellation strategy
- [ ] MLX Swift Audio API surface
- [ ] Hybrid CoreML+MLX orchestration
- [ ] Metal GPU resampler implementation
- [ ] Unified memory WiredSumPolicy integration

## Decisions Pending
1. Echo cancellation: GPU FFT vs CPU vDSP?
2. Model quantization: Q4 for all or adaptive Q4/Q8?
3. Thermal fallback: ANE→MLX or ANE→CPU?

## Blockers
- None (environment setup phase)
```

---

## Phase 3: Project Investigation Structure

### 3.1 Pre-Implementation Investigation

Before writing production code, investigate these areas:

#### Investigation 1: MLX Swift Audio API Surface
**Goal**: Verify API compatibility with OpenOats' TranscriptionBackend protocol

**Tasks**:
1. Install mlx-swift-audio locally
2. Create spike project: `MLXAudioSpike/` 
3. Test STT.whisper() initialization with Q4 quantization
4. Test transcribe() with [Float] samples at 16kHz
5. Measure memory footprint for Large Turbo Q4
6. Test thread-safety (actor isolation)

**Deliverable**: `investigations/mlx-audio-spike/REPORT.md`

#### Investigation 2: Acoustic Echo Characterization
**Goal**: Measure echo delay and spectral characteristics

**Tasks**:
1. Record controlled test: Speak while meeting app plays back
2. Measure delay between mic capture and system audio loopback
3. Analyze frequency response of echo path
4. Test correlation algorithms (vDSP vs MLX FFT)

**Deliverable**: `investigations/echo-analysis/REPORT.md`

#### Investigation 3: Metal GPU Resampler Performance
**Goal**: Validate <1ms resampling for 48kHz→16kHz conversion

**Tasks**:
1. Create Metal shader for linear interpolation resampling
2. Benchmark against AVAudioConverter (CPU)
3. Test with varying buffer sizes (1024, 4096, 16384 samples)
4. Verify numerical accuracy (SNR measurement)

**Deliverable**: `investigations/metal-resampler/REPORT.md`

#### Investigation 4: Hybrid Backend Orchestration
**Goal**: Verify ANE+GPU concurrent execution doesn't deadlock

**Tasks**:
1. Create test harness with WhisperKit (CoreML) + MLX simultaneously
2. Test command queue isolation
3. Measure RTF for each backend in isolation vs concurrent
4. Profile memory bandwidth usage

**Deliverable**: `investigations/hybrid-backend/REPORT.md`

### 3.2 Investigation Artifacts Structure

```
investigations/
├── mlx-audio-spike/
│   ├── Package.swift          # Spike dependencies
│   ├── Sources/
│   │   └── main.swift         # Spike code
│   ├── REPORT.md              # Findings
│   └── BENCHMARKS.json        # Performance data
├── echo-analysis/
│   ├── test-recordings/       # Sample audio files
│   ├── analysis.swift         # Correlation analysis
│   ├── delay-measurements.csv
│   └── REPORT.md
├── metal-resampler/
│   ├── Shaders.metal          # Resample kernel
│   ├── benchmark.swift
│   └── REPORT.md
└── hybrid-backend/
    ├── Package.swift
    ├── Sources/
    └── REPORT.md
```

### 3.3 Decision Gates

| Gate | Criteria | Proceed If |
|------|----------|--------------|
| G1: MLX Audio Viable | MLXAudio.transcribe() works with [Float] buffers, RTF < 0.3 | API compatible |
| G2: Echo Solvable | Correlation peak detectable, delay < 500ms | Can implement real-time AEC |
| G3: Metal Resampler Valid | Resample 4096 samples < 1ms, SNR > 60dB | Better than CPU |
| G4: Hybrid Stable | No deadlocks in 10min concurrent test, RTF maintained | Production ready |

---

## Phase 4: First Artifact - Complete Setup Guide

### 4.1 Quick Start Script

Create `scripts/setup-dev-env.sh`:
```bash
#!/bin/bash
set -e

echo "=== OpenOats ASR Migration Dev Environment Setup ==="

# Check macOS version
if ! sw_vers -productVersion | grep -E "^1[5-9]\." > /dev/null; then
    echo "❌ macOS 15.0+ required"
    exit 1
fi
echo "✅ macOS version OK"

# Check Xcode
if ! xcodebuild -version | grep -E "Xcode 1[6-9]" > /dev/null; then
    echo "❌ Xcode 16.0+ required"
    exit 1
fi
echo "✅ Xcode version OK"

# Check Swift
if ! swift --version | grep -E "Swift version 6\.[2-9]" > /dev/null; then
    echo "❌ Swift 6.2+ required"
    exit 1
fi
echo "✅ Swift version OK"

# Clone repo
if [ ! -d "OpenOats" ]; then
    git clone https://github.com/yazinsai/OpenOats.git
fi
cd OpenOats

# Build project
echo "Building OpenOats..."
swift package resolve
swift build

# Run tests
echo "Running baseline tests..."
swift test 2>&1 | head -50

echo ""
echo "=== Setup Complete ==="
echo "Next steps:"
echo "1. Configure AI tools (see SETUP_GUIDE.md)"
echo "2. Run investigations (see Phase 3)"
echo "3. Review feasibility report: cat asr_feasibility_report_max_hw_accel.json"
```

### 4.2 AI Tool Setup Validation

Create `scripts/validate-ai-tools.sh`:
```bash
#!/bin/bash

echo "=== AI Tooling Validation ==="

# OpenCode
if command -v opencode &> /dev/null; then
    echo "✅ OpenCode: $(opencode --version)"
else
    echo "❌ OpenCode not found. Install: curl -fsSL https://get.opencode.ai/install.sh | bash"
fi

# Claude Code
if command -v claude &> /dev/null; then
    echo "✅ Claude Code: $(claude --version)"
else
    echo "❌ Claude Code not found. Install: npm install -g @anthropic-ai/claude-code"
fi

# Codex
if command -v codex &> /dev/null; then
    echo "✅ Codex: installed"
else
    echo "❌ Codex not found. Install: npm install -g @openai/codex"
fi

# Check skills
if [ -f ".claude/skills/metal-audio-ml.md" ]; then
    echo "✅ Custom skill installed: metal-audio-ml"
else
    echo "⚠️  Custom skill missing: .claude/skills/metal-audio-ml.md"
fi

echo ""
echo "Run 'claude /skills list' to verify skill loading"
```

### 4.3 First Artifact: Complete Setup Guide

**Output**: `SETUP_GUIDE.md` (comprehensive, 1-2 pages)

---

## Timeline

| Phase | Duration | Deliverable |
|-------|----------|-------------|
| 1.1 - Environment | 30 min | Working `swift build` |
| 1.2 - OpenCode | 15 min | `.opencode/config.yaml` |
| 1.3 - Claude | 30 min | `CLAUDE.md`, skills loaded |
| 1.4 - Codex | 15 min | `.codex/config.json` |
| 2.0 - Investigation | 2-3 days | 4x `REPORT.md` files |
| 2.5 - Decision Gates | 1 day | Go/No-Go decision |
| **Total** | **3-4 days** | Ready for implementation |

---

## Success Criteria

✅ **Environment**: `swift build` passes with 0 warnings  
✅ **AI Tools**: All 3 tools (OpenCode, Claude, Codex) configured and tested  
✅ **Investigation**: All 4 technical investigations complete with data  
✅ **Decision**: All 4 gates passed (G1-G4)  
✅ **First Artifact**: SETUP_GUIDE.md merged to repo

---

## Next Steps

1. **Run Phase 1.1** (Environment setup) - Execute `scripts/setup-dev-env.sh`
2. **Create SETUP_GUIDE.md** (First artifact) - Document the setup process
3. **Begin Investigation 1** (MLX Audio spike) - Start API verification
4. **Schedule G1 Review** - Decide if MLX Audio is viable

**Ready to proceed?** Start with the environment setup script, then create the first artifact (SETUP_GUIDE.md).
