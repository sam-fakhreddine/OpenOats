# TASK-009: Data Flow Diagrams

## Architecture Visualization

This document contains comprehensive Mermaid diagrams illustrating the 3-tier architecture, data flows, and component interactions.

---

## 1. Architecture Overview

### 4-Layer Structure with Dependencies

```mermaid
flowchart TB
    subgraph Presentation["Presentation Layer (UI)"]
        UI[SwiftUI Views]
        VM[ViewModels]
        CO[Coordinators]
    end
    
    subgraph Business["Business Logic Layer"]
        UC[Use Cases]
        MP[Domain Mappers]
    end
    
    subgraph Domain["Domain Layer"]
        EN[Entities]
        VA[Value Objects]
        ER[Error Types]
        ID[Identifiers]
    end
    
    subgraph Infrastructure["Infrastructure Layer"]
        REP[Repositories]
        SVC[Services]
        EXT[External Frameworks]
    end
    
    UI --> VM
    VM --> UC
    UC --> EN
    UC --> MP
    MP --> EN
    UC --> REP
    UC --> SVC
    REP --> VA
    SVC --> VA
    EN --> VA
    EN --> ID
    EN --> ER
    REP --> EXT
    SVC --> EXT
    
    style Presentation fill:#e1f5ff,stroke:#01579b
    style Business fill:#fff3e0,stroke:#e65100
    style Domain fill:#e8f5e9,stroke:#2e7d32
    style Infrastructure fill:#fce4ec,stroke:#c2185b
```

**Dependency Rule**: Dependencies flow inward only (outer layers depend on inner layers, never the reverse).

---

## 2. Session Lifecycle Flow

### Complete Session Flow: Start → Record → Transcribe → Stop → Save

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant UI as SessionView
    participant VM as SessionViewModel
    participant UC as StartSessionUseCase
    participant SS as SessionActor
    participant AR as AudioCaptureService
    participant TS as TranscriptionService
    participant SR as SessionRepository
    
    User->>UI: Tap "Start Recording"
    UI->>VM: startRecording(title, source)
    
    VM->>UC: execute(input)
    activate UC
    
    UC->>AR: checkAuthorization()
    AR-->>UC: authorized
    
    UC->>TS: isAvailable
    TS-->>UC: true
    
    UC->>UC: Create Meeting + Session
    UC->>SS: Create session state
    activate SS
    
    UC->>SR: save(session)
    activate SR
    SR-->>UC: saved
    deactivate SR
    
    UC->>UC: Spawn background Task
    UC-->>VM: Return Session
    deactivate UC
    
    VM-->>UI: Update UI state
    UI-->>User: Show recording UI
    
    par Audio Capture
        AR->>AR: captureLoop()
        loop Every 100ms
            AR->>SS: feedAudio(buffer)
        end
    and Transcription
        TS->>TS: transcriptionLoop()
        loop AsyncStream
            TS->>SS: updateSegment(segment)
        end
    end
    
    User->>UI: Tap "Stop Recording"
    UI->>VM: stopRecording()
    
    VM->>UC: StopSessionUseCase
    UC->>AR: stopCapture()
    UC->>SS: finalize()
    UC->>SR: save(finalSession)
    
    SS-->>UC: finalized
    deactivate SS
    
    UC-->>VM: Return finalized Session
    VM-->>UI: Update UI
    UI-->>User: Show completed session
```

---

## 3. Real-Time Transcription Flow

### Audio → Segments → UI Updates with Actor Isolation

```mermaid
sequenceDiagram
    autonumber
    participant AC as AudioCaptureService
    participant TA as TranscriptionActor
    participant TT as TranscriptionTask
    participant VM as TranscriptViewModel
    participant UI as TranscriptView
    
    Note over AC,UI: Actor Isolation Boundaries
    
    rect rgb(255, 240, 240)
        Note over AC: Audio Thread (Non-isolated)
        AC->>AC: audioTapCallback(buffer)
        AC->>TA: feedAudio(buffer)
    end
    
    rect rgb(240, 255, 240)
        Note over TA: TranscriptionActor
        TA->>TA: Process audio chunks
        TA->>TA: VAD detection
        
        opt Speech Detected
            TA->>TT: Spawn child Task
            activate TT
        end
        
        TT->>TT: Run inference
        TT-->>TA: Return segment
        deactivate TT
        
        TA->>TA: Merge partial results
        TA->>VM: publish(segment)
    end
    
    rect rgb(240, 240, 255)
        Note over VM: @MainActor
        VM->>VM: Update @Published var
        VM->>UI: SwiftUI observation
    end
    
    UI-->>UI: Re-render transcript
