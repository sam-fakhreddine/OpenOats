# ADR-004: Async-Safe Locking Migration (NSLock → Actor/Mutex)

## Status

Proposed (Pending wfc-pm Gate Decision)

## Context

The codebase currently uses `NSLock` and `NSRecursiveLock` for synchronization in several critical paths:

```swift
// Current pattern (NOT Sendable, causes Swift 6 errors)
class AudioBuffer {
    private let lock = NSLock()
    private var data: [Float] = []
    
    func append(_ samples: [Float]) {
        lock.lock()
        defer { lock.unlock() }
        data.append(contentsOf: samples)
    }
}
```

Swift 6 errors:
- `Expression is 'async' but is not marked with 'await'`
- `NSLock is not Sendable`
- `Capture of non-Sendable type in async context`

Files affected:
- `StreamingTranscriptionSegmentQueue.swift`
- `CircularAudioBuffer.swift` (if exists)
- `AudioEngine.swift` state management
- Various audio processing components

Total: 250 async-locking errors

## Decision

We will migrate from NSLock to **actor-based isolation** as the primary strategy, with `Mutex` as secondary for specific performance-critical scenarios.

### Strategy 1: Actor-Based Isolation (Primary)

Convert lock-protected classes to actors:

```swift
// After migration: Actor-based isolation (Sendable by default)
actor AudioBuffer {
    private var data: [Float] = []
    
    func append(_ samples: [Float]) {
        // Actor isolation provides automatic serialization
        data.append(contentsOf: samples)
    }
    
    func read() -> [Float] {
        return data
    }
}

// Usage with async/await
let buffer = AudioBuffer()
await buffer.append(samples)
let currentData = await buffer.read()
```

**When to use**: Default choice for all new and migrated code.

### Strategy 2: Mutex from Swift 6 Standard Library (Secondary)

For performance-critical paths where actor overhead is unacceptable:

```swift
import Synchronization  // Swift 6.1+

struct ThreadSafeCounter: ~Copyable {
    private let mutex = Mutex(0)
    
    func increment() {
        mutex.withLock { value in
            value += 1
        }
    }
}
```

**When to use**: 
- Hot paths with <1μs critical sections
- High-contention scenarios with millions of operations/second
- When profiling shows actor context switch overhead is significant

### Strategy 3: Nonisolated + Immutable Data (For Pure Computations)

For operations that don't need mutable state:

```swift
actor AudioProcessor {
    private var state: ProcessingState
    
    // Nonisolated for pure computations
    nonisolated func computeFFT(_ samples: [Float]) -> [Float] {
        // Pure function, no actor state access
        return vDSP_fft(samples)
    }
    
    // Actor-isolated for state mutation
    func process(_ samples: [Float]) async {
        let result = computeFFT(samples)  // Nonisolated, no await
        await updateState(result)          // Actor-isolated, requires await
    }
}
```

## Migration Patterns

### Pattern 1: Simple Lock Replacement

```swift
// Before
class SimpleBuffer {
    private let lock = NSLock()
    private var data: [Float] = []
}

// After
actor SimpleBuffer {
    private var data: [Float] = []
}
```

### Pattern 2: Lock with Multiple Properties

```swift
// Before
class TranscriptionState {
    private let lock = NSRecursiveLock()
    private var isRecording = false
    private var activeSession: Session?
    private var buffer: [Float] = []
}

// After
actor TranscriptionState {
    private var isRecording = false
    private var activeSession: Session?
    private var buffer: [Float] = []
    
    // INVARIANT: isRecording implies activeSession != nil
    var canTranscribe: Bool {
        isRecording && activeSession != nil
    }
}
```

### Pattern 3: Lock with Condition Variable (Complex)

```swift
// Before
class WaitableQueue {
    private let lock = NSLock()
    private let condition = NSCondition()
    private var items: [Item] = []
    
    func waitForItem() -> Item {
        lock.lock()
        while items.isEmpty {
            condition.wait()
        }
        let item = items.removeFirst()
        lock.unlock()
        return item
    }
}

// After: Use AsyncStream or Continuation
actor WaitableQueue {
    private var items: [Item] = []
    private var waiters: [CheckedContinuation<Item, Never>] = []
    
    func enqueue(_ item: Item) {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume(returning: item)
        } else {
            items.append(item)
        }
    }
    
    func dequeue() async -> Item {
        if let item = items.first {
            items.removeFirst()
            return item
        }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}
```

