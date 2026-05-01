import Foundation
import Testing
@testable import OpenOats

// MARK: - SettingsViewModel Property-Based Tests
// PHASE 1: RED - These tests will fail until implementations are created

@Suite("SettingsViewModel State Transitions")
struct SettingsViewModelStateTransitionTests {
    
    // MARK: - Initial State Invariants
    
    @Test("Initial state has valid defaults")
    func testInitialState() async throws {
        // Given: A newly created SettingsViewModel
        let viewModel = try await createSettingsViewModel()
        
        // Then: Initial state invariants must hold
        #expect(viewModel.isLoading == false)
        #expect(viewModel.error == nil)
        #expect(!viewModel.defaultBackend.rawValue.isEmpty)
        #expect(!viewModel.defaultLanguage.isEmpty)
        #expect(viewModel.sampleRate > 0)
        #expect(viewModel.audioFormat.rawValue.isEmpty == false)
    }
    
    @Test("Initial state has no unsaved changes")
    func testInitialNoUnsavedChanges() async throws {
        // Given: A newly created SettingsViewModel
        let viewModel = try await createSettingsViewModel()
        
        // Then: No unsaved changes initially
        #expect(viewModel.hasUnsavedChanges == false)
    }
    
    // MARK: - Setting Changes
    
    @Test("Changing setting marks as unsaved")
    func testChangeMarksUnsaved() async throws {
        // Given: SettingsViewModel with saved state
        let viewModel = try await createSettingsViewModel()
        #expect(viewModel.hasUnsavedChanges == false)
        
        // When: Changing a setting
        viewModel.defaultLanguage = "es"
        viewModel.markAsChanged()
        
        // Then: Should have unsaved changes
        #expect(viewModel.hasUnsavedChanges == true)
    }
    
    @Test("Changing backend updates selected backend")
    func testChangeBackend() async throws {
        // Given: SettingsViewModel
        let viewModel = try await createSettingsViewModel()
        let originalBackend = viewModel.defaultBackend
        
        // When: Changing backend
        viewModel.defaultBackend = BackendID("whisperkit")
        viewModel.markAsChanged()
        
        // Then: Backend should be updated
        #expect(viewModel.defaultBackend == BackendID("whisperkit"))
        #expect(viewModel.defaultBackend != originalBackend)
    }
    
    @Test("Changing language updates language code")
    func testChangeLanguage() async throws {
        // Given: SettingsViewModel
        let viewModel = try await createSettingsViewModel()
        
        // When: Changing language
        viewModel.defaultLanguage = "es"
        viewModel.markAsChanged()
        
        // Then: Language should be updated
        #expect(viewModel.defaultLanguage == "es")
    }
    
    @Test("Changing audio settings updates values")
    func testChangeAudioSettings() async throws {
        // Given: SettingsViewModel
        let viewModel = try await createSettingsViewModel()
        
        // When: Changing audio settings
        viewModel.sampleRate = 48000
        viewModel.captureSystemAudio = true
        viewModel.captureMicrophone = false
        viewModel.audioFormat = .flac
        viewModel.markAsChanged()
        
        // Then: Settings should be updated
        #expect(viewModel.sampleRate == 48000)
        #expect(viewModel.captureSystemAudio == true)
        #expect(viewModel.captureMicrophone == false)
        #expect(viewModel.audioFormat == .flac)
    }
    
    @Test("Changing AI settings updates values")
    func testChangeAISettings() async throws {
        // Given: SettingsViewModel
        let viewModel = try await createSettingsViewModel()
        
        // When: Changing AI settings
        viewModel.llmProvider = .ollama
        viewModel.noteStyle = .bulletPoints
        viewModel.ollamaEndpoint = URL(string: "http://localhost:11434")
        viewModel.markAsChanged()
        
        // Then: Settings should be updated
        #expect(viewModel.llmProvider == .ollama)
        #expect(viewModel.noteStyle == .bulletPoints)
        #expect(viewModel.ollamaEndpoint?.host == "localhost")
    }
    
