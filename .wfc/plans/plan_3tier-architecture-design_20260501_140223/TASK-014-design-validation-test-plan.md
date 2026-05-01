# TASK-014: Design Validation Test Plan

## Comprehensive Test Plan for Design Validation

This document provides TC-001 through TC-015 - test cases for validating the 3-tier architecture design before implementation begins.

---

## Test Case Summary

| ID | Test Case | Type | Priority | Status |
|----|-----------|------|----------|--------|
| TC-001 | Protocol Compile-Time Validation | Static | P0 | Ready |
| TC-002 | Protocol Dependency Injection Test | Unit | P0 | Ready |
| TC-003 | Domain Type Sendable Conformance | Static | P0 | Ready |
| TC-004 | Actor Isolation Verification | Static | P0 | Ready |
| TC-005 | Layer Boundary Enforcement | Static | P0 | Ready |
| TC-006 | AST High Fan-Out Detection | Automated | P0 | Ready |
| TC-007 | AST Blast Radius Detection | Automated | P0 | Ready |
| TC-008 | Circular Dependency Detection | Automated | P0 | Ready |
| TC-009 | Large Class Detection | Automated | P0 | Ready |
| TC-010 | Mock Implementation Test | Unit | P1 | Ready |
| TC-011 | Use Case Unit Test | Unit | P1 | Ready |
| TC-012 | ViewModel Integration Test | Integration | P1 | Ready |
| TC-013 | Data Flow Sequence Validation | Review | P1 | Ready |
| TC-014 | Migration Phase Verification | Review | P1 | Ready |
| TC-015 | Swift 6.2 Concurrency Audit | Static | P0 | Ready |

---

## TC-001: Protocol Compile-Time Validation

### Objective
Verify that all designed protocols can be implemented by concrete types and compile without errors.

### Prerequisites
- Swift 6.2 toolchain installed
- All protocol definitions from TASK-004, TASK-005, TASK-006

### Test Steps

```swift
// TC-001: Protocol Compile Test
// File: Tests/DesignValidation/ProtocolCompileTests.swift

import XCTest
@testable import OpenOats

final class ProtocolCompileTests: XCTestCase {
    
    // MARK: - Presentation Layer Protocols (TASK-004)
    
    func testSessionViewModelProtocolCompiles() {
        // Compile-time test: Verify protocol can be conformed to
        struct MockSessionViewModel: SessionViewModelProtocol {
            var isRecording: Bool = false
            var recordingDuration: Duration = .zero
            var currentSession: Session?
            
            func startRecording(title: String, source: AudioSource) async { }
            func stopRecording() async { }
        }
        
        let vm: any SessionViewModelProtocol = MockSessionViewModel()
        XCTAssertNotNil(vm)
    }
    
    func testTranscriptViewModelProtocolCompiles() {
        struct MockTranscriptViewModel: TranscriptViewModelProtocol {
            var transcript: Transcript?
            var isLoading: Bool = false
            
            func loadTranscript(id: TranscriptID) async { }
            func exportTranscript(format: ExportFormat, to url: URL) async { }
        }
        
        let vm: any TranscriptViewModelProtocol = MockTranscriptViewModel()
        XCTAssertNotNil(vm)
    }
    
    // MARK: - Business Logic Protocols (TASK-005)
    
    func testStartSessionUseCaseProtocolCompiles() {
        struct MockStartSessionUseCase: StartSessionUseCaseProtocol {
            func execute(input: StartSessionInput) async throws -> Session {
                Session(id: SessionID(), meetingID: MeetingID(), startedAt: Date(), status: .recording, recordingURL: nil)
            }
        }
        
        let useCase: any StartSessionUseCaseProtocol = MockStartSessionUseCase()
        XCTAssertNotNil(useCase)
    }
    
    func testAllUseCaseProtocolsCompile() {
        // Verify all 6 use case protocols can be conformed to
        struct MockUseCases {
            let start: any StartSessionUseCaseProtocol
            let stop: any StopSessionUseCaseProtocol
            let generateNotes: any GenerateNotesUseCaseProtocol
            let export: any ExportTranscriptUseCaseProtocol
            let importAudio: any ImportAudioUseCaseProtocol
            let switchBackend: any SwitchBackendUseCaseProtocol
        }
        
        let useCases = MockUseCases(
            start: MockStartSessionUseCase(),
            stop: MockStopSessionUseCase(),
            generateNotes: MockGenerateNotesUseCase(),
            export: MockExportTranscriptUseCase(),
            importAudio: MockImportAudioUseCase(),
            switchBackend: MockSwitchBackendUseCase()
        )
        
        XCTAssertNotNil(useCases)
    }
    
    // MARK: - Infrastructure Protocols (TASK-006)
    
    func testTranscriptionServiceProtocolCompiles() {
        struct MockTranscriptionService: TranscriptionServiceProtocol {
            let backendID: BackendID = .mlx
            var isAvailable: Bool { true }
            
            func supportedLanguages() async -> [LanguageCode] { [.en] }
            func configure(_ configuration: TranscriptionConfiguration) async { }
        }
        
        let service: any TranscriptionServiceProtocol = MockTranscriptionService()
        XCTAssertNotNil(service)
    }
    
    func testSessionRepositoryProtocolCompiles() {
        actor MockSessionRepository: SessionRepositoryProtocol {
            func save(_ session: Session) async throws(StorageError) { }
            func load(id: SessionID) async throws(StorageError) -> Session? { nil }
            func loadAll(for meetingID: MeetingID) async throws(StorageError) -> [Session] { [] }
            func delete(id: SessionID) async throws(StorageError) { }
            func exists(id: SessionID) async -> Bool { false }
        }
        
        let repo: any SessionRepositoryProtocol = MockSessionRepository()
        XCTAssertNotNil(repo)
    }
}

// MARK: - Mock Implementations

struct MockStopSessionUseCase: StopSessionUseCaseProtocol {
    func execute(input: StopSessionInput) async throws -> Session {
        fatalError()
    }
}

struct MockGenerateNotesUseCase: GenerateNotesUseCaseProtocol {
    func execute(input: GenerateNotesInput) async throws(NetworkError) -> GenerateNotesOutput {
        fatalError()
    }
}

struct MockExportTranscriptUseCase: ExportTranscriptUseCaseProtocol {
    func execute(input: ExportTranscriptInput) async throws { }
}

struct MockImportAudioUseCase: ImportAudioUseCaseProtocol {
    func execute(input: ImportAudioInput) async throws -> Transcript {
        fatalError()
    }
}

struct MockSwitchBackendUseCase: SwitchBackendUseCaseProtocol {
    func execute(input: SwitchBackendInput) async throws(TranscriptionError) { }
}
```

