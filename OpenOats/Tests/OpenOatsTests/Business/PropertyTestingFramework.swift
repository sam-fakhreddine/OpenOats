import Foundation
import Testing
@testable import OpenOatsKit

// MARK: - Property-Based Testing Framework (Lightweight)

/// A lightweight property-based testing framework for Swift 6.2
/// Generates random test cases to verify invariants hold across input space.
struct PropertyTest {
    let name: String
    let iterations: Int
    let property: () async throws -> Bool
}

/// Generator for random test data
struct Generator<T: Sendable> {
    let generate: () -> T
    
    func map<U: Sendable>(_ transform: @Sendable @escaping (T) -> U) -> Generator<U> {
        Generator<U> { transform(self.generate()) }
    }
    
    func flatMap<U: Sendable>(_ transform: @Sendable @escaping (T) -> Generator<U>) -> Generator<U> {
        Generator<U> { transform(self.generate()).generate() }
    }
}

// MARK: - Domain Type Generators

/// Generates random UUIDs
extension Generator where T == UUID {
    static var uuid: Generator<UUID> {
        Generator { UUID() }
    }
}

/// Generates random SessionIDs
extension Generator where T == SessionID {
    static var sessionID: Generator<SessionID> {
        Generator<UUID>.uuid.map { SessionID($0) }
    }
}

/// Generates random MeetingIDs
extension Generator where T == MeetingID {
    static var meetingID: Generator<MeetingID> {
        Generator<UUID>.uuid.map { MeetingID($0) }
    }
}

/// Generates random TranscriptIDs
extension Generator where T == TranscriptID {
    static var transcriptID: Generator<TranscriptID> {
        Generator<UUID>.uuid.map { TranscriptID($0) }
    }
}

/// Generates random NoteIDs
extension Generator where T == NoteID {
    static var noteID: Generator<NoteID> {
        Generator<UUID>.uuid.map { NoteID($0) }
    }
}

/// Generates random BackendIDs
extension Generator where T == BackendID {
    static var backendID: Generator<BackendID> {
        let backends = ["mlx-whisper", "whisperkit", "assemblyai", "elevenlabs-scribe", "parakeet", "qwen3"]
        return Generator { BackendID(backends.randomElement()!) }
    }
}

/// Generates random strings
extension Generator where T == String {
    static var string: Generator<String> {
        let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return Generator {
            let length = Int.random(in: 0...100)
            return String((0..<length).map { _ in chars.randomElement()! })
        }
    }
    
    static var nonEmptyString: Generator<String> {
        string.map { $0.isEmpty ? "test" : $0 }
    }
}

/// Generates random dates
extension Generator where T == Date {
    static var date: Generator<Date> {
        Generator {
            let interval = TimeInterval.random(in: 0...1_000_000_000)
            return Date(timeIntervalSince1970: interval)
        }
    }
}

/// Generates random SessionStatus values
extension Generator where T == SessionStatus {
    static var sessionStatus: Generator<SessionStatus> {
        Generator {
            let all: [SessionStatus] = [.active, .finalizing, .completed, .failed, .cancelled]
            return all.randomElement()!
        }
    }
}

/// Generates random Session entities
extension Generator where T == Session {
    static var session: Generator<Session> {
        Generator {
            let startTime = Date()
            let hasEndTime = Bool.random()
            let endTime = hasEndTime ? Date().addingTimeInterval(TimeInterval.random(in: 1...3600)) : nil
            let status = hasEndTime ? SessionStatus.completed : SessionStatus.active
            let backendID = Bool.random() ? BackendID("mlx-whisper") : nil
            
            return Session(
                id: Generator<SessionID>.sessionID.generate(),
                meetingID: Generator<MeetingID>.meetingID.generate(),
                startTime: startTime,
                endTime: endTime,
                status: status,
                backendID: backendID
            )
        }
    }
}

/// Generates random Transcript entities
extension Generator where T == Transcript {
    static var transcript: Generator<Transcript> {
        Generator {
            let utteranceCount = Int.random(in: 0...100)
            let utteranceIDs = (0..<utteranceCount).map { _ in UtteranceID() }
            
            return Transcript(
                id: Generator<TranscriptID>.transcriptID.generate(),
                sessionID: Generator<SessionID>.sessionID.generate(),
                language: ["en", "es", "fr", "de", "zh"].randomElement()!,
                utteranceIDs: utteranceIDs,
                isComplete: Bool.random()
            )
        }
    }
}

/// Generates random Note entities
extension Generator where T == Note {
    static var note: Generator<Note> {
        Generator {
            let categories: [Note.Category] = [.summary, .actionItem, .decision, .insight]
            
            return Note(
                id: Generator<NoteID>.noteID.generate(),
                sessionID: Generator<SessionID>.sessionID.generate(),
                content: Generator<String>.string.generate(),
                category: categories.randomElement()!,
                aiModel: Bool.random() ? AIModelInfo(provider: "openrouter", model: "gpt-4", requestID: UUID().uuidString) : nil,
                createdAt: Generator<Date>.date.generate()
            )
        }
    }
}

/// Generates random NoteGenerationStyle values
struct NoteGenerationStyle: Sendable {
    let style: String
    static let formal = NoteGenerationStyle(style: "formal")
    static let casual = NoteGenerationStyle(style: "casual")
    static let bulletPoints = NoteGenerationStyle(style: "bullet-points")
}

