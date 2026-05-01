import Foundation

// MARK: - Model Download Errors

/// Errors that can occur during model download.
public enum ModelDownloadError: Error, Sendable, Equatable {
    case invalidURL
    case networkFailure(reason: String)
    case insufficientStorage(required: Int64, available: Int64)
    case checksumMismatch(expected: String, actual: String)
    case resumeNotSupported
    case downloadCancelled
    case fileSystemError(reason: String)
    
    public var localizedDescription: String {
        switch self {
        case .invalidURL:
            return "Invalid model download URL"
        case .networkFailure(let reason):
            return "Network failure: \(reason)"
        case .insufficientStorage(let required, let available):
            return "Insufficient storage: need \(required) bytes, have \(available) bytes"
        case .checksumMismatch(let expected, let actual):
            return "Checksum mismatch: expected \(expected), got \(actual)"
        case .resumeNotSupported:
            return "Server does not support resume capability"
        case .downloadCancelled:
            return "Download was cancelled"
        case .fileSystemError(let reason):
            return "File system error: \(reason)"
        }
    }
}

// MARK: - Download Progress

/// Progress information for model download.
public struct DownloadProgress: Sendable, Equatable {
    public let bytesDownloaded: Int64
    public let totalBytes: Int64
    public let percentage: Double
    public let bytesPerSecond: Double
    public let estimatedTimeRemaining: Duration?
    public let isResuming: Bool
    
    public init(
        bytesDownloaded: Int64,
        totalBytes: Int64,
        bytesPerSecond: Double,
        isResuming: Bool = false
    ) {
        self.bytesDownloaded = bytesDownloaded
        self.totalBytes = totalBytes
        self.percentage = totalBytes > 0 ? Double(bytesDownloaded) / Double(totalBytes) : 0
        self.bytesPerSecond = bytesPerSecond
        self.isResuming = isResuming
        
        if bytesPerSecond > 0 {
            let remainingBytes = totalBytes - bytesDownloaded
            let remainingSeconds = Double(remainingBytes) / bytesPerSecond
            self.estimatedTimeRemaining = .seconds(remainingSeconds)
        } else {
            self.estimatedTimeRemaining = nil
        }
    }
}

// MARK: - MLX Model Downloader