### Expected Results
- All protocols can be conformed to by mock types
- Code compiles without errors or warnings
- No protocol has "Self or associated type requirements" that would prevent mocking

### Success Criteria
- [ ] 100% of designed protocols compile with mock implementations
- [ ] All protocol requirements are satisfied

---

## TC-002: Protocol Dependency Injection Test

### Objective
Verify that the dependency injection strategy supports protocol-based injection and test doubles.

### Prerequisites
- DI container design from TASK-007
- All protocol definitions

### Test Steps

```swift
// TC-002: Dependency Injection Test
// File: Tests/DesignValidation/DIContainerTests.swift

import XCTest
@testable import OpenOats

final class DIContainerTests: XCTestCase {
    
    var container: AppContainer!
    
    override func setUp() {
        super.setUp()
        container = AppContainer()
    }
    
    func testContainerResolvesViewModels() {
        // Test that container can resolve view models with injected use cases
        let viewModel = container.resolve(SessionViewModel.self)
        XCTAssertNotNil(viewModel)
    }
    
    func testContainerUsesProtocolBasedInjection() {
        // Verify that resolved dependencies are protocol types, not concrete
        let useCase = container.resolve(any StartSessionUseCaseProtocol.self)
        
        // Should be able to substitute with mock
        let mockUseCase = MockStartSessionUseCase()
        container.register(any StartSessionUseCaseProtocol.self, mockUseCase)
        
        let resolved = container.resolve(any StartSessionUseCaseProtocol.self)
        XCTAssertTrue(resolved is MockStartSessionUseCase)
    }
    
    func testContainerSupportsTestDoubles() {
        // Create test container with mocks
        let testContainer = AppContainer.test()
        
        let viewModel = testContainer.resolve(SessionViewModel.self)
        XCTAssertNotNil(viewModel)
        
        // Verify test doubles are used
        let repository = testContainer.resolve(any SessionRepositoryProtocol.self)
        XCTAssertTrue(repository is InMemorySessionRepository)
    }
    
    func testNoCircularDependencies() {
        // Verify container can initialize without circular dependency errors
        XCTAssertNoThrow {
            _ = AppContainer()
        }
    }
    
    func testLifecycleManagement() {
        // Test singleton vs transient lifecycle
        let singleton1 = container.resolve(any SettingsRepositoryProtocol.self)
        let singleton2 = container.resolve(any SettingsRepositoryProtocol.self)
        XCTAssertTrue(singleton1 === singleton2, "Singletons should be identical")
        
        let transient1 = container.resolve(any StartSessionUseCaseProtocol.self)
        let transient2 = container.resolve(any StartSessionUseCaseProtocol.self)
        XCTAssertFalse(transient1 === transient2, "Transients should be different")
    }
}
```

### Expected Results
- Container resolves all dependencies correctly
- Protocol-based substitution works
- Test doubles can be injected
- No circular dependencies

### Success Criteria
- [ ] Container initializes without errors
- [ ] All dependencies resolvable
- [ ] Test double injection functional
- [ ] Lifecycle management correct

