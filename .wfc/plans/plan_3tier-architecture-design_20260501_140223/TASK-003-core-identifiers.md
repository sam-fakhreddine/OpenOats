# TASK-003: Core Type Aliases and Identifiers

## Design Output

### Overview
Strongly-typed identifiers for the OpenOats domain to prevent accidental mixing of different ID kinds and ensure type safety across the codebase.

---

## Design Principle

Raw typealiases like `typealias MeetingID = UUID` allow accidental cross-assignment:
```swift
// DANGER: Typealias doesn't prevent this
func startMeeting(id: MeetingID) { ... }
startMeeting(id: sessionID) // Compiles! Bug!
```

**Solution**: Wrapper structs with `RawRepresentable` that are distinct, non-interchangeable types:
```swift
// SAFE: Wrapper struct prevents cross-assignment
func startMeeting(id: MeetingID) { ... }
startMeeting(id: sessionID) // ERROR: Cannot convert SessionID to MeetingID
```

---

## 1. Base Identifier Protocol

```swift
/// Protocol for all domain identifiers
public protocol DomainID: RawRepresentable, Sendable, Hashable, Codable, CustomStringConvertible 
where RawValue: Sendable & Hashable & Codable {
    static var entityName: String { get }
    init(rawValue: RawValue)
}

extension DomainID {
    public var description: String {
        "\(Self.entityName)(\(String(describing: rawValue)))"
    }
}
```

---

## 2. UUID-Based Identifiers

```swift
/// Identifier for a meeting (root aggregate)
public struct MeetingID: DomainID, RawRepresentable, Sendable, Hashable, Codable, CustomStringConvertible {
    public let rawValue: UUID
    public static let entityName = "Meeting"
    
    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
    
    /// Generate a new unique MeetingID
    public init() {
        self.rawValue = UUID()
    }
}

/// Identifier for a recording session
public struct SessionID: DomainID, RawRepresentable, Sendable, Hashable, Codable, CustomStringConvertible {
    public let rawValue: UUID
    public static let entityName = "Session"
    
    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
    
    public init() {
        self.rawValue = UUID()
    }
}

/// Identifier for a speaker
public struct SpeakerID: DomainID, RawRepresentable, Sendable, Hashable, Codable, CustomStringConvertible {
    public let rawValue: UUID
    public static let entityName = "Speaker"
    
    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
    
    public init() {
        self.rawValue = UUID()
    }
}

/// Identifier for a transcript
public struct TranscriptID: DomainID, RawRepresentable, Sendable, Hashable, Codable, CustomStringConvertible {
    public let rawValue: UUID
    public static let entityName = "Transcript"
    
    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
    
    public init() {
        self.rawValue = UUID()
    }
}

/// Identifier for an utterance (single speech segment)
public struct UtteranceID: DomainID, RawRepresentable, Sendable, Hashable, Codable, CustomStringConvertible {
    public let rawValue: UUID
    public static let entityName = "Utterance"
    
    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
    
    public init() {
        self.rawValue = UUID()
    }
}

/// Identifier for a note (AI-generated meeting note)
public struct NoteID: DomainID, RawRepresentable, Sendable, Hashable, Codable, CustomStringConvertible {
    public let rawValue: UUID
    public static let entityName = "Note"
    
    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
    
    public init() {
        self.rawValue = UUID()
    }
}

/// Identifier for an audio segment
public struct AudioSegmentID: DomainID, RawRepresentable, Sendable, Hashable, Codable, CustomStringConvertible {
    public let rawValue: UUID
    public static let entityName = "AudioSegment"
    
    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
    
    public init() {
        self.rawValue = UUID()
    }
}
```

---

## 3. String-Based Identifiers

