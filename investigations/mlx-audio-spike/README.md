# MLX Audio Spike Investigation

**Purpose**: Validate MLX Swift Audio API compatibility with OpenOats TranscriptionBackend protocol.

## Goals

- [ ] Validate MLX audio transcription with `[Float]` buffers
- [ ] Test zero-copy buffer transfer (avoid sample copying)
- [ ] Measure RTF (Real-Time Factor) on M4 Pro
- [ ] Validate memory usage stays within 1GB wired limit
- [ ] Test Q4 quantization quality vs speed tradeoff

## Structure

```
investigations/mlx-audio-spike/
├── Package.swift          # MLX + MLXAudio dependencies
├── Sources/
│   ├── MLXAudioSpike/     # Library target
│   │   └── MLXAudioSpike.swift
│   └── MLXAudioTest/      # Test executable
│       └── main.swift
└── README.md              # This file
```

## Dependencies

- [mlx-swift](https://github.com/ml-explore/mlx-swift) - Core MLX framework
- [mlx-audio-swift](https://github.com/Blaizzy/mlx-audio-swift) - Audio processing and STT for MLX

## Usage

```bash
cd investigations/mlx-audio-spike

# Resolve dependencies
swift package resolve

# Build
swift build

# Run tests
swift run MLXAudioTest
```

## API Patterns to Validate

### Model Loading with Q4 Quantization
```swift
import MLXAudio

let whisper = STT.whisper(model: .largeTurbo, quantization: .q4)
try await whisper.load { progress in
    // Report download progress 0.0...1.0
}
```

### Zero-Copy Buffer Transfer
```swift
// Wrap existing [Float] buffer directly
let mlxArray = MLXArray(
    shape: [samples.count],
    dtype: .float32,
    buffer: UnsafeMutableRawPointer(mutating: samples)
)
let result = try await whisper.transcribe(mlxArray)
```

## Success Criteria

| Metric | Target | Status |
|--------|--------|--------|
| Package resolution | Working | ✅ Pass |
| Build | Clean | ⏳ Pending |
| Zero-copy transfer | Working | ⏳ Pending |
| Q4 quality | Acceptable | ⏳ Pending |

## Findings

### 2026-04-30: Initial Setup
- ✅ mlx-swift package resolves correctly (v0.31.3)
- ✅ mlx-audio-swift repository found: https://github.com/Blaizzy/mlx-audio-swift
- 📝 Need to explore mlx-audio-swift API surface

## References

- [SETUP_GUIDE.md](../../SETUP_GUIDE.md) - AI tooling setup and patterns
- [asr_feasibility_report_max_hw_accel.json](../../asr_feasibility_report_max_hw_accel.json) - Feasibility analysis
- OpenOats `TranscriptionBackend.swift` - Protocol definition
- [MLX Swift Documentation](https://ml-explore.github.io/mlx-swift/)
- [mlx-audio-swift Repository](https://github.com/Blaizzy/mlx-audio-swift)

## Decision Gate

This investigation feeds into **G1: MLX Audio API Validation** decision gate.
See SIMPLIFIED_WORKFLOW.md for gate criteria.

## Next Steps

1. Resolve mlx-audio-swift dependencies
2. Explore STT API surface (Whisper, etc.)
3. Validate buffer transfer patterns
4. Measure performance on M4 Pro hardware
