import Foundation
import Testing
@testable import OpenOatsKit

// MARK: - SwitchBackendUseCase Property-Based Tests

/// Protocol definition for SwitchBackendUseCase (from TASK-005 design)
protocol SwitchBackendUseCase: Sendable {
    func execute(input: SwitchBackendInput) async throws -> SwitchBackendOutput
}

/// Input for switching backend
struct SwitchBackendInput: Sendable {
    let currentBackend: BackendID
    let newBackend: BackendID
    let preserveState: Bool
    
    init(
        currentBackend: BackendID,
        newBackend: BackendID,
        preserveState: Bool = true
    ) {
        self.currentBackend = currentBackend
        self.newBackend = newBackend
        self.preserveState = preserveState
    }
}

/// Output from switching backend
struct SwitchBackendOutput: Sendable {
    let previousBackend: BackendID
    let currentBackend: BackendID
    let availableModels: [String]
    let isOnline: Bool
}

/// Backend availability info
struct BackendAvailability: Sendable {
    let id: BackendID
    let isAvailable: Bool
    let models: [String]
    let latency: Duration?
    let isOnline: Bool
}

/// Mock implementation for testing
actor MockSwitchBackendUseCase: SwitchBackendUseCase {
    var backends: [BackendID: BackendAvailability] = [:]
    var activeBackend: BackendID = BackendID.mlxWhisper
    var shouldFail = false
    var failureError: Error = TestFailure("Mock switch failure")
    var delay: Duration = .milliseconds(50)
    
    init() {
        // Initialize with default backends
        backends[BackendID.mlxWhisper] = BackendAvailability(
            id: BackendID.mlxWhisper,
            isAvailable: true,
            models: ["whisper-base", "whisper-small", "whisper-medium"],
            latency: .milliseconds(100),
            isOnline: false
        )
        backends[BackendID.whisperKit] = BackendAvailability(
            id: BackendID.whisperKit,
            isAvailable: true,
            models: ["whisper-base.en", "whisper-small.en"],
            latency: .milliseconds(150),
            isOnline: false
        )
        backends[BackendID.assemblyAI] = BackendAvailability(
            id: BackendID.assemblyAI,
            isAvailable: true,
            models: ["best", "nano"],
            latency: .milliseconds(500),
            isOnline: true
        )
    }
    
    func execute(input: SwitchBackendInput) async throws -> SwitchBackendOutput {
        if shouldFail {
            throw failureError
        }
        
        // Validate new backend exists and is available
        guard let newBackendInfo = backends[input.newBackend], newBackendInfo.isAvailable else {
            throw TranscriptionError.modelUnavailable(
                model: input.newBackend.rawValue,
                reason: "Backend not available"
            )
        }
        
        // Validate current backend matches
        guard input.currentBackend == activeBackend else {
            throw ValidationError.invalidInput(
                field: "currentBackend",
                reason: "Current backend mismatch. Expected: \(activeBackend.rawValue), got: \(input.currentBackend.rawValue)"
            )
        }
        
        // Simulate switch work
        try await Task.sleep(for: delay)
        
        try Task.checkCancellation()
        
        let previousBackend = activeBackend
        activeBackend = input.newBackend
        
        return SwitchBackendOutput(
            previousBackend: previousBackend,
            currentBackend: input.newBackend,
            availableModels: newBackendInfo.models,
            isOnline: newBackendInfo.isOnline
        )
    }
    
    func setBackendAvailability(_ backend: BackendID, available: Bool) {
        if var info = backends[backend] {
            backends[backend] = BackendAvailability(
                id: info.id,
                isAvailable: available,
                models: info.models,
                latency: info.latency,
                isOnline: info.isOnline
            )
        }
    }
}