## Consequences

### Positive

- Automatic Sendable conformance for actor-based types
- Compiler-verified data race safety
- Structured concurrency integration
- Cleaner code without manual lock/unlock
- No risk of forgetting to unlock (defer not needed)

### Negative

- Actor isolation requires `await` for all access
- Potential context switch overhead
- Cannot use synchronous APIs that expect immediate results
- May require restructuring of existing code

### Performance Considerations

| Scenario | NSLock | Actor | Mutex | Recommendation |
|----------|--------|-------|-------|----------------|
| Simple counter | ~20ns | ~100ns | ~25ns | Actor (clarity wins) |
| Audio buffer (20ms chunks) | ~50ns | ~150ns | ~60ns | Actor (acceptable overhead) |
| High-frequency state (1M+ ops/sec) | ~20ns | ~100ns | ~25ns | Mutex if profiled bottleneck |

**Rule**: Start with actor, optimize to Mutex only if profiling shows it's a bottleneck.

## Specific Decisions

### CircularAudioBuffer (TASK-SW6-011)

Decision: Convert to actor with pre-allocated capacity

```swift
actor CircularAudioBuffer {
    private let capacity: Int
    private var buffer: [Float]  // Pre-allocated
    private var head: Int = 0
    private var tail: Int = 0
    private var count: Int = 0
    
    // INVARIANT: count <= capacity
    // INVARIANT: head, tail in 0..<capacity
}
```

Rationale: Audio buffers are accessed every 20ms, actor overhead is negligible compared to processing time.

### StreamingTranscriptionSegmentQueue (TASK-SW6-010)

Decision: Convert to actor with continuation-based waiting

Rationale: Queue operations are async by nature, actor model fits well.

### AudioEngine State (TASK-SW6-012)

Decision: Actor-based state management

Rationale: State changes are infrequent relative to audio processing, actor isolation provides safety without significant overhead.

## Verification

### Build Verification

```bash
# After migration, verify zero NSLock usage in async contexts
grep -r "NSLock\|NSRecursiveLock" --include="*.swift" OpenOats/Sources/
# Expected: Empty or only in legacy wrappers with SAFETY comments
```

### Performance Verification (TASK-SW6-018)

Benchmark before/after:
- Audio buffer processing latency (target: <20ms)
- Context switch overhead
- CPU usage during transcription

Acceptance: <5% regression vs pre-migration baseline

## Alternatives Considered

### Alternative 1: Wrap NSLock in @unchecked Sendable

```swift
struct SendableLock: @unchecked Sendable {
    private let lock = NSLock()
    // SAFETY: Lock is private, only accessed through methods
}
```

**Rejected**: Bypasses Swift 6 safety, doesn't solve async/await integration issues

### Alternative 2: Use os_unfair_lock

```swift
import os.lock

class FastLock {
    private let lock = os_unfair_lock_t.allocate(capacity: 1)
    // ... wrapper methods
}
```

**Rejected**: Still requires manual management, not Sendable, doesn't integrate with async/await

### Alternative 3: Global Actor (@MainActor, custom)

```swift
@CustomAudioActor
class AudioBuffer {
    private var data: [Float] = []
}
```

**Partially Accepted**: Custom global actors may be used for specific subsystems, but general actors preferred for flexibility

## References

- [SE-0302: Sendable](https://github.com/apple/swift-evolution/blob/main/proposals/0302-concurrent-value-and-concurrent-closures.md)
- [Swift Actor Documentation](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/#Actors)
- [MLX Audio Processing Best Practices](https://ml-explore.github.io/mlx-swift/)
- OpenOats AGENTS.md - Memory Safety section
- PROPERTIES.md - SAFETY-003, INVARIANT-001
- TASKS.md - TASK-SW6-010, TASK-SW6-011, TASK-SW6-012

---
*Decision Record ID: ADR-004*  
*Epic: Swift 6 Strict Concurrency Compliance*  
*Date: 2026-05-02*
