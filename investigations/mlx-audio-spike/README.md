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

**Important:** MLX requires Metal shaders which must be built with `xcodebuild`, not `swift build`.

```bash
cd investigations/mlx-audio-spike

# Resolve dependencies
swift package resolve

# Build with xcodebuild (required for Metal support)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -scheme MLXAudioTest -destination 'platform=macOS'

# Run the executable directly
~/Library/Developer/Xcode/DerivedData/mlx-audio-spike-*/Build/Products/Debug/MLXAudioTest
```

## API Patterns Discovered

### Model Loading and Transcription
```swift
import MLX
import MLXAudioSTT

// Load model from HuggingFace
let model = try await ParakeetModel.fromPretrained("nvidia/parakeet-rnnt-1.1b")

// Create MLXArray from [Float] samples
let mlxArray = MLXArray(samples)

// Generate transcription
let output = model.generate(audio: mlxArray)
print(output.text)
```

### Available Models

| Model Family | Repository | Size |
|--------------|------------|------|
| **Parakeet** (NVIDIA) | nvidia/parakeet-rnnt-1.1b | 1.1B |
| | nvidia/parakeet-ctc-1.1b | 1.1B |
| | nvidia/parakeet-tdt-1.1b | 1.1B |
| **Qwen3ASR** (Alibaba) | Qwen/Qwen3-ASR-2B | 2B |
| | Qwen/Qwen3-ASR-7B | 7B |
| **GraniteSpeech** (IBM) | ibm-granite/granite-speech-3.3b | 3.3B |
| **VoxtralRealtime** (Mistral) | mistralai/Voxtral-Realtime-2409 | - |
| **GLMASR** (Zhipu) | THUDM/glm-asr-9b | 9B |

### STTGenerationModel Protocol
```swift
public protocol STTGenerationModel: AnyObject {
    var defaultGenerationParameters: STTGenerateParameters { get }
    
    func generate(audio: MLXArray, generationParameters: STTGenerateParameters) -> STTOutput
    func generateStream(audio: MLXArray, generationParameters: STTGenerateParameters) -> AsyncThrowingStream<STTGeneration, Error>
}
```

### Buffer Transfer
```swift
// MLXArray copies data by design (safety)
let mlxArray = MLXArray(samples)  // [Float] -> MLXArray

// For zero-copy, use UnsafeMutablePointer (advanced)
```

## Success Criteria

| Metric | Target | Status |
|--------|--------|--------|
| Package resolution | Working | ✅ Pass |
| Build (xcodebuild) | Clean | ✅ Pass |
| Runtime (Metal) | GPU access | ✅ Pass (M4 Pro) |
| Buffer transfer | Working | ✅ Pass |
| STT API exploration | Documented | ✅ Pass |
| Model loading test | Partial | ⚠️ Config issue |
| Q4 quantization | Tested | ⏳ Pending |

## Findings

### 2026-04-30: Build & Runtime Validation
- ✅ mlx-swift package resolves correctly (v0.31.3)
- ✅ mlx-audio-swift repository found: https://github.com/Blaizzy/mlx-audio-swift
- ✅ **xcodebuild required** - SwiftPM cannot build Metal shaders
- ✅ **Metal GPU working** on M4 Pro - runtime test passes
- ✅ **MLXArray from [Float]** works (copies data as designed)
- 📝 Module name is `MLXAudioSTT` (not `MLXAudio`)
- 📝 File naming: Use `MLXAudioTest.swift` not `main.swift` with `@main`

### 2026-04-30: API Exploration (Step 2 Complete)
- ✅ **5 STT model families** available: Parakeet, Qwen3ASR, GraniteSpeech, VoxtralRealtime, GLMASR
- ✅ **API Pattern**: `Model.fromPretrained()` → `model.generate(audio: MLXArray)` → `STTOutput`
- ✅ **Protocol-based**: All models conform to `STTGenerationModel` protocol
- ✅ **Streaming support**: `generateStream()` available for real-time transcription
- ✅ **HuggingFace integration**: Models auto-download from HF Hub
- 📝 **No Q4 quantization visible** in current API - may be automatic or not yet implemented

### 2026-04-30: Model Loading Test (Step 3 Partial)
- ✅ **Model download works** - Successfully downloads ~4GB from HuggingFace
- ✅ **Cache system works** - Models cached at `~/.cache/huggingface/hub/mlx-audio/`
- ✅ **MLXArray input works** - Synthetic audio generation and MLXArray creation
- ⚠️ **Config parsing error** - `keyNotFound: preprocessor` - Model format mismatch
- 📝 **Model version issue** - The nvidia/parakeet-ctc-1.1b config doesn't match expected format
- 📝 **Next step** - Try different model or check mlx-audio-swift version compatibility

### Available Modules (from build output)
- `MLXAudioSTT` - Speech-to-text (Whisper, Parakeet, Qwen3ASR, etc.)
- `MLXAudioTTS` - Text-to-speech
- `MLXAudioVAD` - Voice activity detection
- `MLXAudioLID` - Language identification
- `MLXAudioCodecs` - Audio codecs (Mimi, DAC, Encodec)
- `MLXAudioCore` - Core audio utilities
- `MLXAudioSTS` - Speech-to-speech
- `MLXAudioUI` - UI components

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