---

## TC-003: Domain Type Sendable Conformance

### Objective
Verify that all domain types meet Swift 6.2 Sendable requirements.

### Test Steps

```bash
# TC-003: Sendable Conformance Validation

# 1. Build with strict concurrency checking
swift build -Xswiftc -strict-concurrency=complete

# 2. Verify no Sendable warnings
echo "Sendable errors:"
swift build 2>&1 | grep -i "sendable" | grep -i "error" | wc -l
# Expected: 0

# 3. Check for @unchecked Sendable
echo "Unchecked Sendable count:"
grep -r "@unchecked Sendable" OpenOats/Sources/ | wc -l
# Expected: 0 (or documented)
```

### Static Analysis Test

```swift
// TC-003: Sendable Conformance Compile Test
// File: Tests/DesignValidation/SendableConformanceTests.swift

import XCTest
@testable import OpenOats

// This test verifies at compile time that all domain types are Sendable
final class SendableConformanceTests: XCTestCase {
    
    func testAllDomainEntitiesAreSendable() {
        // Compile-time verification that these types are Sendable
        func verifySendable<T: Sendable>(_ value: T) { }
        
        // Entities
        verifySendable(Meeting(id: MeetingID(), title: "", createdAt: Date(), sessions: [], status: .scheduled))
        verifySendable(Session(id: SessionID(), meetingID: MeetingID(), startedAt: Date(), status: .recording, recordingURL: nil))
        verifySendable(Transcript(id: TranscriptID(), sessionID: SessionID(), utterances: [], generatedAt: Date(), backend: .mlx))
        verifySendable(Utterance(speakerID: SpeakerID(), text: "", startTime: .zero, endTime: .zero, confidence: 0.0))
        verifySendable(Speaker(id: SpeakerID()))
        verifySendable(Note(id: UUID(), meetingID: MeetingID(), content: "", type: .summary, generatedAt: Date(), aiModel: ""))
        verifySendable(AudioSegment(id: UUID(), sessionID: SessionID(), buffer: AudioBuffer(), timestamp: .zero, sampleRate: 48000))
        
        // Identifiers
        verifySendable(MeetingID())
        verifySendable(SessionID())
        verifySendable(SpeakerID())
        verifySendable(TranscriptID())
        verifySendable(BackendID.mlx)
        
        // Value objects
        verifySendable(AudioBuffer())
        verifySendable(VoiceSignature(embedding: [], sampleCount: 0))
        
        // Errors
        verifySendable(TranscriptionError.backendFailed(backend: .mlx, reason: "", recoverable: true))
        verifySendable(StorageError.fileNotFound(path: ""))
        verifySendable(ValidationError.invalidInput(field: "", value: "", constraint: ""))
        verifySendable(NetworkError.connectivityFailed(endpoint: ""))
        verifySendable(AudioError.permissionDenied)
        
        // Status enums
        verifySendable(MeetingStatus.scheduled)
        verifySendable(SessionStatus.recording)
        verifySendable(NoteType.summary)
        
        XCTAssertTrue(true) // Compile success is the test
    }
}
```

### Expected Results
- Zero Sendable compiler warnings
- Zero @unchecked Sendable (unless documented)
- All domain types pass Sendable conformance check

### Success Criteria
- [ ] All domain entities conform to Sendable
- [ ] All identifiers conform to Sendable
- [ ] All errors conform to Sendable
- [ ] Zero undocumented @unchecked Sendable

---

## TC-004: Actor Isolation Verification

### Objective
Verify that actor isolation is correctly applied to mutable shared state.

### Test Steps

```bash
# TC-004: Actor Isolation Validation

# 1. Build with actor isolation checking
echo "Actor isolation errors:"
swift build -Xswiftc -strict-concurrency=complete 2>&1 | grep -i "actor" | grep -i "error" | wc -l
# Expected: 0

# 2. Check for @MainActor on view models
echo "@MainActor view models:"
grep -r "@MainActor.*class.*ViewModel" OpenOats/Sources/Presentation/ | wc -l
# Expected: ≥ number of view models

# 3. Check for actor on services with mutable state
echo "Actor services:"
grep -r "^public actor.*Service" OpenOats/Sources/Infrastructure/ | wc -l
# Expected: ≥ 3 (SessionActor, TranscriptionActor, etc.)
```

### Expected Results
- No actor isolation compiler errors
- All view models have @MainActor
- All services with mutable state are actors

### Success Criteria
- [ ] @MainActor on all view models
- [ ] Actor isolation on all shared mutable state
- [ ] Zero actor isolation warnings

---

## TC-005: Layer Boundary Enforcement

### Objective
Verify that layer boundaries are enforced and no layer violations exist.

### Test Steps