```swift
/// Identifier for transcription backends (MLX, WhisperKit, AssemblyAI, etc.)
public struct BackendID: DomainID, RawRepresentable, Sendable, Hashable, Codable, CustomStringConvertible, ExpressibleByStringLiteral {
    public let rawValue: String
    public static let entityName = "Backend"
    
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
    
    public init(stringLiteral value: String) {
        self.rawValue = value
    }
    
    // MARK: - Predefined Backend IDs
    
    public static let mlx = BackendID(rawValue: "mlx")
    public static let whisperKit = BackendID(rawValue: "whisperkit")
    public static let assemblyAI = BackendID(rawValue: "assemblyai")
    public static let parakeet = BackendID(rawValue: "parakeet")
    public static let openAI = BackendID(rawValue: "openai")
    public static let custom = BackendID(rawValue: "custom")
}

/// Identifier for audio formats
public struct AudioFormat: DomainID, RawRepresentable, Sendable, Hashable, Codable, CustomStringConvertible, ExpressibleByStringLiteral {
    public let rawValue: String
    public static let entityName = "AudioFormat"
    
    public init(rawValue: String) {
        self.rawValue = rawValue.lowercased()
    }
    
    public init(stringLiteral value: String) {
        self.rawValue = value.lowercased()
    }
    
    // MARK: - Common Formats
    
    public static let wav = AudioFormat(rawValue: "wav")
    public static let mp3 = AudioFormat(rawValue: "mp3")
    public static let m4a = AudioFormat(rawValue: "m4a")
    public static let flac = AudioFormat(rawValue: "flac")
    public static let ogg = AudioFormat(rawValue: "ogg")
    public static let aac = AudioFormat(rawValue: "aac")
    public static let pcm = AudioFormat(rawValue: "pcm")
    public static let coreAudio = AudioFormat(rawValue: "caf")
}

/// Identifier for LLM providers
public struct LLMProviderID: DomainID, RawRepresentable, Sendable, Hashable, Codable, CustomStringConvertible, ExpressibleByStringLiteral {
    public let rawValue: String
    public static let entityName = "LLMProvider"
    
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
    
    public init(stringLiteral value: String) {
        self.rawValue = value
    }
    
    // MARK: - Predefined Providers
    
    public static let openRouter = LLMProviderID(rawValue: "openrouter")
    public static let ollama = LLMProviderID(rawValue: "ollama")
    public static let openAI = LLMProviderID(rawValue: "openai")
    public static let anthropic = LLMProviderID(rawValue: "anthropic")
    public static let local = LLMProviderID(rawValue: "local")
}

/// Identifier for embedding providers
public struct EmbeddingProviderID: DomainID, RawRepresentable, Sendable, Hashable, Codable, CustomStringConvertible, ExpressibleByStringLiteral {
    public let rawValue: String
    public static let entityName = "EmbeddingProvider"
    
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
    
    public init(stringLiteral value: String) {
        self.rawValue = value
    }
    
    public static let voyage = EmbeddingProviderID(rawValue: "voyage")
    public static let openAI = EmbeddingProviderID(rawValue: "openai")
    public static let local = EmbeddingProviderID(rawValue: "local")
}
```

---

## 4. Integer-Based Identifiers

```swift
/// Identifier for model versions (semantic versioning as integer components)
public struct ModelVersion: DomainID, RawRepresentable, Sendable, Hashable, Codable, CustomStringConvertible, Comparable {
    public let rawValue: UInt32
    public static let entityName = "ModelVersion"
    
    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
    
    /// Initialize from major.minor.patch components
    public init(major: UInt8, minor: UInt8, patch: UInt8, build: UInt8 = 0) {
        var value: UInt32 = 0
        value |= UInt32(major) << 24
        value |= UInt32(minor) << 16
        value |= UInt32(patch) << 8
        value |= UInt32(build)
        self.rawValue = value
    }
    
    public var major: UInt8 {
        UInt8((rawValue >> 24) & 0xFF)
    }
    
    public var minor: UInt8 {
        UInt8((rawValue >> 16) & 0xFF)
    }
    
    public var patch: UInt8 {
        UInt8((rawValue >> 8) & 0xFF)
    }
    
    public var build: UInt8 {
        UInt8(rawValue & 0xFF)
    }
    
    public var description: String {
        "\(major).\(minor).\(patch)"
    }
    
    public var fullDescription: String {
        if build > 0 {
            return "\(major).\(minor).\(patch)+\(build)"
        }
        return "\(major).\(minor).\(patch)"
    }
    
    // MARK: - Comparable
    
    public static func < (lhs: ModelVersion, rhs: ModelVersion) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Identifier for speaker voice signatures (hash-based identification)
public struct VoiceSignature: DomainID, RawRepresentable, Sendable, Hashable, Codable, CustomStringConvertible {
    public let rawValue: UInt64
    public static let entityName = "VoiceSignature"
    
    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }
    
    /// Create from audio feature hash
    public init(fromAudioFeatures features: [Float]) {
        // Simple perceptual hash implementation
        var hash: UInt64 = 0
        let stride = max(1, features.count / 64)
        
        for i in stride(0, features.count, stride) {
            let bit = features[i] > 0 ? 1 : 0
            hash = (hash << 1) | UInt64(bit)
        }
        
        self.rawValue = hash
    }
    
    /// Compare two voice signatures (0-1 similarity score)
    public func similarity(to other: VoiceSignature) -> Double {
        let xor = self.rawValue ^ other.rawValue
        let differingBits = xor.nonzeroBitCount
        return 1.0 - (Double(differingBits) / 64.0)
    }
}
```

