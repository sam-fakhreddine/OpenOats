# MLX Audio Spike Investigation

**Purpose**: Validate MLX Swift API compatibility with OpenOats TranscriptionBackend protocol.

## Goals

- [ ] Validate MLX operations with `[Float]` audio buffers
- [ ] Test buffer transfer efficiency (minimize copying)
- [ ] Measure performance on M4 Pro
- [ ] Validate memory usage patterns
- [ ] Research available MLX audio/STT libraries

## Structure

```
investigations/mlx-audio-spike/
├── Package.swift          # MLX Swift dependency
├── Sources/
│   ├── MLXAudioSpike/     # Library target
│   │   └── MLXAudioSpike.swift
│   └── MLXAudioTest/      # Test executable
│       └── main.swift
└── README.md              # This file
```

## Dependencies

- [mlx-swift](https://github.com/ml-explore/mlx-swift) - Core MLX framework

**Note**: The `mlx-audio` package mentioned in SETUP_GUIDE.md is not yet publicly available. This spike uses core MLX for validation.

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

## API Patterns Validated

### MLXArray from [Float] buffer
```swift
import MLX

// Create MLXArray from samples (copies data)
let mlxArray = MLXArray(samples)
print("Shape: \(mlxArray.shape), dtype: \(mlxArray.dtype)")
```

### Basic Audio Operations
```swift
// Simulate audio processing
let audioBuffer = MLXArray.zeros([16000])  // 1 second at 16kHz
eval(audioBuffer)
```

## Success Criteria

| Metric | Target | Status |
|--------|--------|--------|
| Package resolution | Working | ✅ Pass |
| Build | Clean | ⏳ Pending |
| Buffer transfer | < 1ms | ⏳ Pending |
| Memory | Predictable | ⏳ Pending |

## Findings

### 2026-04-30: Initial Setup
- ✅ mlx-swift package resolves correctly
- ⚠️ mlx-audio package not found at expected URL
- 📝 Need to research alternative MLX audio/STT solutions

## Alternative Approaches

Since `mlx-audio` is not available, consider:

1. **WhisperKit + MLX backend** - Check if WhisperKit supports MLX execution
2. **Custom MLX implementation** - Build STT pipeline using core MLX
3. **ANE + GPU hybrid** - Use WhisperKit CoreML (ANE) for mic, MLX (GPU) for system audio

## References

- [SETUP_GUIDE.md](../../SETUP_GUIDE.md) - AI tooling setup and patterns
- [asr_feasibility_report_max_hw_accel.json](../../asr_feasibility_report_max_hw_accel.json) - Feasibility analysis
- OpenOats `TranscriptionBackend.swift` - Protocol definition
- [MLX Swift Documentation](https://ml-explore.github.io/mlx-swift/)

## Decision Gate

This investigation feeds into **G1: MLX Audio API Validation** decision gate.
See SIMPLIFIED_WORKFLOW.md for gate criteria.

## Next Steps

1. Complete build validation
2. Research available MLX audio/STT options
3. Update SETUP_GUIDE.md with corrected dependency information
4. Decide on hybrid ANE+GPU approach vs pure MLX approach