    @Test("Changing auto-export settings updates values")
    func testChangeAutoExportSettings() async throws {
        // Given: SettingsViewModel
        let viewModel = try await createSettingsViewModel()
        let exportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("exports")
        
        // When: Changing auto-export settings
        viewModel.autoExportEnabled = true
        viewModel.autoExportFormat = .markdown
        viewModel.autoExportLocation = exportURL
        viewModel.markAsChanged()
        
        // Then: Settings should be updated
        #expect(viewModel.autoExportEnabled == true)
        #expect(viewModel.autoExportFormat == .markdown)
        #expect(viewModel.autoExportLocation == exportURL)
    }
    
    // MARK: - Save Settings
    
    @Test("Save settings clears unsaved flag")
    func testSaveClearsUnsaved() async throws {
        // Given: SettingsViewModel with unsaved changes
        let viewModel = try await createSettingsViewModel()
        viewModel.defaultLanguage = "fr"
        viewModel.markAsChanged()
        #expect(viewModel.hasUnsavedChanges == true)
        
        // When: Saving settings
        try await viewModel.saveSettings()
        
        // Then: Unsaved flag should be cleared
        #expect(viewModel.hasUnsavedChanges == false)
    }
    
    @Test("Save settings persists values")
    func testSavePersistsValues() async throws {
        // Given: SettingsViewModel with changed settings
        let viewModel1 = try await createSettingsViewModel()
        viewModel1.defaultLanguage = "de"
        viewModel1.sampleRate = 44100
        try await viewModel1.saveSettings()
        
        // When: Creating new view model
        let viewModel2 = try await createSettingsViewModel()
        
        // Then: Settings should be persisted
        #expect(viewModel2.defaultLanguage == "de")
        #expect(viewModel2.sampleRate == 44100)
    }
    
    @Test("Save settings shows loading state")
    func testSaveShowsLoading() async throws {
        // Given: SettingsViewModel
        let viewModel = try await createSettingsViewModel()
        viewModel.defaultLanguage = "it"
        viewModel.markAsChanged()
        
        // When: Saving
        let saveTask = Task {
            try await viewModel.saveSettings()
        }
        
        try await Task.sleep(for: .milliseconds(10))
        
        // Then: Should show loading
        #expect(viewModel.isLoading == true)
        
        _ = try await saveTask.value
        
        // After completion
        #expect(viewModel.isLoading == false)
    }
    
    @Test("Save failure sets error")
    func testSaveFailureSetsError() async throws {
        // Given: SettingsViewModel that will fail to save
        let viewModel = try await createFailingSettingsViewModel()
        viewModel.defaultLanguage = "ja"
        viewModel.markAsChanged()
        
        // When: Saving fails
        do {
            try await viewModel.saveSettings()
            Issue.record("Expected save to fail")
        } catch {
            // Then: Error should be set
            #expect(viewModel.error != nil)
        }
    }
    
    // MARK: - Reset to Defaults
    
    @Test("Reset to defaults restores original values")
    func testResetToDefaults() async throws {
        // Given: SettingsViewModel with changed settings
        let viewModel = try await createSettingsViewModel()
        let originalLanguage = viewModel.defaultLanguage
        let originalSampleRate = viewModel.sampleRate
        
        viewModel.defaultLanguage = "ko"
        viewModel.sampleRate = 96000
        viewModel.markAsChanged()
        
        // When: Resetting to defaults
        try await viewModel.resetToDefaults()
        
        // Then: Settings should be restored
        #expect(viewModel.defaultLanguage == originalLanguage)
        #expect(viewModel.sampleRate == originalSampleRate)
    }
    
    @Test("Reset clears unsaved changes")
    func testResetClearsUnsaved() async throws {
        // Given: SettingsViewModel with unsaved changes
        let viewModel = try await createSettingsViewModel()
        viewModel.defaultLanguage = "zh"
        viewModel.markAsChanged()
        #expect(viewModel.hasUnsavedChanges == true)
        
        // When: Resetting
        try await viewModel.resetToDefaults()
        
        // Then: Unsaved flag should be cleared
        #expect(viewModel.hasUnsavedChanges == false)
    }
    