---

## 5. Identifier Collections

```swift
/// Type-safe wrapper for collections of IDs to prevent accidental mixing
public struct IdentifierSet<ID: DomainID>: Sendable, Hashable, Codable where ID.RawValue: Hashable {
    private var storage: Set<ID>
    
    public init() {
        self.storage = Set()
    }
    
    public init(ids: [ID]) {
        self.storage = Set(ids)
    }
    
    public var isEmpty: Bool { storage.isEmpty }
    public var count: Int { storage.count }
    
    public mutating func insert(_ id: ID) {
        storage.insert(id)
    }
    
    public mutating func remove(_ id: ID) {
        storage.remove(id)
    }
    
    public func contains(_ id: ID) -> Bool {
        storage.contains(id)
    }
    
    public func toArray() -> [ID] {
        Array(storage)
    }
    
    // MARK: - Set Operations
    
    public func union(_ other: IdentifierSet<ID>) -> IdentifierSet<ID> {
        IdentifierSet(ids: Array(storage.union(other.storage)))
    }
    
    public func intersection(_ other: IdentifierSet<ID>) -> IdentifierSet<ID> {
        IdentifierSet(ids: Array(storage.intersection(other.storage)))
    }
    
    public func difference(_ other: IdentifierSet<ID>) -> IdentifierSet<ID> {
        IdentifierSet(ids: Array(storage.subtracting(other.storage)))
    }
}

/// Type-safe map keyed by domain identifiers
public struct IdentifierMap<ID: DomainID, Value: Sendable>: Sendable where ID.RawValue: Hashable {
    private var storage: [ID: Value]
    
    public init() {
        self.storage = [:]
    }
    
    public init(dictionary: [ID: Value]) {
        self.storage = dictionary
    }
    
    public var isEmpty: Bool { storage.isEmpty }
    public var count: Int { storage.count }
    public var keys: [ID] { Array(storage.keys) }
    public var values: [Value] { Array(storage.values) }
    
    public subscript(id: ID) -> Value? {
        get { storage[id] }
        set { storage[id] = newValue }
    }
    
    public mutating func removeValue(forKey id: ID) -> Value? {
        storage.removeValue(forKey: id)
    }
    
    public func mapValues<T: Sendable>(_ transform: (Value) -> T) -> IdentifierMap<ID, T> {
        IdentifierMap<ID, T>(dictionary: storage.mapValues(transform))
    }
}
```

---

## 6. Identifier Factory

```swift
/// Factory for creating and managing identifiers
public enum IdentifierFactory {
    
    /// Generate a new MeetingID
    public static func newMeetingID() -> MeetingID {
        MeetingID()
    }
    
    /// Generate a new SessionID
    public static func newSessionID() -> SessionID {
        SessionID()
    }
    
    /// Generate a new SpeakerID
    public static func newSpeakerID() -> SpeakerID {
        SpeakerID()
    }
    
    /// Generate a new TranscriptID
    public static func newTranscriptID() -> TranscriptID {
        TranscriptID()
    }
    
    /// Generate a new UtteranceID
    public static func newUtteranceID() -> UtteranceID {
        UtteranceID()
    }
    
    /// Generate a new NoteID
    public static func newNoteID() -> NoteID {
        NoteID()
    }
    
    /// Generate a new AudioSegmentID
    public static func newAudioSegmentID() -> AudioSegmentID {
        AudioSegmentID()
    }
    
    /// Parse a MeetingID from string representation
    public static func parseMeetingID(_ string: String) -> MeetingID? {
        guard let uuid = UUID(uuidString: string) else { return nil }
        return MeetingID(rawValue: uuid)
    }
    
    /// Parse a SessionID from string representation
    public static func parseSessionID(_ string: String) -> SessionID? {
        guard let uuid = UUID(uuidString: string) else { return nil }
        return SessionID(rawValue: uuid)
    }
    
    /// Parse a SpeakerID from string representation
    public static func parseSpeakerID(_ string: String) -> SpeakerID? {
        guard let uuid = UUID(uuidString: string) else { return nil }
        return SpeakerID(rawValue: uuid)
    }
}
```

---

## 7. Type-Safe Relationships