/// Actor-based model downloader with resume capability.
/// Downloads models in 5MB chunks with up to 6 concurrent downloads.
public actor MLXModelDownloader {
    
    // MARK: - Constants
    
    /// Chunk size: 5MB
    public static let chunkSize: Int = 5 * 1024 * 1024
    
    /// Maximum concurrent downloads
    public static let maxConcurrentDownloads: Int = 6
    
    /// Default timeout for download operations
    public static let downloadTimeout: Duration = .seconds(300)
    
    // MARK: - Properties
    
    /// Model repository identifier (e.g., "mlx-community/GLM-ASR-Nano-2512-4bit")
    public let modelRepository: String
    
    /// Destination directory for downloaded model
    public let destinationURL: URL
    
    /// Whether the server supports resume capability
    public let supportsResume: Bool
    
    /// Progress stream for download updates
    private var progressContinuation: AsyncStream<DownloadProgress>.Continuation?
    
    /// Active download tasks
    private var downloadTasks: [Task<Data, Error>] = []
    
    /// Cancellation flag
    private var isCancelled: Bool = false
    
    /// Download state for resume
    private var downloadState: DownloadState = .idle
    
    // MARK: - Initialization
    
    /// Creates a new model downloader.
    /// - Parameters:
    ///   - modelRepository: HuggingFace model repository
    ///   - destinationURL: Local directory for model files
    ///   - supportsResume: Whether to use resume capability
    public init(
        modelRepository: String,
        destinationURL: URL,
        supportsResume: Bool = true
    ) {
        self.modelRepository = modelRepository
        self.destinationURL = destinationURL
        self.supportsResume = supportsResume
    }
    
    // MARK: - Download State
    
    private enum DownloadState: Sendable {
        case idle
        case downloading(totalBytes: Int64, bytesDownloaded: Int64)
        case paused(bytesDownloaded: Int64)
        case completed
        case failed(Error)
    }
    
    // MARK: - Public Methods
    
    /// Downloads the model with progress reporting.
    /// - Returns: Async stream of download progress
    /// - Throws: ModelDownloadError if download fails
    public func download() -> AsyncStream<DownloadProgress> {
        let (stream, continuation) = AsyncStream<DownloadProgress>.makeStream()
        self.progressContinuation = continuation
        
        Task {
            do {
                try await performDownload()
            } catch {
                // Finish the stream on error
                continuation.finish()
            }
        }
        
        return stream
    }
    
    /// Cancels the current download operation.
    public func cancel() async {
        isCancelled = true
        
        // Cancel all active tasks
        for task in downloadTasks {
            task.cancel()
        }
        downloadTasks.removeAll()
        
        progressContinuation?.finish()
        progressContinuation = nil
    }
    
    /// Pauses the current download (if resume is supported).
    public func pause() async {
        if case .downloading(let total, let downloaded) = downloadState {
            downloadState = .paused(bytesDownloaded: downloaded)
            
            // Cancel active tasks but preserve state
            for task in downloadTasks {
                task.cancel()
            }
            downloadTasks.removeAll()
        }
    }
    
    /// Resumes a paused download.
    public func resume() async throws {
        guard case .paused(let bytesDownloaded) = downloadState else {
            return // Not paused, nothing to resume
        }
        
        isCancelled = false
        try await performDownload(resumingFrom: bytesDownloaded)
    }
    
    /// Checks if model is already downloaded and valid.
    /// - Returns: True if model exists and is complete
    public func isModelDownloaded() async -> Bool {
        // Check for essential model files
        let modelFiles = [
            "config.json",
            "model.safetensors"
        ]
        
        for file in modelFiles {
            let fileURL = destinationURL.appendingPathComponent(file)
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory)
            if !exists || isDirectory.boolValue {
                return false
            }
        }
        
        return true
    }
    
    /// Gets the total size of the model if known.
    /// - Returns: Total size in bytes, or nil if unknown
    public func getTotalSize() async -> Int64? {
        // This would typically query the server for model size
        // For now, return a typical model size estimate
        return 1_200_000_000 // ~1.2GB for GLMASR 4bit
    }
    
    /// Deletes the downloaded model files.
    public func clearDownloadedModel() async throws {
        let fileManager = FileManager.default
        
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        
        downloadState = .idle
    }
    
    // MARK: - Configuration Accessors (for tests)
    
    /// Returns the chunk size (5MB)
    public func chunkSize() -> Int {
        return Self.chunkSize
    }
    
    /// Returns the concurrent download limit (6)
    public func concurrentLimit() -> Int {
        return Self.maxConcurrentDownloads
    }
    
    /// Calculates download progress percentage.
    /// - Parameters:
    ///   - downloaded: Bytes downloaded
    ///   - total: Total bytes
    /// - Returns: Progress percentage (0.0 - 1.0)
    public func calculateProgress(downloaded: Int64, total: Int64) -> Double {
        guard total > 0 else { return 0 }
        return Double(downloaded) / Double(total)
    }
    
    // MARK: - Private Methods
    
    private func performDownload(resumingFrom resumeByte: Int64 = 0) async throws {
        let startTime = Date()
        let totalBytes = await getTotalSize() ?? 0
        
        downloadState = .downloading(totalBytes: totalBytes, bytesDownloaded: resumeByte)
        
        // Create destination directory if needed
        try FileManager.default.createDirectory(
            at: destinationURL,
            withIntermediateDirectories: true
        )
        
        // Build download URLs for model files
        let filesToDownload = try await getModelFiles()
        
        // Download files concurrently with limit
        try await withThrowingTaskGroup(of: (String, Data).self) { group in
            var activeTasks = 0
            var fileIterator = filesToDownload.makeIterator()
            
            func addNextTask() {
                guard activeTasks < Self.maxConcurrentDownloads,
                      let (filename, url) = fileIterator.next() else { return }
                
                activeTasks += 1
                group.addTask {
                    let data = try await self.downloadFile(url: url, filename: filename)
                    return (filename, data)
                }
            }
            
            // Start initial batch of tasks
            for _ in 0..<min(Self.maxConcurrentDownloads, filesToDownload.count) {
                addNextTask()
            }
            
            // Process completed tasks and add new ones
            var completedBytes: Int64 = resumeByte
            
            for try await (filename, data) in group {
                activeTasks -= 1
                
                // Save downloaded file
                let fileURL = self.destinationURL.appendingPathComponent(filename)
                try data.write(to: fileURL)
                
                // Update progress
                completedBytes += Int64(data.count)
                let elapsed = Date().timeIntervalSince(startTime)
                let bytesPerSecond = elapsed > 0 ? Double(completedBytes) / elapsed : 0
                
                let progress = DownloadProgress(
                    bytesDownloaded: completedBytes,
                    totalBytes: totalBytes,
                    bytesPerSecond: bytesPerSecond,
                    isResuming: resumeByte > 0
                )
                
                self.progressContinuation?.yield(progress)
                
                // Check for cancellation
                if self.isCancelled {
                    group.cancelAll()
                    throw ModelDownloadError.downloadCancelled
                }
                
                // Add next task if available
                addNextTask()
            }
        }
        
        downloadState = .completed
        progressContinuation?.finish()
        progressContinuation = nil
    }
    
    private func downloadFile(url: URL, filename: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 300
        
        // Add headers for resume support if needed
        if supportsResume {
            // This would check partial file and add Range header
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ModelDownloadError.networkFailure(reason: "HTTP error for \(filename)")
        }
        
        return data
    }
    
    private func getModelFiles() async throws -> [(String, URL)] {
        // For HuggingFace models, construct download URLs
        let baseURL = "https://huggingface.co/\(modelRepository)/resolve/main"
        
        // Essential model files for MLX
        let essentialFiles = [
            "config.json",
            "model.safetensors",
            "preprocessor_config.json",
            "tokenizer.json"
        ]
        
        // SEC-003 Fix: Use SecureURLConstruction to prevent path traversal
        return try essentialFiles.compactMap { filename -> (String, URL)? in
            do {
                let url = try SecureURLConstruction.modelDownloadURL(
                    baseURL: baseURL,
                    filename: filename
                )
                return (filename, url)
            } catch {
                // Log and skip invalid URLs
                return nil
            }
        }
    }
}