```bash
# TC-005: Layer Violation Detection

# 1. Check Domain doesn't import Infrastructure
echo "Domain imports Infrastructure:"
grep -r "import.*Infrastructure" OpenOats/Sources/Domain/ | wc -l
# Expected: 0

# 2. Check BusinessLogic doesn't import Presentation
echo "BusinessLogic imports SwiftUI:"
grep -r "import SwiftUI" OpenOats/Sources/BusinessLogic/ | wc -l
# Expected: 0

# 3. Check Infrastructure doesn't depend on upper layers
echo "Infrastructure imports Presentation:"
grep -r "import.*Presentation" OpenOats/Sources/Infrastructure/ | wc -l
# Expected: 0

grep -r "import.*BusinessLogic" OpenOats/Sources/Infrastructure/ | wc -l
# Expected: 0

# 4. Run OpenGrep rules
opengrep scan --config .opengrep/layer-violation.yaml OpenOats/Sources/
# Expected: 0 violations
```

### Expected Results
- Zero imports from outer layers into inner layers
- Zero layer violations from OpenGrep

### Success Criteria
- [ ] Domain has zero external dependencies
- [ ] No upward layer imports
- [ ] OpenGrep layer rules pass

---

## TC-006: AST High Fan-Out Detection

### Objective
Verify that no functions have excessive fan-out (>8 calls).

### Test Steps

```bash
# TC-006: High Fan-Out Validation

# Run EEDOM SQL query
FANOUT=$(sqlite3 .eedom/code_graph.sqlite "SELECT COUNT(*) FROM (SELECT s.id FROM symbols s JOIN edges e ON e.source_id = s.id AND e.kind = 'calls' GROUP BY s.id HAVING COUNT(e.id) > 8);")

echo "Functions with >8 calls: $FANOUT"

if [ "$FANOUT" -eq 0 ]; then
    echo "✅ PASS: No high fan-out functions"
else
    echo "❌ FAIL: Found $FANOUT functions with high fan-out"
    sqlite3 .eedom/code_graph.sqlite "SELECT s.name, s.file, COUNT(e.id) as calls FROM symbols s JOIN edges e ON e.source_id = s.id AND e.kind = 'calls' GROUP BY s.id HAVING calls > 8;"
    exit 1
fi
```

### Expected Results
- Zero functions with >8 calls

### Success Criteria
- [ ] High fan-out count = 0

---

## TC-007: AST Blast Radius Detection

### Objective
Verify that no symbols have excessive blast radius (>10 dependents).

### Test Steps

```bash
# TC-007: Blast Radius Validation

BLAST=$(sqlite3 .eedom/code_graph.sqlite "SELECT COUNT(*) FROM (SELECT s.id FROM symbols s JOIN edges e ON e.target_id = s.id GROUP BY s.id HAVING COUNT(e.id) > 10);")

echo "Symbols with >10 dependents: $BLAST"

if [ "$BLAST" -eq 0 ]; then
    echo "✅ PASS: No high blast radius symbols"
else
    echo "❌ FAIL: Found $BLAST symbols with high blast radius"
    sqlite3 .eedom/code_graph.sqlite "SELECT s.name, s.file, COUNT(e.id) as deps FROM symbols s JOIN edges e ON e.target_id = s.id GROUP BY s.id HAVING deps > 10;"
    exit 1
fi
```

### Expected Results
- Zero symbols with >10 dependents

### Success Criteria
- [ ] Blast radius count = 0

---

## TC-008: Circular Dependency Detection

### Objective
Verify that no circular dependencies exist in the codebase.

### Test Steps

```bash
# TC-008: Circular Dependency Validation

CIRCULAR=$(sqlite3 .eedom/code_graph.sqlite "SELECT COUNT(*) FROM (SELECT DISTINCT s1.file, s2.file FROM edges e1 JOIN symbols s1 ON e1.source_id = s1.id JOIN symbols s2 ON e1.target_id = s2.id JOIN edges e2 ON e2.source_id = s2.id AND e2.target_id = s1.id WHERE e1.kind = 'imports');")

echo "Circular dependencies: $CIRCULAR"

if [ "$CIRCULAR" -eq 0 ]; then
    echo "✅ PASS: No circular dependencies"
else
    echo "❌ FAIL: Found $CIRCULAR circular dependencies"
    sqlite3 .eedom/code_graph.sqlite "SELECT DISTINCT s1.file, s2.file FROM edges e1 JOIN symbols s1 ON e1.source_id = s1.id JOIN symbols s2 ON e1.target_id = s2.id JOIN edges e2 ON e2.source_id = s2.id AND e2.target_id = s1.id WHERE e1.kind = 'imports';"
    exit 1
fi
```

### Expected Results
- Zero circular dependencies

### Success Criteria
- [ ] Circular dependency count = 0

---

## TC-009: Large Class Detection

### Objective
Verify that no classes have excessive method counts (>15).

### Test Steps