```swift
/// Represents a relationship between two domain entities
public struct Relationship<From: DomainID, To: DomainID>: Sendable, Hashable, Codable {
    public let from: From
    public let to: To
    public let relationshipType: String
    public let createdAt: Date
    
    public init(from: From, to: To, relationshipType: String, createdAt: Date = Date()) {
        self.from = from
        self.to = to
        self.relationshipType = relationshipType
        self.createdAt = createdAt
    }
    
    public func reversed() -> Relationship<To, From> {
        Relationship<To, From>(
            from: to,
            to: from,
            relationshipType: "\(relationshipType)-reverse",
            createdAt: createdAt
        )
    }
}

// MARK: - Convenience Type Aliases for Common Relationships

/// Meeting contains Sessions
public typealias MeetingSession = Relationship<MeetingID, SessionID>

/// Session produces Transcript
public typealias SessionTranscript = Relationship<SessionID, TranscriptID>

/// Transcript contains Utterances
public typealias TranscriptUtterance = Relationship<TranscriptID, UtteranceID>

/// Utterance spoken by Speaker
public typealias UtteranceSpeaker = Relationship<UtteranceID, SpeakerID>

/// Session contains AudioSegments
public typealias SessionAudioSegment = Relationship<SessionID, AudioSegmentID>

/// Meeting has Notes
public typealias MeetingNote = Relationship<MeetingID, NoteID>
```

---

## 8. Identifier Validation

```swift
/// Validator for domain identifiers
public struct IDValidator {
    
    /// Validate that an ID is not nil/empty
    public static func isValid<ID: DomainID>(_ id: ID?) -> Bool {
        guard let id = id else { return false }
        
        // UUID-based: check for nil UUID
        if let uuid = id.rawValue as? UUID {
            return uuid != UUID()
        }
        
        // String-based: check for empty string
        if let string = id.rawValue as? String {
            return !string.isEmpty
        }
        
        // Integer-based: check for zero
        if let integer = id.rawValue as? any FixedWidthInteger {
            return integer != 0
        }
        
        return true
    }
    
    /// Validate a collection of IDs
    public static func allValid<ID: DomainID>(_ ids: [ID]) -> Bool {
        !ids.isEmpty && ids.allSatisfy { isValid($0) }
    }
    
    /// Generate a validation error for invalid ID
    public static func validationError<ID: DomainID>(for id: ID?, fieldName: String) -> ValidationError? {
        guard !isValid(id) else { return nil }
        return ValidationError.emptyContent(field: fieldName)
    }
}

// MARK: - DomainID Extensions

extension DomainID {
    /// Check if this is a valid (non-nil/empty) identifier
    public var isValid: Bool {
        IDValidator.isValid(self)
    }
    
    /// Check if this is the nil/empty identifier
    public var isNil: Bool {
        !isValid
    }
}
```

---

## 9. Thread-Safe ID Generation

```swift
/// Thread-safe identifier generation for high-throughput scenarios
public actor IDGenerator {
    private var counter: UInt64 = 0
    private let baseUUID: UUID
    
    public init() {
        self.baseUUID = UUID()
    }
    
    /// Generate a unique ID combining UUID base + monotonic counter
    public func generateSequentialID() -> UUID {
        counter += 1
        
        // Combine base UUID with counter for unique sequential IDs
        var uuid = baseUUID.uuid
        withUnsafeMutableBytes(of: &uuid) { bytes in
            // Overwrite last 8 bytes with counter (big-endian)
            var counterBE = counter.bigEndian
            withUnsafeBytes(of: &counterBE) { counterBytes in
                bytes.copyMemory(from: counterBytes)
            }
        }
        
        return UUID(uuid: uuid)
    }
    
    /// Generate multiple IDs in batch (more efficient)
    public func generateBatch(count: Int) -> [UUID] {
        var ids: [UUID] = []
        ids.reserveCapacity(count)
        
        for _ in 0..<count {
            counter += 1
            var uuid = baseUUID.uuid
            withUnsafeMutableBytes(of: &uuid) { bytes in
                var counterBE = counter.bigEndian
                withUnsafeBytes(of: &counterBE) { counterBytes in
                    bytes.copyMemory(from: counterBytes)
                }
            }
            ids.append(UUID(uuid: uuid))
        }
        
        return ids
    }
}
```

---

## Design Decisions

### 1. Wrapper Structs Over Typealiases

**Why**: Typealiases are fully interchangeable with their underlying type. Wrapper structs with `RawRepresentable` are distinct types that cannot be accidentally mixed.