```

---

## 4. Note Generation Flow

### Transcript → AI → Notes → Display

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant UI as MeetingDetailView
    participant VM as NotesViewModel
    participant UC as GenerateNotesUseCase
    participant TR as TranscriptRepository
    participant LLM as LLMService
    participant AI as OpenRouter/Ollama
    
    User->>UI: Tap "Generate Notes"
    UI->>VM: generateNotes(types)
    
    VM->>UC: execute(input)
    activate UC
    
    UC->>TR: load(transcriptID)
    TR-->>UC: Transcript
    
    Note over UC: Parallel Generation with TaskGroup
    
    UC->>UC: withTaskGroup { group
    
    loop For each noteType
        UC->>UC: group.addTask
        UC->>LLM: complete(prompt)
        activate LLM
        LLM->>AI: API Request
        AI-->>LLM: Generated content
        LLM-->>UC: Note content
        deactivate LLM
    end
    
    UC->>UC: for await note in group
    UC->>UC: Collect all notes
    
    UC-->>VM: GenerateNotesOutput
    deactivate UC
    
    VM->>VM: Update @Published notes
    VM-->>UI: SwiftUI observation
    UI-->>User: Display generated notes
```

---

## 5. Error Propagation Flow

### How Errors Flow: Infrastructure → Business → Presentation

```mermaid
flowchart TB
    subgraph InfraErrors["Infrastructure Layer Errors"]
        direction TB
        TE[TranscriptionError]
        SE[StorageError]
        NE[NetworkError]
        AE[AudioError]
        
        TE_DETAIL["• backendFailed<br/>• audioFormatUnsupported<br/>• timeout"]
        SE_DETAIL["• persistenceFailed<br/>• corruptionDetected<br/>• migrationFailed"]
        NE_DETAIL["• connectivityFailed<br/>• apiError<br/>• rateLimited"]
        AE_DETAIL["• captureFailed<br/>• permissionDenied<br/>• formatConversionFailed"]
        
        TE --> TE_DETAIL
        SE --> SE_DETAIL
        NE --> NE_DETAIL
        AE --> AE_DETAIL
    end
    
    subgraph BizErrors["Business Logic Layer"]
        direction TB
        UC["Use Case Error Handling"]
        UC_DETAIL["• Map infra → domain errors<br/>• Add context<br/>• Set recoverable flag"]
        UC --> UC_DETAIL
    end
    
    subgraph PresErrors["Presentation Layer"]
        direction TB
        VM[ViewModel Error Handling]
        UI[UI Error Display]
        
        VM_DETAIL["• Catch errors<br/>• Update @Published error<br/>• Set showError flag"]
        UI_DETAIL["• Show alert on showError<br/>• Display localized description<br/>• Offer retry action"]
        
        VM --> VM_DETAIL
        UI --> UI_DETAIL
    end
    
    InfraErrors -->|"throws(StorageError)<br/>throws(TranscriptionError)"| BizErrors
    BizErrors -->|"throws(Error)"| PresErrors
    
    style InfraErrors fill:#fce4ec,stroke:#c2185b
    style BizErrors fill:#fff3e0,stroke:#e65100
    style PresErrors fill:#e1f5ff,stroke:#01579b
```

### Detailed Error Propagation Sequence

```mermaid
sequenceDiagram
    autonumber
    participant INF as Infrastructure
    participant UC as UseCase
    participant VM as ViewModel
    participant UI as View
    
    Note over INF,UI: Error Propagation Chain
    
    alt Storage Error
        INF->>INF: File write fails
        INF->>UC: throw StorageError.persistenceFailed
        UC->>UC: Catch, add context
        UC->>VM: throw with context
        VM->>VM: error = caughtError
        VM->>VM: showError = true
        VM->>UI: @Published update
        UI->>UI: .alert("Error", isPresented: $showError)
        UI->>UI: Display: error.localizedDescription
        
    else Transcription Error
        INF->>INF: Backend timeout
        INF->>UC: throw TranscriptionError.timeout
        UC->>UC: Check if recoverable
        alt Recoverable
            UC->>UC: Retry with backoff
        else Not Recoverable
            UC->>VM: throw after max retries
        end
        VM->>VM: Handle error
        VM->>UI: Show with retry button
        
    else Network Error (AI Service)
        INF->>INF: API rate limited
        INF->>UC: throw NetworkError.rateLimited
        UC->>UC: Extract retryAfter
        UC->>VM: error + retryAfter
        VM->>UI: Show with countdown timer
    end
```