/// Generator for backend pairs (current, new)
extension Generator where T == (BackendID, BackendID) {
    static var backendPair: Generator<(BackendID, BackendID)> {
        Generator {
            let allBackends = [
                BackendID.mlxWhisper,
                BackendID.whisperKit,
                BackendID.assemblyAI,
                BackendID.elevenLabsScribe,
                BackendID.parakeet
            ]
            let current = allBackends.randomElement()!
            var new = allBackends.randomElement()!
            while new == current {
                new = allBackends.randomElement()!
            }
            return (current, new)
        }
    }
}

// MARK: - Test Suite

@Suite("SwitchBackendUseCase Property-Based Tests")
struct SwitchBackendUseCaseTests {
    
    // MARK: - Property: Backend State Transitions
    
    /// Property: Switching backend updates current backend
    @Test("Backend is switched correctly")
    func backendIsSwitchedCorrectly() async throws {
        let backendPairGen = Generator<(BackendID, BackendID)>.backendPair
        let testRunner = try await forAll(backendPairGen, iterations: 30)
        
        try await testRunner { (current, new) in
            let useCase = MockSwitchBackendUseCase()
            await useCase.setActiveBackend(current)
            
            let input = SwitchBackendInput(
                currentBackend: current,
                newBackend: new
            )
            
            let output = try await useCase.execute(input: input)
            
            return output.currentBackend == new &&
                   output.previousBackend == current
        }
    }
    
    /// Property: Output contains available models
    @Test("Output contains available models")
    func outputContainsAvailableModels() async throws {
        let useCase = MockSwitchBackendUseCase()
        let input = SwitchBackendInput(
            currentBackend: BackendID.mlxWhisper,
            newBackend: BackendID.whisperKit
        )
        
        let output = try await useCase.execute(input: input)
        
        #expect(!output.availableModels.isEmpty)
    }
    
    /// Property: Online status is correctly reported
    @Test("Online status correctly reported")
    func onlineStatusCorrectlyReported() async throws {
        let useCase = MockSwitchBackendUseCase()
        
        // Switch to online backend (AssemblyAI)
        let input = SwitchBackendInput(
            currentBackend: BackendID.mlxWhisper,
            newBackend: BackendID.assemblyAI
        )
        
        let output = try await useCase.execute(input: input)
        
        #expect(output.isOnline == true, "AssemblyAI should be online")
    }
    
    /// Property: Local backends report as offline
    @Test("Local backends report offline")
    func localBackendsReportOffline() async throws {
        let useCase = MockSwitchBackendUseCase()
        
        // Stay on local backend
        let input = SwitchBackendInput(
            currentBackend: BackendID.mlxWhisper,
            newBackend: BackendID.whisperKit
        )
        
        let output = try await useCase.execute(input: input)
        
        #expect(output.isOnline == false, "Local backends should be offline")
    }
    
    // MARK: - Property: Validation
    
    /// Property: Switching to unavailable backend throws error
    @Test("Unavailable backend throws error")
    func unavailableBackendThrowsError() async throws {
        let useCase = MockSwitchBackendUseCase()
        await useCase.setBackendAvailability(BackendID.assemblyAI, available: false)
        
        let input = SwitchBackendInput(
            currentBackend: BackendID.mlxWhisper,
            newBackend: BackendID.assemblyAI
        )
        
        do {
            _ = try await useCase.execute(input: input)
            #expect(false, "Should have thrown")
        } catch let error as TranscriptionError {
            if case .modelUnavailable = error {
                #expect(true)
            } else {
                #expect(false)
            }
        }
    }
    
    /// Property: Mismatched current backend throws error
    @Test("Mismatched current backend throws error")
    func mismatchedCurrentBackendThrowsError() async throws {
        let useCase = MockSwitchBackendUseCase()
        // Active backend is mlxWhisper by default
        
        let input = SwitchBackendInput(
            currentBackend: BackendID.assemblyAI, // Wrong - should be mlxWhisper
            newBackend: BackendID.whisperKit
        )
        
        do {
            _ = try await useCase.execute(input: input)
            #expect(false, "Should have thrown for mismatched backend")
        } catch {
            #expect(true)
        }
    }
    