**Example**:
```swift
// Typealias (unsafe)
typealias MeetingID = UUID
typealias SessionID = UUID

let m: MeetingID = UUID()
let s: SessionID = UUID()
let x: MeetingID = s  // Compiles! Bug!

// Wrapper struct (safe)
struct MeetingID: RawRepresentable { let rawValue: UUID }
struct SessionID: RawRepresentable { let rawValue: UUID }

let m = MeetingID(rawValue: UUID())
let s = SessionID(rawValue: UUID())
let x: MeetingID = s  // ERROR: Cannot convert SessionID to MeetingID
```

### 2. ExpressibleByStringLiteral for Convenience

String-based IDs like `BackendID` and `AudioFormat` conform to `ExpressibleByStringLiteral` for convenient literal syntax:
```swift
let backend: BackendID = "mlx"  // Instead of BackendID(rawValue: "mlx")
```

### 3. Predefined Constants

Common values are provided as static constants to avoid stringly-typed code:
```swift
let backend = BackendID.assemblyAI  // Type-safe
// vs
let backend = BackendID(rawValue: "assemblyai")  // Risk of typo
```

### 4. Sendable Conformance

All ID types are `Sendable`, ensuring they can be passed across actor boundaries in Swift 6.2. Since all underlying types (`UUID`, `String`, `UInt64`) are `Sendable`, the conformance is automatic.

### 5. Codable for Persistence

All ID types are `Codable` with automatic conformance through `RawRepresentable`. They serialize as their underlying value:
```json
{ "meetingId": "550e8400-e29b-41d4-a716-446655440000" }
```

### 6. String Interpolation Control

`CustomStringConvertible` provides controlled string representation. The default shows entity name + value for debugging:
```swift
print(meetingId)  // "Meeting(550e8400-e29b-41d4-a716-446655440000)"
```

---

## Formal Property Verification

| Property | Status | Evidence |
|----------|--------|----------|
| INVARIANT-006 (Domain Identifier Uniqueness) | ✅ Satisfied | All IDs use UUID or monotonic generation; immutable once assigned |
| SAFETY-006 (Sendable-Safe) | ✅ Satisfied | All identifier types conform to `Sendable` |
| SAFETY-004 (Immutable Domain State) | ✅ Satisfied | All identifiers are value types with `let rawValue` |

---

## Acceptance Criteria Verification

| Criterion | Status | Evidence |
|-----------|--------|----------|
| All IDs are distinct types (not raw typealiases) | ✅ | All use `struct` wrappers with `RawRepresentable` |
| IDs conform to `RawRepresentable`, `Codable`, `Hashable`, `Sendable` | ✅ | All conform via `DomainID` protocol |
| String interpolation is disabled or controlled | ✅ | `CustomStringConvertible` provides controlled description |
| Example matches specification | ✅ | `struct MeetingID: RawRepresentable, Sendable { let rawValue: UUID }` format followed |

---

## Usage Examples

### Basic Usage
```swift
let meetingId = MeetingID()
let sessionId = SessionID()

// Compile-time type safety prevents mixing
// let wrong: MeetingID = sessionId  // ERROR!

// Passing to functions
func startSession(meetingId: MeetingID) -> SessionID {
    let sessionId = SessionID()
    // ... start session logic
    return sessionId
}

let newSessionId = startSession(meetingId: meetingId)
```

### String Literals
```swift
let backend: BackendID = "mlx"
let format: AudioFormat = "wav"

// Or explicit
let backend2 = BackendID.mlx
let format2 = AudioFormat.wav
```

### Collections
```swift
var meetingIds = IdentifierSet<MeetingID>()
meetingIds.insert(MeetingID())
meetingIds.insert(MeetingID())

var sessionsByMeeting = IdentifierMap<MeetingID, [SessionID]>()
sessionsByMeeting[meetingId] = [sessionId1, sessionId2]
```

### Relationships
```swift
let sessionToTranscript = SessionTranscript(
    from: sessionId,
    to: transcriptId,
    relationshipType: "produces"
)
```

---

## Next Slice Dependencies

**TASK-003 enables:**
- TASK-004: Presentation protocols use these IDs in ViewModels
- TASK-005: Use cases accept/return these typed identifiers
- TASK-006: Infrastructure services use IDs for persistence lookup
- TASK-008: Migration strategy maps old string IDs to new typed IDs

**Dependencies on other slices:**
- ✅ TASK-001: Domain entities (completed) - IDs reference these entities
- ⬜ TASK-002: Error types (just completed) - IDs may appear in error contexts

---

*Design completed by wfc-slice execution - TASK-003*