---

## 6. Dependency Injection Flow

### AppContainer Initialization and Dependency Resolution

```mermaid
sequenceDiagram
    autonumber
    participant App as OpenOatsApp
    participant CT as AppContainer
    participant SF as ServiceFactory
    participant RP as RepositoryFactory
    participant UC as UseCaseFactory
    participant VM as ViewModelFactory
    
    Note over App,VM: App Launch Sequence
    
    App->>CT: initialize()
    activate CT
    
    CT->>SF: registerServices()
    activate SF
    SF->>SF: register(TranscriptionServiceProtocol)<br/>→ MLXTranscriptionService()
    SF->>SF: register(AudioCaptureServiceProtocol)<br/>→ CoreAudioCaptureService()
    SF->>SF: register(LLMServiceProtocol)<br/>→ OpenRouterService()
    SF-->>CT: Services registered
    deactivate SF
    
    CT->>RP: registerRepositories()
    activate RP
    RP->>RP: register(SessionRepositoryProtocol)<br/>→ CoreDataSessionRepository()
    RP->>RP: register(TranscriptRepositoryProtocol)<br/>→ SwiftDataTranscriptRepository()
    RP->>RP: register(SettingsRepositoryProtocol)<br/>→ UserDefaultsRepository()
    RP-->>CT: Repositories registered
    deactivate RP
    
    CT->>UC: registerUseCases()
    activate UC
    UC->>CT: resolve dependencies for<br/>StartSessionUseCase
    CT-->>UC: SessionRepository,<br/>AudioCaptureService,<br/>TranscriptionService
    UC->>UC: Create use case instances
    UC-->>CT: Use cases registered
    deactivate UC
    
    CT->>VM: registerViewModels()
    activate VM
    VM->>CT: resolve dependencies for<br/>SessionViewModel
    CT-->>VM: StartSessionUseCase,<br/>StopSessionUseCase
    VM->>VM: Create view model instances
    VM-->>CT: View models registered
    deactivate VM
    
    CT-->>App: Container ready
    deactivate CT
    
    Note over App,VM: View Creation with DI
    
    App->>CT: resolve(SessionViewModel.self)
    CT->>VM: Create with injected use cases
    VM-->>CT: SessionViewModel instance
    CT-->>App: Return view model
    
    App->>UI: NotesView(viewModel: vm)
```

---

## 7. Backend Abstraction Flow

### Multiple Transcription Backends with Unified Interface

```mermaid
classDiagram
    class TranscriptionServiceProtocol {
        <<protocol>>
        +backendID: BackendID
        +isAvailable: Bool
        +supportedLanguages() async
        +configure(configuration)
    }
    
    class StreamingTranscriptionServiceProtocol {
        <<protocol>>
        +startStreaming() async
        +feedAudio(buffer) async
        +stopStreaming() async
        +isStreaming: Bool
    }
    
    class BatchTranscriptionServiceProtocol {
        <<protocol>>
        +transcribeFile(url) async
        +transcribeWithProgress(url) async
    }
    
    class MLXStreamingService {
        -model: WhisperModel
        -audioBuffer: CircularBuffer
        +startStreaming()
        +process(audioChunk)
    }
    
    class WhisperKitStreamingService {
        -whisperKit: WhisperKit
        -decoder: AudioDecoder
        +startStreaming()
        +encode(audioBuffer)
    }
    
    class AssemblyAIStreamingService {
        -websocket: WebSocket
        -apiKey: String
        +startStreaming()
        +send(audioData)
    }
    
    class TranscriptionServiceFactory {
        +makeService(backendID) any TranscriptionServiceProtocol
        +makeStreaming(backendID) any StreamingTranscriptionServiceProtocol
        +makeBatch(backendID) any BatchTranscriptionServiceProtocol
    }
    
    TranscriptionServiceProtocol <|-- StreamingTranscriptionServiceProtocol
    TranscriptionServiceProtocol <|-- BatchTranscriptionServiceProtocol
    StreamingTranscriptionServiceProtocol <|.. MLXStreamingService
    StreamingTranscriptionServiceProtocol <|.. WhisperKitStreamingService
    StreamingTranscriptionServiceProtocol <|.. AssemblyAIStreamingService
    TranscriptionServiceFactory ..> TranscriptionServiceProtocol : creates
```