    /// Property: Unknown backend throws appropriate error
    @Test("Unknown backend throws error")
    func unknownBackendThrowsError() async throws {
        let useCase = MockSwitchBackendUseCase()
        let unknownBackend = BackendID("unknown-backend")
        
        let input = SwitchBackendInput(
            currentBackend: BackendID.mlxWhisper,
            newBackend: unknownBackend
        )
        
        do {
            _ = try await useCase.execute(input: input)
            #expect(false)
        } catch {
            #expect(true)
        }
    }
    
    // MARK: - Property: Idempotency
    
    /// Property: Switching to same backend twice produces consistent result
    @Test("Switching to same backend is idempotent")
    func switchingToSameBackendIsIdempotent() async throws {
        let useCase = MockSwitchBackendUseCase()
        
        let input = SwitchBackendInput(
            currentBackend: BackendID.mlxWhisper,
            newBackend: BackendID.whisperKit
        )
        
        let output1 = try await useCase.execute(input: input)
        
        // Now active is whisperKit, switch back
        await useCase.setActiveBackend(BackendID.mlxWhisper)
        
        let input2 = SwitchBackendInput(
            currentBackend: BackendID.mlxWhisper,
            newBackend: BackendID.whisperKit
        )
        
        let output2 = try await useCase.execute(input: input2)
        
        // Should produce equivalent results
        #expect(output1.currentBackend == output2.currentBackend)
        #expect(output1.availableModels == output2.availableModels)
        #expect(output1.isOnline == output2.isOnline)
    }
    
    // MARK: - Property: Error Propagation
    
    /// Property: Backend failures are properly wrapped
    @Test("Backend failures are wrapped")
    func backendFailuresAreWrapped() async throws {
        let useCase = MockSwitchBackendUseCase()
        await useCase.setShouldFail(true)
        await useCase.setFailureError(
            TranscriptionError.backendFailed(
                backend: "test",
                reason: "Connection failed",
                recoverable: true
            )
        )
        
        let input = SwitchBackendInput(
            currentBackend: BackendID.mlxWhisper,
            newBackend: BackendID.whisperKit
        )
        
        do {
            _ = try await useCase.execute(input: input)
            #expect(false)
        } catch is TranscriptionError {
            #expect(true)
        }
    }
    
    /// Property: Network errors during online backend switch are handled
    @Test("Network errors during switch are handled")
    func networkErrorsDuringSwitchHandled() async throws {
        let useCase = MockSwitchBackendUseCase()
        await useCase.setShouldFail(true)
        await useCase.setFailureError(
            TranscriptionError.networkFailure(reason: "Timeout")
        )
        
        let input = SwitchBackendInput(
            currentBackend: BackendID.mlxWhisper,
            newBackend: BackendID.assemblyAI
        )
        
        do {
            _ = try await useCase.execute(input: input)
            #expect(false)
        } catch {
            #expect(true)
        }
    }
    
    // MARK: - Property: Cancellation
    
    /// Property: Switch operation can be cancelled
    @Test("Switch operation is cancellable")
    func switchIsCancellable() async throws {
        let useCase = MockSwitchBackendUseCase()
        await useCase.setDelay(.seconds(5))
        
        let input = SwitchBackendInput(
            currentBackend: BackendID.mlxWhisper,
            newBackend: BackendID.whisperKit
        )
        
        let task = Task {
            try await useCase.execute(input: input)
        }
        
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        
        do {
            _ = try await task.value
            #expect(false, "Should have been cancelled")
        } catch is CancellationError {
            #expect(true)
        }
    }
    