    @Test("Reset shows loading state")
    func testResetShowsLoading() async throws {
        // Given: SettingsViewModel
        let viewModel = try await createSettingsViewModel()
        viewModel.defaultLanguage = "ru"
        viewModel.markAsChanged()
        
        // When: Resetting
        let resetTask = Task {
            try await viewModel.resetToDefaults()
        }
        
        try await Task.sleep(for: .milliseconds(10))
        
        // Then: Should show loading
        #expect(viewModel.isLoading == true)
        
        _ = try await resetTask.value
        
        // After completion
        #expect(viewModel.isLoading == false)
    }
    
    // MARK: - API Key Validation
    
    @Test("Valid API key returns true")
    func testValidAPIKey() async throws {
        // Given: SettingsViewModel
        let viewModel = try await createSettingsViewModel()
        
        // When: Validating valid API key
        let isValid = await viewModel.validateAPIKey("sk-valid-key-12345")
        
        // Then: Should return true (implementation dependent)
        #expect(isValid == true)
        #expect(viewModel.isAPIKeyValid == true)
    }
    
    @Test("Invalid API key returns false")
    func testInvalidAPIKey() async throws {
        // Given: SettingsViewModel
        let viewModel = try await createSettingsViewModel()
        
        // When: Validating invalid API key
        let isValid = await viewModel.validateAPIKey("invalid-key")
        
        // Then: Should return false
        #expect(isValid == false)
        #expect(viewModel.isAPIKeyValid == false)
    }
    
    @Test("Empty API key returns false")
    func testEmptyAPIKey() async throws {
        // Given: SettingsViewModel
        let viewModel = try await createSettingsViewModel()
        
        // When: Validating empty API key
        let isValid = await viewModel.validateAPIKey("")
        
        // Then: Should return false
        #expect(isValid == false)
    }
    
    // MARK: - Import/Export Settings
    
    @Test("Export settings creates file")
    func testExportSettings() async throws {
        // Given: SettingsViewModel
        let viewModel = try await createSettingsViewModel()
        let exportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("settings_export.json")
        
        // When: Exporting settings
        try await viewModel.exportSettings(to: exportURL)
        
        // Then: File should exist
        #expect(FileManager.default.fileExists(atPath: exportURL.path))
        
        // Cleanup
        try? FileManager.default.removeItem(at: exportURL)
    }
    
    @Test("Import settings restores values")
    func testImportSettings() async throws {
        // Given: SettingsViewModel with exported settings
        let viewModel1 = try await createSettingsViewModel()
        viewModel1.defaultLanguage = "pt"
        viewModel1.sampleRate = 32000
        
        let exportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("settings_import_test.json")
        try await viewModel1.exportSettings(to: exportURL)
        
        // When: Importing to new view model
        let viewModel2 = try await createSettingsViewModel()
        try await viewModel2.importSettings(from: exportURL)
        
        // Then: Settings should be restored
        #expect(viewModel2.defaultLanguage == "pt")
        #expect(viewModel2.sampleRate == 32000)
        
        // Cleanup
        try? FileManager.default.removeItem(at: exportURL)
    }
    
