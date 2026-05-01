import Foundation

// MARK: - Runtime Mode

/// Runtime mode for the DI container.
/// Determines which implementations of dependencies to use.
public enum DIContainerRuntimeMode: Sendable, Equatable {
    /// Live production mode with real dependencies.
    case live
    
    /// Test mode with mock dependencies.
    case test
    
    /// Preview mode for SwiftUI previews.
    case preview
}

// MARK: - App DI Container

/// Root composition container for dependency injection.
/// 
/// The DIContainer is the central point for wiring together all layers of the application:
/// - Business Layer (UseCases)
/// - Presentation Layer (ViewModels)
/// - Infrastructure Layer (Services, Repositories)
///
/// ## Usage
/// ```swift
/// // Create container for production
/// let container = DIContainer(mode: .live)
///
/// // Access factories
/// let serviceFactory = await container.serviceFactory
/// let useCaseFactory = await container.useCaseFactory
/// let viewModelFactory = container.viewModelFactory
///
/// // Create components
/// let startSessionUseCase = useCaseFactory.makeStartSessionUseCase()
/// let sessionViewModel = viewModelFactory.makeSessionViewModel()
/// ```
///
/// ## Features
/// - Lazy initialization: Services are created only when first accessed
/// - Sendable-safe: All factories are actors or Sendable structs
/// - Mock injection: Supports injecting mock factories for testing
/// - Swift 6.2 strict concurrency compliant
@available(macOS 15.0, *)
actor DIContainer {
    
    // MARK: - Properties
    
    /// The runtime mode of the container.
    let mode: DIContainerRuntimeMode
    
    // MARK: - Private Storage
    
    /// Injected service factory (for testing) or nil to use default.
    private var injectedServiceFactory: (any ServiceFactory)?
    
    /// Injected use case factory (for testing) or nil to use default.
    private var injectedUseCaseFactory: (any UseCaseFactory)?
    
    /// Injected view model factory (for testing) or nil to use default.
    @MainActor
    private var injectedViewModelFactory: (any ViewModelFactory)?
    
    /// Cached service factory instance.
    private var cachedServiceFactory: (any ServiceFactory)?
    
    /// Cached use case factory instance.
    private var cachedUseCaseFactory: (any UseCaseFactory)?
    
    /// Cached view model factory instance (accessed on MainActor).
    @MainActor
    private var cachedViewModelFactory: (any ViewModelFactory)?
    
    // MARK: - Initialization
    
    /// Creates a new DIContainer with the specified runtime mode.
    ///
    /// - Parameters:
    ///   - mode: The runtime mode (live, test, or preview).
    ///   - serviceFactory: Optional mock service factory for testing.
    ///   - useCaseFactory: Optional mock use case factory for testing.
    ///   - viewModelFactory: Optional mock view model factory for testing.
    init(
        mode: DIContainerRuntimeMode,
        serviceFactory: (any ServiceFactory)? = nil,
        useCaseFactory: (any UseCaseFactory)? = nil,
        viewModelFactory: (any ViewModelFactory)? = nil
    ) {
        self.mode = mode
        self.injectedServiceFactory = serviceFactory
        self.injectedUseCaseFactory = useCaseFactory
        
        // ViewModelFactory must be set on MainActor
        if let vmFactory = viewModelFactory {
            Task { @MainActor in
                self.cachedViewModelFactory = vmFactory
            }
        }
    }
    
    // MARK: - Factory Accessors (Lazy Initialization)
    
    /// The service factory for creating infrastructure services.
    /// Lazily initialized on first access.
    var serviceFactory: any ServiceFactory {
        get async {
            // Return injected factory if available
            if let injected = injectedServiceFactory {
                return injected
            }
            
            // Return cached factory if available
            if let cached = cachedServiceFactory {
                return cached
            }
            
            // Create appropriate factory based on mode
            let factory: any ServiceFactory
            switch mode {
            case .live:
                #if DEBUG
                // In debug builds, still use mock for development
                factory = MockServiceFactory()
                #else
                // TODO: Create real ServiceFactoryImpl when available
                factory = MockServiceFactory()
                #endif
            case .test, .preview:
                factory = MockServiceFactory()
            }
            
            cachedServiceFactory = factory
            return factory
        }
    }
    
    /// The use case factory for creating business logic use cases.
    /// Lazily initialized on first access.
    var useCaseFactory: any UseCaseFactory {
        get async {
            // Return injected factory if available
            if let injected = injectedUseCaseFactory {
                return injected
            }
            
            // Return cached factory if available
            if let cached = cachedUseCaseFactory {
                return cached
            }
            
            // Create factory with current service factory
            let serviceFactory = await self.serviceFactory
            let factory = UseCaseFactoryImpl(serviceFactory: serviceFactory)
            
            cachedUseCaseFactory = factory
            return factory
        }
    }
    
    /// The view model factory for creating presentation view models.
    /// Lazily initialized on first access. Must be accessed on MainActor.
    @MainActor
    var viewModelFactory: any ViewModelFactory {
        get {
            // Return injected factory if available
            if let injected = injectedViewModelFactory {
                return injected
            }
            
            // Return cached factory if available
            if let cached = cachedViewModelFactory {
                return cached
            }
            
            // Create factory - use the struct-based mock that conforms to Sendable
            let factory = DIContainerViewModelFactoryImpl()
            
            cachedViewModelFactory = factory
            return factory
        }
    }
    
    // MARK: - Lifecycle
    
    /// Resets all cached factory instances.
    /// This forces the container to recreate factories on next access.
    func reset() {
        cachedServiceFactory = nil
        cachedUseCaseFactory = nil
        Task { @MainActor in
            self.cachedViewModelFactory = nil
        }
    }
    
    /// Creates a new container configured for testing with mock dependencies.
    static func testContainer() -> DIContainer {
        DIContainer(mode: .test)
    }
    
    /// Creates a new container configured for production.
    static func liveContainer() -> DIContainer {
        DIContainer(mode: .live)
    }
    
    /// Creates a new container configured for SwiftUI previews.
    static func previewContainer() -> DIContainer {
        DIContainer(mode: .preview)
    }
}