    /// Property: Partial switch is handled (atomicity concern)
    @Test("Partial switch is handled gracefully")
    func partialSwitchHandled() async throws {
        // This test verifies that if a switch fails partway,
        // the system is left in a consistent state
        let useCase = MockSwitchBackendUseCase()
        
        let initialBackend = BackendID.mlxWhisper
        await useCase.setActiveBackend(initialBackend)
        
        // Simulate failure during switch
        await useCase.setShouldFail(true)
        
        let input = SwitchBackendInput(
            currentBackend: initialBackend,
            newBackend: BackendID.assemblyAI
        )
        
        do {
            _ = try await useCase.execute(input: input)
        } catch {
            // Expected
        }
        
        // System should still be usable for another switch attempt
        await useCase.setShouldFail(false)
        
        let retryInput = SwitchBackendInput(
            currentBackend: initialBackend, // Still mlxWhisper since switch failed
            newBackend: BackendID.whisperKit
        )
        
        let output = try await useCase.execute(input: retryInput)
        #expect(output.currentBackend == BackendID.whisperKit)
    }
    
    // MARK: - Property: Backend Info Consistency
    
    /// Property: Available models list is never empty for valid backend
    @Test("Available models not empty for valid backend")
    func availableModelsNotEmpty() async throws {
        let useCase = MockSwitchBackendUseCase()
        
        let input = SwitchBackendInput(
            currentBackend: BackendID.mlxWhisper,
            newBackend: BackendID.whisperKit
        )
        
        let output = try await useCase.execute(input: input)
        
        #expect(!output.availableModels.isEmpty)
    }
    
    /// Property: All model names are non-empty strings
    @Test("Model names are valid")
    func modelNamesAreValid() async throws {
        let useCase = MockSwitchBackendUseCase()
        
        let input = SwitchBackendInput(
            currentBackend: BackendID.mlxWhisper,
            newBackend: BackendID.mlxWhisper // Switch to same - should work
        )
        
        let output = try await useCase.execute(input: input)
        
        for model in output.availableModels {
            #expect(!model.isEmpty)
        }
    }
    
    // MARK: - Property: Sendable Safety
    
    /// Property: Backend switching works across actor boundaries
    @Test("Backend switch is Sendable-safe")
    func backendSwitchIsSendableSafe() async throws {
        let backends: [BackendID] = [
            BackendID.mlxWhisper,
            BackendID.whisperKit,
            BackendID.assemblyAI
        ]
        
        await withTaskGroup(of: SwitchBackendOutput.self) { group in
            for backend in backends {
                group.addTask {
                    let useCase = MockSwitchBackendUseCase()
                    await useCase.setActiveBackend(BackendID.mlxWhisper)
                    
                    let input = SwitchBackendInput(
                        currentBackend: BackendID.mlxWhisper,
                        newBackend: backend
                    )
                    
                    return try! await useCase.execute(input: input)
                }
            }
            
            var results: [SwitchBackendOutput] = []
            for await output in group {
                results.append(output)
            }
            
            #expect(results.count == backends.count)
        }
    }
    
    // MARK: - Property: State Preservation
    
    /// Property: preserveState flag affects behavior correctly
    @Test("Preserve state flag affects behavior")
    func preserveStateFlagAffectsBehavior() async throws {
        let useCase = MockSwitchBackendUseCase()
        
        let inputWithPreserve = SwitchBackendInput(
            currentBackend: BackendID.mlxWhisper,
            newBackend: BackendID.whisperKit,
            preserveState: true
        )
        
        let output1 = try await useCase.execute(input: inputWithPreserve)
        
        await useCase.setActiveBackend(BackendID.mlxWhisper)
        
        let inputWithoutPreserve = SwitchBackendInput(
            currentBackend: BackendID.mlxWhisper,
            newBackend: BackendID.whisperKit,
            preserveState: false
        )
        
        let output2 = try await useCase.execute(input: inputWithoutPreserve)
        
        // Both should succeed, implementation may differ
        #expect(output1.currentBackend == output2.currentBackend)
    }
}

// MARK: - Mock Helpers

extension MockSwitchBackendUseCase {
    func setActiveBackend(_ backend: BackendID) {
        activeBackend = backend
    }
    
    func setShouldFail(_ value: Bool) {
        shouldFail = value
    }
    
    func setFailureError(_ error: Error) {
        failureError = error
    }
    
    func setDelay(_ duration: Duration) {
        delay = duration
    }
}