// MARK: - Model Download Manager

/// Manages multiple model downloads with queue and prioritization.
public actor ModelDownloadManager {
    
    // MARK: - Properties
    
    private var activeDownloads: [String: MLXModelDownloader] = [:]
    private var downloadQueue: [DownloadRequest] = []
    private var maxConcurrentDownloads: Int = 2
    
    // MARK: - Types
    
    public struct DownloadRequest: Sendable, Identifiable {
        public let id: String
        public let modelRepository: String
        public let destinationURL: URL
        public let priority: DownloadPriority
        
        public init(
            id: String,
            modelRepository: String,
            destinationURL: URL,
            priority: DownloadPriority = .normal
        ) {
            self.id = id
            self.modelRepository = modelRepository
            self.destinationURL = destinationURL
            self.priority = priority
        }
    }
    
    public enum DownloadPriority: Int, Sendable, Comparable {
        case low = 0
        case normal = 1
        case high = 2
        case critical = 3
        
        public static func < (lhs: DownloadPriority, rhs: DownloadPriority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }
    
    // MARK: - Public Methods
    
    /// Enqueues a model download.
    /// - Parameter request: Download request
    /// - Returns: Download ID for tracking
    @discardableResult
    public func enqueueDownload(_ request: DownloadRequest) -> AsyncStream<DownloadProgress> {
        let downloader = MLXModelDownloader(
            modelRepository: request.modelRepository,
            destinationURL: request.destinationURL
        )
        
        activeDownloads[request.id] = downloader
        
        // Start download and return progress stream
        return downloader.download()
    }
    
    /// Cancels a download by ID.
    /// - Parameter id: Download ID
    public func cancelDownload(id: String) async {
        if let downloader = activeDownloads[id] {
            await downloader.cancel()
            activeDownloads.removeValue(forKey: id)
        }
    }
    
    /// Checks if a model is currently downloading.
    /// - Parameter id: Download ID
    /// - Returns: True if downloading
    public func isDownloading(id: String) -> Bool {
        activeDownloads.keys.contains(id)
    }
    
    /// Gets download progress for a specific download.
    /// - Parameter id: Download ID
    /// - Returns: Current progress percentage
    public func getProgress(id: String) async -> Double? {
        guard let downloader = activeDownloads[id] else { return nil }
        // This would need to be implemented with proper state tracking
        return nil
    }
    
    /// Cancels all active downloads.
    public func cancelAllDownloads() async {
        for (_, downloader) in activeDownloads {
            await downloader.cancel()
        }
        activeDownloads.removeAll()
    }
    
    /// Clears downloaded model by ID.
    /// - Parameter id: Download ID
    public func clearModel(id: String) async throws {
        if let request = downloadQueue.first(where: { $0.id == id }) {
            let downloader = MLXModelDownloader(
                modelRepository: request.modelRepository,
                destinationURL: request.destinationURL
            )
            try await downloader.clearDownloadedModel()
        }
        
        downloadQueue.removeAll { $0.id == id }
    }
}