// MARK: - ViewModel Factory Implementation for DIContainer

/// ViewModelFactory implementation that doesn't depend on external UseCaseFactory
/// to avoid isolation conflicts
@available(macOS 15.0, *)
@MainActor
struct DIContainerViewModelFactoryImpl: ViewModelFactory {
    func makeSessionViewModel() -> any SessionViewModel {
        return DefaultSessionViewModel()
    }
    
    func makeTranscriptViewModel() -> any TranscriptViewModel {
        return DefaultTranscriptViewModel()
    }
    
    func makeSettingsViewModel() -> any SettingsViewModel {
        return DefaultSettingsViewModel()
    }
    
    func makeIdleDashboardViewModel() -> any IdleDashboardViewModel {
        return DefaultIdleDashboardViewModel()
    }
    
    func makeBackendConfigurationViewModel() -> any BackendConfigurationViewModel {
        return DIContainerDefaultBackendConfigurationViewModel()
    }
}

// MARK: - Default Backend Configuration View Model

/// Default implementation of BackendConfigurationViewModel for DIContainer
@available(macOS 15.0, *)
@MainActor
@Observable
final class DIContainerDefaultBackendConfigurationViewModel: BackendConfigurationViewModel {
    let id: UUID
    
    var isLoading: Bool = false
    var error: PresentationError? = nil
    var backends: [BackendConfiguration] = []
    var selectedBackend: BackendID = .mlxWhisper
    
    init() {
        self.id = UUID()
        self.backends = [
            BackendConfiguration(
                id: .mlxWhisper,
                name: "MLX Whisper",
                description: "Fast local transcription using MLX",
                isLocal: true,
                requiresAPIKey: false,
                supportedLanguages: ["en", "es", "fr", "de", "it"],
                capabilities: [.streaming, .batch, .speakerDiarization]
            ),
            BackendConfiguration(
                id: .whisperKit,
                name: "WhisperKit",
                description: "Apple Silicon optimized Whisper",
                isLocal: true,
                requiresAPIKey: false,
                supportedLanguages: ["en", "es", "fr", "de", "it", "ja", "zh"],
                capabilities: [.streaming, .batch, .realTimeProcessing]
            ),
            BackendConfiguration(
                id: .assemblyAI,
                name: "AssemblyAI",
                description: "Cloud transcription with high accuracy",
                isLocal: false,
                requiresAPIKey: true,
                supportedLanguages: ["en"],
                capabilities: [.streaming, .batch, .speakerDiarization, .realTimeProcessing]
            )
        ]
    }
    
    func clearError() {
        error = nil
    }
    
    func testConnection(to backend: BackendID) async -> ConnectionTestResult {
        isLoading = true
        defer { isLoading = false }
        
        // Simulate connection test
        try? await Task.sleep(for: .milliseconds(500))
        
        // Return success for local backends, simulated result for cloud
        switch backend {
        case .mlxWhisper, .whisperKit:
            return .success(latency: .milliseconds(100))
        default:
            return .success(latency: .milliseconds(500))
        }
    }
}