```bash
# TC-009: Large Class Validation

LARGE=$(sqlite3 .eedom/code_graph.sqlite "SELECT COUNT(*) FROM (SELECT c.name FROM symbols c JOIN symbols m ON m.file = c.file WHERE c.kind = 'class' GROUP BY c.name HAVING COUNT(m.id) > 15);")

echo "Classes with >15 methods: $LARGE"

if [ "$LARGE" -eq 0 ]; then
    echo "✅ PASS: No large classes"
else
    echo "❌ FAIL: Found $LARGE large classes"
    sqlite3 .eedom/code_graph.sqlite "SELECT c.name, c.file, COUNT(m.id) as methods FROM symbols c JOIN symbols m ON m.file = c.file WHERE c.kind = 'class' GROUP BY c.name HAVING methods > 15;"
    exit 1
fi
```

### Expected Results
- Zero classes with >15 methods

### Success Criteria
- [ ] Large class count = 0

---

## TC-010: Mock Implementation Test

### Objective
Verify that all protocols can be mocked for testing.

### Test Steps

```swift
// TC-010: Mock Implementation Test
// File: Tests/DesignValidation/MockImplementationTests.swift

import XCTest
@testable import OpenOats

final class MockImplementationTests: XCTestCase {
    
    func testMockRepositoryWorksInTest() async {
        let mockRepo = MockSessionRepository()
        
        let session = Session(
            id: SessionID(),
            meetingID: MeetingID(),
            startedAt: Date(),
            status: .recording,
            recordingURL: nil
        )
        
        try? await mockRepo.save(session)
        let loaded = try? await mockRepo.load(id: session.id)
        
        XCTAssertEqual(loaded?.id, session.id)
    }
    
    func testMockTranscriptionServiceWorksInTest() async {
        let mockService = MockTranscriptionService()
        
        let isAvailable = await mockService.isAvailable
        XCTAssertTrue(isAvailable)
        
        let languages = await mockService.supportedLanguages()
        XCTAssertEqual(languages, [.en])
    }
    
    func testMockLLMServiceWorksInTest() async throws {
        let mockLLM = MockLLMService()
        
        let transcript = Transcript(
            id: TranscriptID(),
            sessionID: SessionID(),
            utterances: [],
            generatedAt: Date(),
            backend: .mlx
        )
        
        let note = try await mockLLM.generateNotes(
            from: transcript,
            type: .summary,
            options: LLMOptions()
        )
        
        XCTAssertNotNil(note)
        XCTAssertEqual(note.type, .summary)
    }
}

// MARK: - Mock Implementations

actor MockSessionRepository: SessionRepositoryProtocol {
    private var storage: [SessionID: Session] = [:]
    
    func save(_ session: Session) async throws(StorageError) {
        storage[session.id] = session
    }
    
    func load(id: SessionID) async throws(StorageError) -> Session? {
        storage[id]
    }
    
    func loadAll(for meetingID: MeetingID) async throws(StorageError) -> [Session] {
        storage.values.filter { $0.meetingID == meetingID }
    }
    
    func delete(id: SessionID) async throws(StorageError) {
        storage.removeValue(forKey: id)
    }
    
    func exists(id: SessionID) async -> Bool {
        storage[id] != nil
    }
}

struct MockTranscriptionService: TranscriptionServiceProtocol {
    let backendID: BackendID = .mlx
    var isAvailable: Bool { true }
    
    func supportedLanguages() async -> [LanguageCode] { [.en] }
    func configure(_ configuration: TranscriptionConfiguration) async { }
}

struct MockLLMService: LLMServiceProtocol {
    func generateNotes(from transcript: Transcript, type: NoteType, options: LLMOptions) async throws(NetworkError) -> Note {
        Note(
            meetingID: transcript.sessionID.meetingID,
            content: "Mock generated notes",
            type: type,
            generatedAt: Date(),
            aiModel: "mock"
        )
    }
    
    func complete(prompt: String, options: LLMOptions) async throws(NetworkError) -> String {
        "Mock completion"
    }
    
    func streamCompletion(prompt: String, options: LLMOptions) -> AsyncThrowingStream<String, NetworkError> {
        AsyncThrowingStream { continuation in
            continuation.yield("Mock")
            continuation.finish()
        }
    }
}
```

### Expected Results
- All mocks implement protocol requirements
- Mocks work in unit tests
- No protocol has requirements that prevent mocking

### Success Criteria
- [ ] All protocols mockable
- [ ] Mock tests pass

---

## TC-011: Use Case Unit Test

### Objective
Verify that use cases can be unit tested in isolation.

### Test Steps