    @Test("Import invalid file throws error")
    func testImportInvalidFile() async throws {
        // Given: SettingsViewModel
        let viewModel = try await createSettingsViewModel()
        let invalidURL = URL(fileURLWithPath: "/nonexistent/settings.json")
        
        // When: Importing invalid file
        // Then: Must throw error
        await #expect(throws: PresentationError.self) {
            try await viewModel.importSettings(from: invalidURL)
        }
    }
    
    // MARK: - Validation
    
    @Test("Invalid sample rate throws validation error")
    func testInvalidSampleRate() async throws {
        // Given: SettingsViewModel
        let viewModel = try await createSettingsViewModel()
        
        // When: Setting invalid sample rate
        viewModel.sampleRate = -1
        
        // Then: Validation should fail on save
        await #expect(throws: PresentationError.self) {
            try await viewModel.saveSettings()
        }
    }
    
    @Test("Invalid language code throws validation error")
    func testInvalidLanguageCode() async throws {
        // Given: SettingsViewModel
        let viewModel = try await createSettingsViewModel()
        
        // When: Setting invalid language
        viewModel.defaultLanguage = "invalid_language_code"
        
        // Then: Validation should fail on save
        await #expect(throws: PresentationError.self) {
            try await viewModel.saveSettings()
        }
    }
    
    @Test("Both audio capture disabled throws validation error")
    func testBothAudioCaptureDisabled() async throws {
        // Given: SettingsViewModel
        let viewModel = try await createSettingsViewModel()
        
        // When: Disabling both audio sources
        viewModel.captureSystemAudio = false
        viewModel.captureMicrophone = false
        
        // Then: Validation should fail on save
        await #expect(throws: PresentationError.self) {
            try await viewModel.saveSettings()
        }
    }
    
    // MARK: - Helper Functions
    
    private func createSettingsViewModel() async throws -> any SettingsViewModel {
        throw TestError.notImplemented("SettingsViewModel implementation not available")
    }
    
    private func createFailingSettingsViewModel() async throws -> any SettingsViewModel {
        throw TestError.notImplemented("Failing SettingsViewModel implementation not available")
    }
}

// MARK: - SettingsViewModel Property Tests (Invariants)

@Suite("SettingsViewModel UI State Invariants")
struct SettingsViewModelInvariantTests {
    
    @Test("hasUnsavedChanges implies changes from persisted state")
    func testUnsavedChangesInvariant() async throws {
        // Property: hasUnsavedChanges should be true only when settings differ from persisted
        let viewModel = try await createSettingsViewModel()
        
        // Initially should not have unsaved changes
        #expect(viewModel.hasUnsavedChanges == false)
        
        // After changing, should have unsaved changes
        viewModel.defaultLanguage = "ar"
        viewModel.markAsChanged()
        #expect(viewModel.hasUnsavedChanges == true)
        
        // After saving, should not have unsaved changes
        try await viewModel.saveSettings()
        #expect(viewModel.hasUnsavedChanges == false)
    }
    
    @Test("At least one audio capture enabled")
    func testAtLeastOneAudioCapture() async throws {
        // Property: captureSystemAudio OR captureMicrophone must be true
        let viewModel = try await createSettingsViewModel()
        
        // Initial state
        #expect(viewModel.captureSystemAudio || viewModel.captureMicrophone)
        
        // If we disable one, the other should remain enabled
        viewModel.captureSystemAudio = false
        #expect(viewModel.captureMicrophone == true)
        
        viewModel.captureSystemAudio = true
        viewModel.captureMicrophone = false
        #expect(viewModel.captureSystemAudio == true)
    }
    
    @Test("Sample rate is positive")
    func testSampleRatePositive() async throws {
        // Property: sampleRate > 0
        let viewModel = try await createSettingsViewModel()
        #expect(viewModel.sampleRate > 0)
    }
    
    @Test("Language code is valid ISO code")
    func testValidLanguageCode() async throws {
        // Property: language code should be 2-5 characters
        let viewModel = try await createSettingsViewModel()
        #expect(viewModel.defaultLanguage.count >= 2)
        #expect(viewModel.defaultLanguage.count <= 5)
    }
    
    @Test("Auto-export location is valid when enabled")
    func testAutoExportLocationValid() async throws {
        // Property: If autoExportEnabled, location should be non-nil
        let viewModel = try await createSettingsViewModel()
        
        if viewModel.autoExportEnabled {
            #expect(viewModel.autoExportLocation != nil)
        }
    }
    
    @Test("API key valid state matches validation result")
    func testAPIKeyValidStateMatches() async throws {
        // Property: isAPIKeyValid should match last validation result
        let viewModel = try await createSettingsViewModel()
        
        let isValid = await viewModel.validateAPIKey("test-key")
        #expect(viewModel.isAPIKeyValid == isValid)
    }
    
