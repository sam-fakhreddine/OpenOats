# Architecture Implementation Principles

## Branch
`feat!/3tier-clean-architecture` - Breaking change (complete architecture refactor)

## Core Principles

### SOLID
- **S**ingle Responsibility: One reason to change per class
- **O**pen/Closed: Open for extension, closed for modification
- **L**iskov Substitution: Protocols fully substitutable
- **I**nterface Segregation: Focused protocols, not fat interfaces
- **D**ependency Inversion: Depend on abstractions, not concretions

### DRY
- Don't Repeat Yourself
- Extract shared logic to reusable components
- One source of truth for domain concepts

### ELEGANT
- Clear naming (intent-revealing)
- Minimal surprise
- Self-documenting code

### SIMPLE
- Start simple, add complexity only when needed
- Prefer composition over inheritance
- Avoid over-engineering (no speculative generality)

### TDD (Test-Driven Development)
- **RED**: Write failing test first (proves behavior doesn't exist)
- **GREEN**: Implement minimum code to pass test
- **REFACTOR**: Clean up while tests pass
- **Context Isolation**: Test agent → Implementation agent (no context poisoning)

### PROPERTY-BASED TESTING
- **Generative**: Random inputs, not just hardcoded examples
- **Invariant-based**: Test properties, not specific outputs
- **Shrinking**: Find minimal failing case automatically
- **Coverage**: Edge cases discovered automatically
- **SwiftCheck**: Use SwiftCheck or similar framework

---

## TDD Workflow (Agent Handoff)

### Phase 1: Test Agent (RED)
**Agent A**: Writes comprehensive tests
- Property-based tests for invariants
- Example-based tests for specific cases
- Edge case identification
- **Output**: Test file with all tests failing

### Phase 2: Implementation Agent (GREEN)
**Agent B**: Implements to pass tests
- **Constraint**: Cannot see test implementation details
- Only sees test signatures and expected behavior
- Implements minimum code to make tests pass
- **Output**: Implementation + passing tests

### Phase 3: Refactor Agent (Optional)
**Agent C**: Code quality improvements
- Refactors while maintaining test passes
- Performance optimizations
- Documentation

---

## MLX Work Reuse Strategy

We have existing MLX work in these branches:
- `feat/mlx-audio-and-model-storage` - MLX Audio backend
- `feat/mlx-audio-investigation` - Investigation findings
- `feat/meeting-detection` - Meeting detection features

### What to Reuse:
1. **MLXWhisperBackend.swift** - Can adapt to new TranscriptionService protocol
2. **Model download logic** - Chunked download with resume (5MB chunks, 6 concurrent)
3. **MLX configuration** - Model paths, quantization settings
4. **Benchmark results** - WER metrics for validation

### What to Reimplement:
1. **Direct MLX dependencies in UI** → Move to Infrastructure layer
2. **Tight coupling with SessionRepository** → Use protocol-based DI
3. **Non-Sendable types** → Make Sendable-safe for Swift 6.2

### Migration Approach:
```
Old MLX Code (feat/mlx-audio-and-model-storage)
        ↓
Extract core logic → Adapt to TranscriptionService protocol
        ↓
New Infrastructure Layer: MLXTranscriptionService
```

---

## Code Quality Gates

### Before Commit:
- [ ] No force unwraps (`!`)
- [ ] No force try (`try!`)
- [ ] All functions < 20 lines (SRP)
- [ ] All classes < 15 methods (SRP)
- [ ] Protocol-based dependencies only
- [ ] Sendable conformance for domain types
- [ ] @MainActor on ViewModels

### CI/CD Checks:
- [ ] OpenGrep: Zero layer violations
- [ ] OpenGrep: Zero force unwraps
- [ ] Swift compiler: Zero warnings with `-strict-concurrency=complete`
- [ ] Tests: >80% coverage for Domain layer

---

## Layer Boundaries (Strict)

### Domain (Innermost)
```swift
// ✅ GOOD: Pure, no external deps
struct Transcription: Sendable, Equatable, Codable {
    let text: String
    let confidence: Double
}

// ❌ BAD: External dependency
import MLX  // NEVER in Domain
```

### Business Logic
```swift
// ✅ GOOD: Protocol abstraction
struct StartSessionUseCase {
    let transcriptionService: TranscriptionService
    let sessionRepository: SessionRepository
}

// ❌ BAD: Concrete dependency
struct StartSessionUseCase {
    let transcriptionService: MLXTranscriptionService  // Don't do this
}
```

### Infrastructure
```swift
// ✅ GOOD: Implements domain protocol
struct MLXTranscriptionService: TranscriptionService {
    func transcribe(audio: AudioData) async throws -> Transcription {
        // MLX implementation here
    }
}
```

### Presentation
```swift
// ✅ GOOD: Thin ViewModel
@MainActor
class SessionViewModel: ObservableObject {
    private let startSessionUseCase: StartSessionUseCase
    
    func startRecording() async throws {
        try await startSessionUseCase.execute()
    }
}
```

---

## Naming Conventions

### Protocols (Suffix with Protocol or use nouns)
```swift
protocol TranscriptionService { }
protocol SessionRepository { }
protocol AudioCaptureService { }
```

### Implementations (Prefix with technology)
```swift
struct MLXTranscriptionService: TranscriptionService { }
struct WhisperKitTranscriptionService: TranscriptionService { }
struct CoreDataSessionRepository: SessionRepository { }
```

### Use Cases (Verb + Noun)
```swift
struct StartSessionUseCase { }
struct StopSessionUseCase { }
struct GenerateNotesUseCase { }
struct ExportTranscriptUseCase { }
```

### ViewModels (ViewName + ViewModel)
```swift
@MainActor
class SessionViewModel: ObservableObject { }
@MainActor
class TranscriptViewModel: ObservableObject { }
```

---

## Migration Order (Strangler Fig)

1. **Infrastructure First** (easiest to extract)
   - Create TranscriptionService protocol
   - Adapt existing MLX code to protocol
   - Keep old code working during transition

2. **Domain Second** (pure, no deps)
   - Extract entities (Transcription, Session, etc.)
   - Define value objects
   - Create error taxonomy

3. **Business Logic Third** (depends on Domain + Infrastructure)
   - Create use cases
   - Move logic from ViewModels
   - Protocol-based DI

4. **Presentation Last** (depends on all)
   - Refactor ViewModels to use use cases
   - Thin ViewModels (just state management)
   - @MainActor everywhere

---

## Testing Strategy

### Domain: Unit Tests (100% coverage)
```swift
func testTranscriptionValidation() {
    let transcription = Transcription(text: "Hello", confidence: 0.95)
    XCTAssertTrue(transcription.isValid)
}
```

### Business: Integration Tests with Mocks
```swift
func testStartSessionUseCase() async throws {
    let mockService = MockTranscriptionService()
    let useCase = StartSessionUseCase(transcriptionService: mockService)
    
    let session = try await useCase.execute()
    XCTAssertNotNil(session.id)
}
```

### Infrastructure: Contract Tests
```swift
func testMLXTranscriptionServiceConformsToProtocol() {
    let service: any TranscriptionService = MLXTranscriptionService()
    // Verify protocol conformance
}
```

### Presentation: UI Tests (minimal)
- Test user flows
- Mock all dependencies

---

## Remember

> "Perfection is achieved, not when there is nothing more to add, but when there is nothing left to take away."
> — Antoine de Saint-Exupéry

**Start simple. Add complexity only when proven necessary.**