/// Generates random LLMProvider values
struct LLMProvider: Sendable {
    let provider: String
    static let openrouter = LLMProvider(provider: "openrouter")
    static let ollama = LLMProvider(provider: "ollama")
}

/// Generates random NoteSectionType values
enum NoteSectionType: Sendable {
    case summary, actionItems, decisions, keyPoints
    
    static var all: [NoteSectionType] {
        [.summary, .actionItems, .decisions, .keyPoints]
    }
}

/// Generates random ExportFormat values
enum ExportFormat: Sendable {
    case txt, json, markdown, srt
    
    static var all: [ExportFormat] {
        [.txt, .json, .markdown, .srt]
    }
}

/// Generates random AudioFormat values
enum AudioFormat: Sendable {
    case wav, mp3, m4a, flac
    
    static var all: [AudioFormat] {
        [.wav, .mp3, .m4a, .flac]
    }
}

/// Property test runner that executes a property multiple times
func forAll<T: Sendable>(
    _ generator: Generator<T>,
    iterations: Int = 100,
    file: StaticString = #file,
    line: UInt = #line
) -> (@Sendable (T) async throws -> Bool) async throws {
    return { property in
        var failures: [(input: T, error: Error)] = []
        
        for _ in 0..<iterations {
            let input = generator.generate()
            do {
                let result = try await property(input)
                if !result {
                    failures.append((input, TestFailure("Property returned false")))
                }
            } catch {
                failures.append((input, error))
            }
        }
        
        if !failures.isEmpty {
            throw PropertyTestFailure(
                message: "Property failed \(failures.count)/\(iterations) times",
                failures: failures,
                file: file,
                line: line
            )
        }
    }
}

/// Run a property test with multiple generators
func forAll2<T1: Sendable, T2: Sendable>(
    _ gen1: Generator<T1>,
    _ gen2: Generator<T2>,
    iterations: Int = 100,
    file: StaticString = #file,
    line: UInt = #line
) -> (@Sendable (T1, T2) async throws -> Bool) async throws {
    return { property in
        var failures: [(input: (T1, T2), error: Error)] = []
        
        for _ in 0..<iterations {
            let input = (gen1.generate(), gen2.generate())
            do {
                let result = try await property(input.0, input.1)
                if !result {
                    failures.append((input, TestFailure("Property returned false")))
                }
            } catch {
                failures.append((input, error))
            }
        }
        
        if !failures.isEmpty {
            throw PropertyTestFailure(
                message: "Property failed \(failures.count)/\(iterations) times",
                failures: failures.map { (input: (input.0, input.1), error: $0.error) },
                file: file,
                line: line
            )
        }
    }
}

/// Run a property test with three generators
func forAll3<T1: Sendable, T2: Sendable, T3: Sendable>(
    _ gen1: Generator<T1>,
    _ gen2: Generator<T2>,
    _ gen3: Generator<T3>,
    iterations: Int = 100,
    file: StaticString = #file,
    line: UInt = #line
) -> (@Sendable (T1, T2, T3) async throws -> Bool) async throws {
    return { property in
        var failures: [(input: (T1, T2, T3), error: Error)] = []
        
        for _ in 0..<iterations {
            let input = (gen1.generate(), gen2.generate(), gen3.generate())
            do {
                let result = try await property(input.0, input.1, input.2)
                if !result {
                    failures.append((input, TestFailure("Property returned false")))
                }
            } catch {
                failures.append((input, error))
            }
        }
        
        if !failures.isEmpty {
            throw PropertyTestFailure(
                message: "Property failed \(failures.count)/\(iterations) times",
                failures: failures.map { (input: (input.0, input.1, input.2), error: $0.error) },
                file: file,
                line: line
            )
        }
    }
}

// MARK: - Test Failure Types

struct TestFailure: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

struct PropertyTestFailure: Error {
    let message: String
    let failures: [(input: any Sendable, error: Error)]
    let file: StaticString
    let line: UInt
}

// MARK: - Test Helpers

/// Asserts that an async operation throws an error
func expectError<T>(
    _ operation: () async throws -> T,
    file: StaticString = #file,
    line: UInt = #line
) async -> Error? {
    do {
        _ = try await operation()
        return nil // No error thrown
    } catch {
        return error
    }
}

/// Asserts that an async operation completes within a timeout
func completesWithin<T: Sendable>(
    timeout: Duration,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withTimeout(timeout, operation: operation)
}

/// Timeout helper
func withTimeout<T: Sendable>(
    _ timeout: Duration,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        
        group.addTask {
            try await Task.sleep(for: timeout)
            throw TimeoutError()
        }
        
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

struct TimeoutError: Error {}

/// Test that two executions produce equivalent results (determinism/idempotency check)
func expectEquivalent<T: Equatable & Sendable>(
    _ operation1: @escaping @Sendable () async throws -> T,
    _ operation2: @escaping @Sendable () async throws -> T,
    file: StaticString = #file,
    line: UInt = #line
) async throws -> Bool {
    let result1 = try await operation1()
    let result2 = try await operation2()
    return result1 == result2
}
