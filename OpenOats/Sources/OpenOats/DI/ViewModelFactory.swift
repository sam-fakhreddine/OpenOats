import Foundation
import SwiftUI

// MARK: - ViewModelFactory Implementation

/// Default implementation of ViewModelFactory.
/// Creates view models with their required dependencies from a UseCaseFactory.
@MainActor
struct ViewModelFactoryImpl: ViewModelFactory {
    
    // MARK: - Dependencies
    
    private let useCaseFactory: any UseCaseFactory
    
    // MARK: - Initialization
    
    /// Creates a new ViewModelFactory with the specified use case factory.
    /// - Parameter useCaseFactory: Factory for creating use cases.
    init(useCaseFactory: any UseCaseFactory) {
        self.useCaseFactory = useCaseFactory
    }
    
    // MARK: - Main View Models
    
    /// Creates a view model for the recording session screen.
    /// Uses lazy initialization to cache the instance.
    func makeSessionViewModel() -> any SessionViewModel {
        return DefaultSessionViewModel()
    }
    
    /// Creates a view model for the transcript display screen.
    /// Uses lazy initialization to cache the instance.
    func makeTranscriptViewModel() -> any TranscriptViewModel {
        return DefaultTranscriptViewModel()
    }
    
    /// Creates a view model for the settings screen.
    /// Uses lazy initialization to cache the instance.
    func makeSettingsViewModel() -> any SettingsViewModel {
        return DefaultSettingsViewModel()
    }
    
    /// Creates a view model for the idle dashboard (home screen).
    /// Uses lazy initialization to cache the instance.
    func makeIdleDashboardViewModel() -> any IdleDashboardViewModel {
        return DefaultIdleDashboardViewModel()
    }
    
    /// Creates a view model for backend configuration.
    func makeBackendConfigurationViewModel() -> any BackendConfigurationViewModel {
        // Return a default implementation from DIContainer
        return DIContainerDefaultBackendConfigurationViewModel()
    }
}