### Backend Switching Sequence

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant UI as SettingsView
    participant VM as SettingsViewModel
    participant UC as SwitchBackendUseCase
    participant TF as TranscriptionFactory
    participant OLD as OldBackendService
    participant NEW as NewBackendService
    participant SR as SettingsRepository
    
    User->>UI: Select new backend
    UI->>VM: switchBackend(to)
    
    VM->>UC: execute(input)
    activate UC
    
    UC->>TF: makeService(newBackendID)
    TF->>NEW: Instantiate
    NEW-->>TF: newService
    TF-->>UC: newService
    
    UC->>NEW: isAvailable
    NEW-->>UC: true
    
    opt If currently streaming
        UC->>OLD: stopStreaming()
        UC->>UC: Transfer partial results
    end
    
    UC->>SR: save(newBackendID)
    SR-->>UC: saved
    
    UC->>TF: setCurrent(newService)
    
    UC-->>VM: Success
    deactivate UC
    
    VM-->>UI: Show confirmation
    UI-->>User: "Backend switched successfully"
```

---

## 8. Data Race Fix Flow (TASK-015)

### Before: @unchecked Sendable with Data Race Risk

```mermaid
flowchart LR
    subgraph Before["Before: Unsafe"]
        A[Thread 1] -->|"writes converter"| ST[StreamingTranscriber<br/>@unchecked Sendable]
        B[Thread 2] -->|"writes converter"| ST
        C[Audio Thread] -->|"reads converter"| ST
        
        note["Risk: EXC_BAD_ACCESS<br/>from concurrent access"]
    end
    
    style Before fill:#ffcccc,stroke:#cc0000
```

### After: Actor-Protected State

```mermaid
flowchart LR
    subgraph After["After: Safe"]
        A[Task 1] -->|"await actor.call()"| ACT[actor StreamingTranscriptionActor]
        B[Task 2] -->|"await actor.call()"| ACT
        C[Audio Thread] -->|"await actor.feedAudio()"| ACT
        
        ACT -->|"isolated state"| S["state:<br/>• converter<br/>• rateTracking<br/>• context"]
        
        note["Safe: Actor serializes<br/>all access"]
    end
    
    style After fill:#ccffcc,stroke:#00cc00
```

### Actor Isolation Sequence

```mermaid
sequenceDiagram
    autonumber
    participant AT as AudioThread
    participant ST as StreamingTranscriptionActor
    participant SL as Swift Runtime
    participant TT as TranscriptionTask
    
    Note over AT,TT: Actor Isolation Guarantees
    
    AT->>AT: audioTapCallback(buffer)
    AT->>SL: Task { await actor.feedAudio }
    
    SL->>ST: Check actor queue
    alt Actor busy
        SL->>SL: Suspend Task
        SL->>SL: Queue for later
    else Actor free
        SL->>ST: Execute feedAudio(buffer)
        ST->>ST: Process on actor queue
        ST->>ST: Update isolated state
        ST-->>SL: Complete
    end
    
    TT->>SL: await actor.getState()
    SL->>ST: Check actor queue
    SL->>SL: Suspend Task (if busy)
    SL->>ST: Execute when free
    ST->>ST: Read isolated state
    ST-->>TT: Return state