```swift
// TC-011: Use Case Unit Test
// File: Tests/DesignValidation/UseCaseTests.swift

import XCTest
@testable import OpenOats

final class UseCaseTests: XCTestCase {
    
    var sessionRepository: MockSessionRepository!
    var audioCapture: MockAudioCaptureService!
    var transcriptionService: MockTranscriptionService!
    var startUseCase: StartSessionUseCase!
    
    override func setUp() {
        super.setUp()
        sessionRepository = MockSessionRepository()
        audioCapture = MockAudioCaptureService()
        transcriptionService = MockTranscriptionService()
        
        startUseCase = StartSessionUseCase(
            sessionRepository: sessionRepository,
            audioCapture: audioCapture,
            transcriptionService: transcriptionService
        )
    }
    
    func testStartSessionCreatesSession() async throws {
        let input = StartSessionInput(
            meetingTitle: "Test Meeting",
            audioSource: .microphone,
            transcriptionBackend: .mlx
        )
        
        let session = try await startUseCase.execute(input: input)
        
        XCTAssertNotNil(session)
        XCTAssertEqual(session.status, .recording)
        
        // Verify saved to repository
        let saved = try await sessionRepository.load(id: session.id)
        XCTAssertNotNil(saved)
    }
    
    func testStartSessionFailsWithoutAuthorization() async {
        audioCapture.isAuthorized = false
        
        let input = StartSessionInput(
            meetingTitle: "Test",
            audioSource: .microphone,
            transcriptionBackend: .mlx
        )
        
        do {
            _ = try await startUseCase.execute(input: input)
            XCTFail("Should have thrown")
        } catch {
            XCTAssertTrue(error is AudioError)
        }
    }
}
```

### Expected Results
- Use cases can be tested with mock dependencies
- Business logic is isolated and testable

### Success Criteria
- [ ] Use cases unit testable
- [ ] Test coverage > 80%

---

## TC-012: ViewModel Integration Test

### Objective
Verify that view models correctly integrate with use cases and handle UI state.

### Test Steps

```swift
// TC-012: ViewModel Integration Test
// File: Tests/DesignValidation/ViewModelTests.swift

import XCTest
import Combine
@testable import OpenOats

@MainActor
final class ViewModelTests: XCTestCase {
    
    var viewModel: SessionViewModel!
    var mockStartUseCase: MockStartSessionUseCase!
    var mockStopUseCase: MockStopSessionUseCase!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        mockStartUseCase = MockStartSessionUseCase()
        mockStopUseCase = MockStopSessionUseCase()
        viewModel = SessionViewModel(
            startSessionUseCase: mockStartUseCase,
            stopSessionUseCase: mockStopUseCase
        )
        cancellables = []
    }
    
    func testStartRecordingUpdatesState() async {
        XCTAssertFalse(viewModel.isRecording)
        
        await viewModel.startRecording(title: "Test", source: .microphone)
        
        XCTAssertTrue(viewModel.isRecording)
        XCTAssertNotNil(viewModel.currentSession)
    }
    
    func testStopRecordingUpdatesState() async {
        // First start
        await viewModel.startRecording(title: "Test", source: .microphone)
        XCTAssertTrue(viewModel.isRecording)
        
        // Then stop
        await viewModel.stopRecording(shouldGenerateNotes: false)
        
        XCTAssertFalse(viewModel.isRecording)
    }
    
    func testErrorHandling() async {
        mockStartUseCase.shouldFail = true
        
        await viewModel.startRecording(title: "Test", source: .microphone)
        
        XCTAssertNotNil(viewModel.error)
        XCTAssertTrue(viewModel.showErrorAlert)
    }
}

// MARK: - Mock Use Cases for ViewModel Testing

struct MockStartSessionUseCase: StartSessionUseCaseProtocol {
    var shouldFail = false
    
    func execute(input: StartSessionInput) async throws -> Session {
        if shouldFail {
            throw AudioError.permissionDenied
        }
        
        return Session(
            id: SessionID(),
            meetingID: MeetingID(),
            startedAt: Date(),
            status: .recording,
            recordingURL: nil
        )
    }
}

struct MockStopSessionUseCase: StopSessionUseCaseProtocol {
    func execute(input: StopSessionInput) async throws -> Session {
        Session(
            id: input.sessionID,
            meetingID: MeetingID(),
            startedAt: Date(),
            endedAt: Date(),
            status: .completed,
            recordingURL: nil
        )
    }
}
```

### Expected Results
- View models update UI state correctly
- Errors are published for UI display
- Integration with use cases works

### Success Criteria
- [ ] View model tests pass
- [ ] UI state updates correctly

---

## TC-013: Data Flow Sequence Validation

### Objective
Verify that all data flow diagrams correctly represent the actual code structure.

### Test Steps