    @Test("isLoading and hasUnsavedChanges can coexist")
    func testLoadingAndUnsavedChanges() async throws {
        // Property: Loading state doesn't affect unsaved changes tracking
        let viewModel = try await createSettingsViewModel()
        viewModel.defaultLanguage = "he"
        viewModel.markAsChanged()
        #expect(viewModel.hasUnsavedChanges == true)
        
        // During save, both can be true
        let saveTask = Task {
            try await viewModel.saveSettings()
        }
        
        try await Task.sleep(for: .milliseconds(10))
        #expect(viewModel.isLoading == true)
        
        _ = try await saveTask.value
        
        // After save, unsaved changes cleared
        #expect(viewModel.hasUnsavedChanges == false)
        #expect(viewModel.isLoading == false)
    }
    
    @Test("Settings persist across view model instances")
    func testSettingsPersistence() async throws {
        // Property: Settings should persist and be consistent
        let viewModel1 = try await createSettingsViewModel()
        viewModel1.defaultLanguage = "nl"
        viewModel1.sampleRate = 16000
        viewModel1.llmProvider = .openRouter
        try await viewModel1.saveSettings()
        
        let viewModel2 = try await createSettingsViewModel()
        #expect(viewModel2.defaultLanguage == "nl")
        #expect(viewModel2.sampleRate == 16000)
        #expect(viewModel2.llmProvider == .openRouter)
    }
    
    // MARK: - Helper Functions
    
    private func createSettingsViewModel() async throws -> any SettingsViewModel {
        throw TestError.notImplemented("SettingsViewModel implementation not available")
    }
}

// MARK: - Error Presentation Tests

@Suite("SettingsViewModel Error Presentation")
struct SettingsViewModelErrorPresentationTests {
    
    @Test("Validation failure presents correct error")
    func testValidationFailure() async throws {
        let viewModel = try await createSettingsViewModel()
        viewModel.sampleRate = -100 // Invalid
        
        do {
            try await viewModel.saveSettings()
            Issue.record("Expected validation to fail")
        } catch {
            guard let presentationError = viewModel.error else {
                Issue.record("Expected error to be set")
                return
            }
            
            if case .validationFailed(let field, _) = presentationError {
                #expect(field == "sampleRate" || field == "audio")
            } else {
                Issue.record("Expected validationFailed error")
            }
        }
    }
    
    @Test("Import failure presents correct error")
    func testImportFailure() async throws {
        let viewModel = try await createSettingsViewModel()
        let invalidURL = URL(fileURLWithPath: "/invalid/import.json")
        
        do {
            try await viewModel.importSettings(from: invalidURL)
            Issue.record("Expected import to fail")
        } catch {
            guard let presentationError = viewModel.error else {
                Issue.record("Expected error to be set")
                return
            }
            
            // Should have some error set
            #expect(viewModel.error != nil)
        }
    }
    
    @Test("Network error for API validation")
    func testAPIValidationNetworkError() async throws {
        let viewModel = try await createOfflineSettingsViewModel()
        
        let isValid = await viewModel.validateAPIKey("any-key")
        
        // Should fail due to network
        #expect(isValid == false)
        // May or may not set error depending on implementation
    }
    
    @Test("Error provides recovery suggestion")
    func testErrorRecoverySuggestion() async throws {
        let error = PresentationError.validationFailed(field: "sampleRate", reason: "Invalid value")
        
        #expect(error.recoverySuggestion?.contains("field") == true)
        #expect(error.errorDescription?.contains("sampleRate") == true)
    }
    
    @Test("Clear error removes error state")
    func testClearError() async throws {
        // Given: SettingsViewModel with error
        let viewModel = try await createSettingsViewModel()
        viewModel.sampleRate = -1
        do {
            try await viewModel.saveSettings()
        } catch {
            #expect(viewModel.error != nil)
        }
        
        // When: Clearing error
        viewModel.clearError()
        
        // Then: Error should be nil
        #expect(viewModel.error == nil)
    }
    
    // MARK: - Helper Functions
    
    private func createSettingsViewModel() async throws -> any SettingsViewModel {
        throw TestError.notImplemented("SettingsViewModel implementation not available")
    }
    
    private func createOfflineSettingsViewModel() async throws -> any SettingsViewModel {
        throw TestError.notImplemented("Offline SettingsViewModel implementation not available")
    }
}