```

---

## 9. Memory Management Flow (TASK-016)

### Streaming Audio Processing (vs Load-All)

```mermaid
flowchart TB
    subgraph Old["Before: Unbounded Memory"]
        direction TB
        REC[2hr Recording<br/>48kHz] --> LOAD[readAllMono()]
        LOAD --> ARR["[Float] Array<br/>~2.6 GB"]
        ARR --> OOM[OOM Crash<br/>on 8GB Macs]
        
        style Old fill:#ffcccc,stroke:#cc0000
    end
    
    subgraph New["After: Bounded Memory"]
        direction TB
        REC2[Recording Stream] --> CHUNK[64K Frame Chunks]
        CHUNK --> POOL[Buffer Pool<br/>~768 KB max]
        POOL --> PROC[Process Chunk]
        PROC --> REUSE[Return to Pool]
        REUSE --> CHUNK
        
        style New fill:#ccffcc,stroke:#00cc00
    end
```

### AudioBuffer Pool Sequence

```mermaid
sequenceDiagram
    autonumber
    participant AC as AudioCapture
    participant BP as BufferPool
    participant P as Processor
    participant TS as TranscriptionService
    
    Note over AC,TS: Bounded Memory Architecture
    
    loop Audio Stream
        AC->>BP: acquireBuffer()
        alt Pool has free buffer
            BP-->>AC: Return buffer from pool
        else Pool empty
            BP->>BP: Allocate new buffer<br/>(max 12 buffers)
            BP-->>AC: Return new buffer
        end
        
        AC->>AC: Fill with audio samples
        AC->>P: process(buffer)
        
        P->>P: Downmix, resample
        P->>TS: transcribeChunk(buffer)
        TS->>TS: Run inference
        TS-->>P: Return segments
        
        P->>BP: releaseBuffer(buffer)
        BP->>BP: Reset buffer<br/>Return to pool
    end
```

---

## 10. SwiftUI Observation Pattern

### @Observable vs ObservableObject

```mermaid
flowchart TB
    subgraph OldPattern["ObservableObject Pattern"]
        VM1[SessionViewModel<br/>@Published var state]
        VM1 -->|"objectWillChange.send()"| OBS1[SwiftUI Observation]
        OBS1 -->|"Re-render view"| UI1[SessionView]
        
        note["Works on all iOS versions<br/>More boilerplate<br/>ObservableObject protocol"]
    end
    
    subgraph NewPattern["@Observable Pattern"]
        VM2[@Observable<br/>SessionViewModel<br/>var state]
        VM2 -->|"Automatic tracking"| OBS2[SwiftUI Observation]
        OBS2 -->|"Granular re-render"| UI2[SessionView]
        
        note["iOS 17+ only<br/>Less boilerplate<br/>Automatic dependency tracking"]
    end
    
    style OldPattern fill:#fff3e0,stroke:#e65100
    style NewPattern fill:#e8f5e9,stroke:#2e7d32
```

### Recommended Pattern for OpenOats

```swift
// For macOS 15+ targets, use @Observable
@MainActor
@Observable
class SessionViewModel {
    var isRecording: Bool = false
    var recordingDuration: Duration = .zero
    var currentSession: Session?
    
    // Dependencies injected
    private let startUseCase: any StartSessionUseCaseProtocol
    
    init(startUseCase: any StartSessionUseCaseProtocol) {
        self.startUseCase = startUseCase
    }
    
    func startRecording() async {
        // Observation is automatic
        isRecording = true
        
        let session = try? await startUseCase.execute(input: input)
        currentSession = session
    }
}
```

---

## Summary

These diagrams illustrate:

| Diagram | Purpose | Key Insight |
|---------|---------|-------------|
| Architecture Overview | Layer structure | 4 layers with inward-only dependencies |
| Session Lifecycle | Recording flow | Actor isolation at each boundary |
| Real-time Transcription | Audio → UI | AsyncStream for real-time updates |
| Note Generation | AI integration | TaskGroup for parallel generation |
| Error Propagation | Error handling | Typed throws with context preservation |
| Dependency Injection | App startup | Factory pattern with protocol conformance |
| Backend Abstraction | Multiple backends | Unified interface, swappable implementations |
| Data Race Fix | Thread safety | Actor isolation replaces @unchecked Sendable |
| Memory Management | Bounded memory | Buffer pool pattern prevents OOM |
| SwiftUI Observation | UI updates | @Observable for automatic tracking |

**All diagrams use standard Mermaid syntax** and can be rendered in:
- GitHub markdown
- Notion
- Obsidian
- VS Code with Mermaid extension
- Any Mermaid-compatible renderer

---

**Status**: Design deliverable complete