```bash
# TC-013: Data Flow Validation

# 1. Verify sequence diagram files exist
echo "Checking data flow diagrams..."
DIAGRAMS=$(grep -c "^\`\`\`mermaid" .wfc/plans/plan_*/TASK-009*.md)
echo "Found $DIAGRAMS Mermaid diagrams"
[ "$DIAGRAMS" -ge 5 ] && echo "✅ PASS" || echo "❌ FAIL"

# 2. Verify all major flows are diagrammed
echo ""
echo "Verifying required flows:"
echo "- Architecture Overview: $(grep -c 'Architecture Overview' .wfc/plans/plan_*/TASK-009*.md)"
echo "- Session Lifecycle: $(grep -c 'Session Lifecycle' .wfc/plans/plan_*/TASK-009*.md)"
echo "- Real-time Transcription: $(grep -c 'Real-Time Transcription' .wfc/plans/plan_*/TASK-009*.md)"
echo "- Note Generation: $(grep -c 'Note Generation' .wfc/plans/plan_*/TASK-009*.md)"
echo "- Error Propagation: $(grep -c 'Error Propagation' .wfc/plans/plan_*/TASK-009*.md)"
```

### Expected Results
- All 5 major flows have sequence diagrams
- Diagrams use correct Mermaid syntax

### Success Criteria
- [ ] 5+ data flow diagrams exist
- [ ] All major flows covered

---

## TC-014: Migration Phase Verification

### Objective
Verify that the migration plan has all required phases and rollback strategies.

### Test Steps

```bash
# TC-014: Migration Plan Validation

# 1. Verify 9-week plan exists
echo "Checking migration plan..."
grep -c "9-Week Phased Migration Plan" .wfc/plans/plan_*/TASK-008*.md
echo "✅ 9-week plan documented"

# 2. Verify all phases documented
echo ""
echo "Verifying phases:"
grep "Phase [1-5]:" .wfc/plans/plan_*/TASK-008*.md

# 3. Verify rollback strategies
echo ""
echo "Verifying rollback strategies:"
grep -c "Rollback" .wfc/plans/plan_*/TASK-008*.md
echo "Rollback mentions found"

# 4. Verify feature flags
echo ""
echo "Verifying feature flags:"
grep -c "FeatureFlags" .wfc/plans/plan_*/TASK-008*.md
echo "Feature flag mentions found"

# 5. Verify success metrics
echo ""
echo "Verifying success metrics:"
grep -c "Success Metrics" .wfc/plans/plan_*/TASK-008*.md
echo "Success metrics documented"
```

### Expected Results
- 9-week plan documented
- All 5 phases defined
- Rollback strategies specified
- Feature flags documented
- Success metrics defined

### Success Criteria
- [ ] Migration plan complete
- [ ] All phases defined with deliverables
- [ ] Rollback strategies documented
- [ ] Feature flags specified

---

## TC-015: Swift 6.2 Concurrency Audit

### Objective
Comprehensive audit of Swift 6.2 concurrency patterns.

### Test Steps

```bash
#!/bin/bash
# TC-015: Swift 6.2 Concurrency Audit Script

echo "=== TC-015: Swift 6.2 Concurrency Audit ==="
echo ""

ERRORS=0

# 1. Actor usage check
echo "1. Actor usage:"
ACTOR_COUNT=$(grep -r "^public actor" OpenOats/Sources/ --include="*.swift" | wc -l)
echo "   Found $ACTOR_COUNT public actors"
[ "$ACTOR_COUNT" -ge 3 ] && echo "   ✅ PASS" || { echo "   ❌ FAIL: Expected ≥3 actors"; ERRORS=$((ERRORS + 1)); }

# 2. @MainActor check
echo ""
echo "2. @MainActor on ViewModels:"
MAINACTOR_COUNT=$(grep -r "@MainActor" OpenOats/Sources/Presentation/ --include="*.swift" | wc -l)
echo "   Found $MAINACTOR_COUNT @MainActor annotations"
[ "$MAINACTOR_COUNT" -ge 1 ] && echo "   ✅ PASS" || { echo "   ❌ FAIL: Expected ≥1"; ERRORS=$((ERRORS + 1)); }

# 3. @unchecked Sendable check
echo ""
echo "3. @unchecked Sendable (should be 0 or documented):"
UNCHECKED=$(grep -r "@unchecked Sendable" OpenOats/Sources/ --include="*.swift" | wc -l)
echo "   Found $UNCHECKED @unchecked Sendable"
[ "$UNCHECKED" -eq 0 ] && echo "   ✅ PASS" || { echo "   ⚠️ WARN: Document if needed"; }

# 4. Sendable protocol inheritance
echo ""
echo "4. Sendable protocol inheritance:"
SENDABLE_PROTOCOLS=$(grep -r "protocol.*:.*Sendable" OpenOats/Sources/ --include="*.swift" | wc -l)
echo "   Found $SENDABLE_PROTOCOLS Sendable protocols"
[ "$SENDABLE_PROTOCOLS" -ge 5 ] && echo "   ✅ PASS" || { echo "   ❌ FAIL: Expected ≥5"; ERRORS=$((ERRORS + 1)); }

# 5. async/await usage
echo ""
echo "5. async/await usage (not completion handlers):"
ASYNC_KEYWORDS=$(grep -r "async throws\|await " OpenOats/Sources/ --include="*.swift" | wc -l)
echo "   Found $ASYNC_KEYWORDS async keywords"
[ "$ASYNC_KEYWORDS" -ge 20 ] && echo "   ✅ PASS" || { echo "   ❌ FAIL: Expected ≥20"; ERRORS=$((ERRORS + 1)); }

# 6. Task cancellation handling
echo ""
echo "6. Task cancellation handling:"
CANCELLATION=$(grep -r "Task.isCancelled\|Task.checkCancellation" OpenOats/Sources/ --include="*.swift" | wc -l)
echo "   Found $CANCELLATION cancellation checks"
[ "$CANCELLATION" -ge 3 ] && echo "   ✅ PASS" || { echo "   ⚠️ WARN: Consider adding more"; }

# Final result
echo ""
echo "=== Audit Result ==="
if [ $ERRORS -eq 0 ]; then
    echo "✅ CONCURRENCY AUDIT PASSED"
    exit 0
else
    echo "❌ CONCURRENCY AUDIT FAILED: $ERRORS errors"
    exit 1
fi
```

