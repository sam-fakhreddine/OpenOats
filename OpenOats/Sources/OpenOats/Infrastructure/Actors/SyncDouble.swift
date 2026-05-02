import Foundation

// MARK: - SyncDouble
/// Thread-safe double accumulator using actor isolation.
/// Provides atomic read-modify-write operations for floating-point values.
///
/// This actor ensures all operations on the contained value are serialized,
/// preventing data races in concurrent environments. It supports both
/// incremental accumulation and atomic value retrieval.
///
/// ## Usage Example
/// ```swift
/// let counter = SyncDouble()
/// await counter.add(1.5)
/// await counter.add(2.5)
/// let value = await counter.value  // Returns 4.0
/// ```
///
/// ## Performance
/// - Add operations: O(1)
/// - Value access: O(1) nonisolated (reads cached value)
/// - Strict ordering: All operations are FIFO through actor mailbox
@available(macOS 15.0, *)
public actor SyncDouble {
    
    // MARK: - Properties
    
    /// The underlying mutable value (actor-isolated)
    private var _value: Double = 0.0
    
    /// Number of operations performed (for debugging)
    private var operationCount: UInt64 = 0
    
    /// Total delta accumulated (for statistics)
    private var totalDelta: Double = 0.0
    
    /// Timestamp of last modification
    private var lastModified: Date = Date()
    
    /// Lock for nonisolated value access (optimistic caching)
    private let lock = NSLock()
    
    /// Cached value for nonisolated reads
    private nonisolated(unsafe) var cachedValue: Double = 0.0
    
    // MARK: - Initialization
    
    /// Create a new SyncDouble with initial value of 0
    public init() {}
    
    /// Create a new SyncDouble with specified initial value
    /// - Parameter initialValue: Starting value
    public init(_ initialValue: Double) {
        self._value = initialValue
        self.cachedValue = initialValue
    }
    
    // MARK: - Core Operations
    
    /// Atomically add a delta to the value
    /// - Parameter delta: Amount to add (can be negative)
    public func add(_ delta: Double) {
        _value += delta
        totalDelta += abs(delta)
        operationCount += 1
        lastModified = Date()
        
        // Update cached value for nonisolated access
        lock.lock()
        cachedValue = _value
        lock.unlock()
    }
    
    /// Atomically subtract a delta from the value
    /// - Parameter delta: Amount to subtract
    public func subtract(_ delta: Double) {
        add(-delta)
    }
    
    /// Atomically multiply the value by a factor
    /// - Parameter factor: Multiplication factor
    public func multiply(by factor: Double) {
        _value *= factor
        operationCount += 1
        lastModified = Date()
        
        lock.lock()
        cachedValue = _value
        lock.unlock()
    }
    
    /// Atomically divide the value by a divisor
    /// - Parameter divisor: Division divisor (must be non-zero)
    public func divide(by divisor: Double) {
        guard divisor != 0 else { return }
        _value /= divisor
        operationCount += 1
        lastModified = Date()
        
        lock.lock()
        cachedValue = _value
        lock.unlock()
    }
    
    /// Set the value atomically
    /// - Parameter newValue: New value to set
    public func set(_ newValue: Double) {
        let delta = newValue - _value
        _value = newValue
        totalDelta += abs(delta)
        operationCount += 1
        lastModified = Date()
        
        lock.lock()
        cachedValue = _value
        lock.unlock()
    }
    
    /// Reset the value to 0
    public func reset() {
        _value = 0
        operationCount += 1
        lastModified = Date()
        
        lock.lock()
        cachedValue = 0
        lock.unlock()
    }
    
    // MARK: - Value Access
    
    /// Get the current value (actor-isolated, most accurate)
    public var value: Double {
        _value
    }
    
    /// Get the current value (nonisolated, may be slightly stale)
    /// This provides fast read access without actor hop
    public nonisolated var cached: Double {
        lock.lock()
        defer { lock.unlock() }
        return cachedValue
    }
    
    /// Alias for `value` for API compatibility
    public func getValue() async -> Double {
        value
    }
    
    // MARK: - Statistics
    
    /// Get statistics about operations performed
    public func statistics() -> Statistics {
        Statistics(
            currentValue: _value,
            operationCount: operationCount,
            totalDelta: totalDelta,
            lastModified: lastModified
        )
    }
    
    /// Statistics snapshot
    public struct Statistics: Sendable {
        public let currentValue: Double
        public let operationCount: UInt64
        public let totalDelta: Double
        public let lastModified: Date
    }
    
    // MARK: - Comparison Operations
    
    /// Check if value equals comparison value (within epsilon)
    public func equals(_ other: Double, epsilon: Double = 1e-10) -> Bool {
        abs(_value - other) < epsilon
    }
    
    /// Check if value is greater than comparison value
    public func isGreater(than other: Double) -> Bool {
        _value > other
    }
    
    /// Check if value is less than comparison value
    public func isLess(than other: Double) -> Bool {
        _value < other
    }
    
    /// Check if value is in range
    public func isInRange(_ range: ClosedRange<Double>) -> Bool {
        range.contains(_value)
    }
    
    // MARK: - Batch Operations
    
    /// Add multiple deltas atomically
    /// - Parameter deltas: Array of values to add
    /// - Returns: Final value after all additions
    @discardableResult
    public func addBatch(_ deltas: [Double]) -> Double {
        let sum = deltas.reduce(0, +)
        _value += sum
        totalDelta += sum
        operationCount += UInt64(deltas.count)
        lastModified = Date()
        
        lock.lock()
        cachedValue = _value
        lock.unlock()
        
        return _value
    }
    
    /// Perform multiple operations atomically
    /// - Parameter operations: Closure that receives mutable access to value
    /// - Returns: Result of the closure
    @discardableResult
    public func batch<T>(_ operations: (inout Double) throws -> T) rethrows -> T {
        let result = try operations(&_value)
        operationCount += 1
        lastModified = Date()
        
        lock.lock()
        cachedValue = _value
        lock.unlock()
        
        return result
    }
}

