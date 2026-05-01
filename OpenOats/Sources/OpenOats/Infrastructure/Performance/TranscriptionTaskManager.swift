import Foundation
import os

// MARK: - H1 Implementation: Non-Blocking Transcription Task Manager
//
// This actor implements non-blocking transcription that ensures the VAD loop
// never blocks on transcription operations.
//
// Key Design Points:
// - Transcriptions are fired in child Tasks that don't block the caller
// - Results are collected asynchronously via an AsyncStream
// - Queue is bounded to prevent memory growth
// - Cancellation is cooperative and fast

/// Actor that manages transcription tasks without blocking the VAD loop
public actor TranscriptionTaskManager: NonBlockingTranscriptionProtocol {
    
    // MARK: - Configuration
    
    /// Maximum time VAD loop can block (target: < 10ms)
    public static let maxVADLatency: Duration = .milliseconds(10)
    
    /// Maximum number of pending transcription tasks
    private static let maxQueueDepth = 10
    
    /// Maximum time to wait for a transcription before considering it failed
    private static let transcriptionTimeout: Duration = .seconds(30)
    
    // MARK: - State
    
    /// The transcription backend to use
    private let backend: any TranscriptionBackend
    
    /// Pending transcription tasks (bounded queue)
    private var pendingTasks: [TranscriptionTaskID: Task<TranscriptionResult, Error>] = [:]
    
    /// Completed results awaiting collection
    private var completedResults: [TranscriptionResult] = []
    
    /// Continuation for streaming results
    private var resultContinuation: AsyncStream<TranscriptionResult>.Continuation?
    
    /// Stream of transcription results
    private let resultStream: AsyncStream<TranscriptionResult>
    
    /// Logger for performance monitoring
    private let logger = Logger(subsystem: "com.openoats", category: "TranscriptionTaskManager")
    
    // MARK: - Initialization
    
    /// Initialize with a transcription backend
    public init(backend: any TranscriptionBackend) {
        self.backend = backend
        
        // Create the result stream
        var continuation: AsyncStream<TranscriptionResult>.Continuation?
        self.resultStream = AsyncStream { cont in
            continuation = cont
        }
        self.resultContinuation = continuation
    }
    
    // MARK: - NonBlockingTranscriptionProtocol Implementation
    
    /// Enqueue transcription without blocking the VAD loop
    /// 
    /// This method returns immediately with a task ID. The transcription
    /// runs in a child Task and results are delivered via the result stream.
    /// 
    /// - Parameters:
    ///   - samples: Audio samples to transcribe
    ///   - locale: Locale for transcription
    ///   - previousContext: Previous transcription context for continuity
    /// - Returns: Task ID for tracking this transcription
    public func enqueueTranscription(
        samples: [Float],
        locale: Locale,
        previousContext: String?
    ) async -> TranscriptionTaskID {
        let taskID = TranscriptionTaskID()
        
        // Check queue depth and remove oldest if needed
        if pendingTasks.count >= Self.maxQueueDepth {
            // Cancel and remove oldest task
            let oldestID = pendingTasks.keys.sorted { id1, id2 in
                // UUIDs are time-based, so earlier UUIDs are older
                id1.uuid.uuidString < id2.uuid.uuidString
            }.first
            
            if let oldestID = oldestID {
                pendingTasks[oldestID]?.cancel()
                pendingTasks.removeValue(forKey: oldestID)
                logger.warning("Queue full, cancelled oldest task \(oldestID.uuid)")
            }
        }
        
        // Create child task for transcription (non-blocking)
        let task = Task { [weak self] in
            let startTime = ContinuousClock().now
            
            do {
                // Check cancellation before starting
                try Task.checkCancellation()
                
                // Perform transcription with timeout
                let text = try await self?.performTranscriptionWithTimeout(
                    samples: samples,
                    locale: locale,
                    previousContext: previousContext
                ) ?? ""
                
                let duration = startTime.duration(to: ContinuousClock().now)
                
                return TranscriptionResult(
                    taskID: taskID,
                    text: text,
                    duration: duration,
                    success: true
                )
            } catch {
                let duration = startTime.duration(to: ContinuousClock().now)
                
                return TranscriptionResult(
                    taskID: taskID,
                    text: "",
                    duration: duration,
                    success: false,
                    error: error
                )
            }
        }
        
        // Store the task
        pendingTasks[taskID] = task
        
        // Start result collection task (non-blocking)
        Task {
            await collectTaskResult(taskID: taskID, task: task)
        }
        
        return taskID
    }
    
    /// Cancel a specific transcription task
    public func cancelTranscription(_ taskID: TranscriptionTaskID) async {
        if let task = pendingTasks.removeValue(forKey: taskID) {
            task.cancel()
            logger.debug("Cancelled transcription task \(taskID.uuid)")
        }
    }
    
    /// Get results for completed transcriptions
    public func collectResults() async -> [TranscriptionResult] {
        let results = completedResults
        completedResults.removeAll()
        return results
    }
    
    /// Current number of pending transcription tasks
    public var pendingCount: Int {
        pendingTasks.count
    }
    
    /// Cancel all pending transcription tasks
    public func cancelAll() async {
        logger.info("Cancelling all \(pendingTasks.count) pending transcription tasks")
        
        // Cancel all pending tasks
        for (_, task) in pendingTasks {
            task.cancel()
        }
        
        // Wait for all to complete
        for (_, task) in pendingTasks {
            _ = try? await task.value
        }
        
        pendingTasks.removeAll()
        completedResults.removeAll()
    }
    
    // MARK: - Private Methods
    
    /// Perform transcription with timeout
    private func performTranscriptionWithTimeout(
        samples: [Float],
        locale: Locale,
        previousContext: String?
    ) async throws -> String {
        try await withTimeout(Self.transcriptionTimeout) {
            try await self.backend.transcribe(
                samples,
                locale: locale,
                previousContext: previousContext
            )
        }
    }
    
    /// Collect result from a transcription task
    private func collectTaskResult(
        taskID: TranscriptionTaskID,
        task: Task<TranscriptionResult, Error>
    ) async {
        do {
            let result = try await task.value
            
            // Remove from pending
            pendingTasks.removeValue(forKey: taskID)
            
            // Store completed result
            completedResults.append(result)
            
            // Yield to stream
            resultContinuation?.yield(result)
            
            logger.debug("Transcription task \(taskID.uuid) completed in \(result.duration)")
            
        } catch is CancellationError {
            // Task was cancelled, clean up
            pendingTasks.removeValue(forKey: taskID)
            logger.debug("Transcription task \(taskID.uuid) was cancelled")
            
        } catch {
            // Task failed
            pendingTasks.removeValue(forKey: taskID)
            
            let failedResult = TranscriptionResult(
                taskID: taskID,
                text: "",
                duration: .zero,
                success: false,
                error: error
            )
            
            completedResults.append(failedResult)
            resultContinuation?.yield(failedResult)
            
            logger.error("Transcription task \(taskID.uuid) failed: \(error)")
        }
    }
    
    /// Helper: Execute with timeout
    private func withTimeout<T>(
        _ timeout: Duration,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            // Add the operation task
            group.addTask {
                try await operation()
            }
            
            // Add timeout task
            group.addTask {
                try await Task.sleep(for: timeout)
                throw TimeoutError()
            }
            
            // Return first result
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}

// MARK: - Supporting Types

/// Error thrown when transcription times out
private struct TimeoutError: Error {}

// MARK: - StreamingTranscriber Integration

/// Integration helper for StreamingTranscriber to use non-blocking transcription
public actor NonBlockingStreamingTranscriber {
    private let taskManager: TranscriptionTaskManager
    private let locale: Locale
    private var previousContext: String?
    private var onResult: (@Sendable (String, Bool) -> Void)?
    
    public init(
        backend: any TranscriptionBackend,
        locale: Locale,
        onResult: @escaping @Sendable (String, Bool) -> Void
    ) {
        self.taskManager = TranscriptionTaskManager(backend: backend)
        self.locale = locale
        self.onResult = onResult
    }
    
    /// Start the result collection loop
    public func startResultCollection() {
        Task {
            for await result in await taskManager.resultStream {
                handleResult(result)
            }
        }
    }
    
    /// Enqueue a transcription segment (non-blocking)
    public func enqueueTranscription(samples: [Float], isPartial: Bool = false) async {
        let taskID = await taskManager.enqueueTranscription(
            samples: samples,
            locale: locale,
            previousContext: previousContext
        )
        
        // Update context only for final results
        if !isPartial {
            // Context will be updated when result comes in
        }
    }
    
    /// Stop and cancel all transcriptions
    public func stop() async {
        await taskManager.cancelAll()
    }
    
    private func handleResult(_ result: TranscriptionResult) {
        if result.success {
            // Update context for next transcription
            let words = result.text.split(separator: " ")
            previousContext = words.suffix(5).joined(separator: " ")
            
            // Notify result handler
            onResult?(result.text, false)
        }
    }
}