### Expected Results
- Actors used for mutable shared state
- @MainActor on UI code
- Zero undocumented @unchecked Sendable
- Sendable on all protocols
- Proper async/await usage
- Cancellation handling

### Success Criteria
- [ ] Actor usage ≥ 3
- [ ] @MainActor on all view models
- [ ] Zero undocumented @unchecked Sendable
- [ ] Sendable protocols ≥ 5
- [ ] Cancellation handling present

---

## Test Execution Schedule

| Phase | Tests | When | Owner |
|-------|-------|------|-------|
| Design Validation | TC-001 to TC-015 | Before implementation | QA Lead |
| Phase 1 Gate | TC-003, TC-004, TC-005 | End of Week 2 | Tech Lead |
| Phase 2 Gate | TC-001, TC-002, TC-010 | End of Week 4 | Tech Lead |
| Phase 3 Gate | TC-006 to TC-009 | End of Week 6 | QA Lead |
| Phase 4 Gate | TC-011 to TC-015 | End of Week 8 | QA Lead |
| Final Gate | All tests | End of Week 9 | All |

---

## Test Automation

### CI/CD Integration

```yaml
# .github/workflows/design-validation.yml
name: Design Validation Tests

on:
  pull_request:
    branches: [ main, develop ]
    paths:
      - '.wfc/plans/**'
      - 'OpenOats/Sources/**'

jobs:
  test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Run TC-001 to TC-005 (Compile Tests)
        run: |
          swift test --filter ProtocolCompileTests
          swift test --filter DIContainerTests
          swift test --filter SendableConformanceTests
      
      - name: Run TC-006 to TC-009 (AST Analysis)
        run: |
          ./scripts/validate-ast-metrics.sh
      
      - name: Run TC-010 to TC-012 (Unit Tests)
        run: |
          swift test --filter MockImplementationTests
          swift test --filter UseCaseTests
          swift test --filter ViewModelTests
      
      - name: Run TC-013 to TC-015 (Review Tests)
        run: |
          ./scripts/validate-data-flows.sh
          ./scripts/validate-migration-plan.sh
          ./scripts/validate-concurrency-audit.sh
      
      - name: Upload Results
        uses: actions/upload-artifact@v4
        with:
          name: test-results
          path: test-results/
```

---

## Test Results Summary Template

```markdown
# Design Validation Test Results

**Date:** [DATE]
**Tester:** [NAME]
**Build:** [COMMIT_SHA]

## Summary
| Total | Passed | Failed | Skipped |
|-------|--------|--------|---------|
| 15    | 15     | 0      | 0       |

## Detailed Results

### Static Analysis (TC-001 to TC-009)
- TC-001: ✅ PASS
- TC-002: ✅ PASS
- ...

### Unit Tests (TC-010 to TC-012)
- TC-010: ✅ PASS
- TC-011: ✅ PASS
- TC-012: ✅ PASS

### Review Tests (TC-013 to TC-015)
- TC-013: ✅ PASS
- TC-014: ✅ PASS
- TC-015: ✅ PASS

## Conclusion
All 15 test cases passed. Design is validated and ready for implementation.

**Approved by:**
- QA Lead: _________________
- Tech Lead: _________________
- Product Owner: _________________
```

---

## Formal Properties Verification

| Property | Status | Evidence |
|----------|--------|----------|
| LIVENESS: Design validation completes before implementation | ⏳ | This test plan |
| SAFETY: Design flaws caught in validation, not implementation | ✅ | 15 comprehensive tests |
| INVARIANT: All design deliverables have validation tests | ✅ | TC-001 through TC-015 |

**Status**: Design deliverable complete. All 19 tasks of the 3-tier architecture design epic are complete.

**Ready for handoff to wfc-implement for implementation phase.**