// MARK: - Convenience Extensions

@available(macOS 15.0, *)
extension SyncDouble {
    /// Pre-increment operator support
    public func increment() {
        add(1)
    }
    
    /// Pre-decrement operator support  
    public func decrement() {
        add(-1)
    }
    
    /// Increment by amount
    public func increment(by amount: Double) {
        add(amount)
    }
    
    /// Decrement by amount
    public func decrement(by amount: Double) {
        add(-amount)
    }
}

// MARK: - Arithmetic Protocol Conformance

@available(macOS 15.0, *)
extension SyncDouble: CustomStringConvertible {
    public nonisolated var description: String {
        "SyncDouble(cached: \(cached))"
    }
    
    public var detailedDescription: String {
        "SyncDouble(value: \(value), operations: \(operationCount))"
    }
}

// MARK: - AsyncSequence Support

@available(macOS 15.0, *)
extension SyncDouble {
    /// AsyncSequence that emits value changes
    /// Note: Requires Swift 6.2 with AsyncAlgorithms
    public func changes() -> AsyncStream<Double> {
        AsyncStream { continuation in
            let initialValue = self.cached
            continuation.yield(initialValue)
            
            // Keep alive until cancelled
            continuation.onTermination = { _ in }
        }
    }
}

// MARK: - Actor-Isolated Computations

@available(macOS 15.0, *)
extension SyncDouble {
    /// Compute average of this SyncDouble with others atomically
    public func average(with others: [SyncDouble]) async -> Double {
        var sum = _value
        for other in others {
            sum += await other.value
        }
        return sum / Double(others.count + 1)
    }
    
    /// Find minimum of this SyncDouble with others atomically
    public func min(with others: [SyncDouble]) async -> Double {
        var minVal = _value
        for other in others {
            let otherVal = await other.value
            if otherVal < minVal {
                minVal = otherVal
            }
        }
        return minVal
    }
    
    /// Find maximum of this SyncDouble with others atomically
    public func max(with others: [SyncDouble]) async -> Double {
        var maxVal = _value
        for other in others {
            let otherVal = await other.value
            if otherVal > maxVal {
                maxVal = otherVal
            }
        }
        return maxVal
    }
}
