// MARK: - Swift 6 Concurrency Verification Test
// This file verifies that FluidVadManager and SyncDouble are properly Sendable

import Foundation

// MARK: - Sendable Conformance Verification

// Verify FluidVadManager is Sendable (implicit via actor)
func verifyFluidVadManagerSendable() {
    let _: any Sendable.Type = FluidVadManager.self
}

// Verify SyncDouble is Sendable (implicit via actor)
func verifySyncDoubleSendable() {
    let _: any Sendable.Type = SyncDouble.self
}

// MARK: - Cross-Isolation Boundary Test

// Test that actors can be passed across isolation boundaries
@MainActor
func testCrossIsolationBoundary() async {
    let vadManager: any VadManager = await FluidVadManager()
    let counter = SyncDouble()
    
    // Use across isolation boundary
    await counter.add(1.0)
    let _ = await counter.value
    
    let _ = await vadManager.makeStreamState()
}

// MARK: - Usage Pattern Verification

/// Verifies the usage patterns documented in the requirements
func verifyUsagePatterns() async {
    // FluidVadManager usage
    let vad = FluidVadManager()
    
    // Configuration access
    let config = await vad.getConfiguration()
    let _: Double = config.sampleRate
    let _: Float = config.threshold
    
    // Statistics
    let stats = await vad.getStatistics()
    let _: Int64 = stats.totalProcessedSamples
    let _: Double = stats.totalProcessedSeconds
    
    // Reset
    await vad.reset()
    
    // SyncDouble usage
    let counter = SyncDouble()
    
    // Arithmetic operations
    await counter.add(1.5)
    await counter.subtract(0.5)
    await counter.multiply(by: 2.0)
    await counter.divide(by: 2.0)
    
    // Value access
    let _: Double = await counter.value
    let _: Double = counter.cached  // Nonisolated access
    
    // Statistics
    let counterStats = counter.statistics()
    let _: UInt64 = counterStats.operationCount
}

// MARK: - VadManager Protocol Conformance

/// Verifies FluidVadManager properly implements VadManager
func verifyVadManagerConformance() async throws {
    let vad: any VadManager = await FluidVadManager()
    
    // Protocol methods
    let state = await vad.makeStreamState()
    
    let samples: [Float] = [0.1, 0.2, 0.3, 0.4, 0.5]
    let config = VadConfig.default
    
    let result = try await vad.processStreamingChunk(
        samples,
        state: state,
        config: config,
        returnSeconds: true,
        timeResolution: 1
    )
    
    // Verify result components
    let _: VadStreamState = result.state
    let _: VadEvent? = result.event
    let _: Double? = result.seconds
}

// MARK: - Nonisolated Access Verification

/// Verifies nonisolated access works correctly for SyncDouble
func verifyNonisolatedAccess() async {
    let counter = SyncDouble(100.0)
    
    // Nonisolated read (should not require await)
    let cachedValue: Double = counter.cached
    assert(cachedValue == 100.0, "Initial cached value should be 100.0")
    
    // Actor-isolated write
    await counter.add(50.0)
    
    // Nonisolated read after write
    let updatedValue: Double = counter.cached
    assert(updatedValue == 150.0, "Cached value should be updated to 150.0")
}

// MARK: - Swift 6 Strict Concurrency Verification

#if swift(>=6.0)
/// Verifies Swift 6 strict concurrency compliance
@MainActor
func verifySwift6Compliance() async {
    // Actors are implicitly Sendable
    let sendableActors: [any Sendable] = [
        await FluidVadManager(),
        SyncDouble()
    ]
    
    // Can pass across isolation boundaries
    await Task {
        for item in sendableActors {
            _ = item
        }
    }.value
}
#endif

// MARK: - Notes

/*
This test file verifies:
1. FluidVadManager is properly declared as an actor conforming to VadManager
2. SyncDouble is properly declared as an actor with nonisolated cached value
3. Both actors are implicitly Sendable
4. Cross-isolation boundary passing works correctly
5. All protocol requirements are met
6. Swift 6 strict concurrency is satisfied

To compile and verify:
    swiftc -swift-version 6 SendableVerification.swift

Expected: No errors related to Sendable conformance or actor isolation
*/
