import Foundation
import SwiftUI

// MARK: - DefaultSettingsViewModel

/// Default implementation of SettingsViewModel for app settings
@MainActor
@Observable
final class DefaultSettingsViewModel: SettingsViewModel {
    let id: UUID
    
    // Loading and error state
    var isLoading: Bool = false
    var error: PresentationError? = nil
    
    // Settings change tracking
    var hasUnsavedChanges: Bool = false
    var isAPIKeyValid: Bool = false
    
    // General Settings
    var defaultBackend: BackendID {
        didSet { markAsChanged() }
    }
    var defaultLanguage: String {
        didSet { markAsChanged() }
    }
    var autoExportEnabled: Bool {
        didSet { markAsChanged() }
    }
    var autoExportFormat: ExportFormat {
        didSet { markAsChanged() }
    }
    var autoExportLocation: URL? {
        didSet { markAsChanged() }
    }
    
    // Audio Settings
    var sampleRate: Int {
        didSet { markAsChanged() }
    }
    var captureSystemAudio: Bool {
        didSet { 
            markAsChanged()
            validateAudioCapture()
        }
    }
    var captureMicrophone: Bool {
        didSet { 
            markAsChanged()
            validateAudioCapture()
        }
    }
    var audioFormat: AudioRecordingFormat {
        didSet { markAsChanged() }
    }
    
    // AI Settings
    var llmProvider: LLMProvider {
        didSet { markAsChanged() }
    }
    var openRouterAPIKey: String? {
        didSet { markAsChanged() }
    }
    var ollamaEndpoint: URL? {
        didSet { markAsChanged() }
    }
    var noteStyle: NoteGenerationStyle {
        didSet { markAsChanged() }
    }
    
    // Private state
    private var originalSettings: SettingsSnapshot?
    private var shouldFailSave: Bool
    private var isOffline: Bool
    
    private struct SettingsSnapshot: Sendable {
        let defaultBackend: BackendID
        let defaultLanguage: String
        let autoExportEnabled: Bool
        let autoExportFormat: ExportFormat
        let autoExportLocation: URL?
        let sampleRate: Int
        let captureSystemAudio: Bool
        let captureMicrophone: Bool
        let audioFormat: AudioRecordingFormat
        let llmProvider: LLMProvider
        let openRouterAPIKey: String?
        let ollamaEndpoint: URL?
        let noteStyle: NoteGenerationStyle
    }
    
    init(shouldFailSave: Bool = false, isOffline: Bool = false) {
        self.id = UUID()
        self.shouldFailSave = shouldFailSave
        self.isOffline = isOffline
        
        // Set defaults
        self.defaultBackend = .mlxWhisper
        self.defaultLanguage = "en"
        self.autoExportEnabled = false
        self.autoExportFormat = .plainText
        self.autoExportLocation = nil
        self.sampleRate = 16000
        self.captureSystemAudio = true
        self.captureMicrophone = true
        self.audioFormat = .wav
        self.llmProvider = .openRouter
        self.openRouterAPIKey = nil
        self.ollamaEndpoint = nil
        self.noteStyle = .concise
        
        // Save original settings for reset
        self.originalSettings = SettingsSnapshot(
            defaultBackend: defaultBackend,
            defaultLanguage: defaultLanguage,
            autoExportEnabled: autoExportEnabled,
            autoExportFormat: autoExportFormat,
            autoExportLocation: autoExportLocation,
            sampleRate: sampleRate,
            captureSystemAudio: captureSystemAudio,
            captureMicrophone: captureMicrophone,
            audioFormat: audioFormat,
            llmProvider: llmProvider,
            openRouterAPIKey: openRouterAPIKey,
            ollamaEndpoint: ollamaEndpoint,
            noteStyle: noteStyle
        )
    }
    
    func clearError() {
        error = nil
    }
    
    func markAsChanged() {
        hasUnsavedChanges = true
    }
    
    func saveSettings() async throws {
        guard !isLoading else {
            throw PresentationError.validationFailed(field: "save", reason: "Save in progress")
        }
        
        isLoading = true
        defer { isLoading = false }
        
        // Validate settings
        try validateSettings()
        
        // Simulate failure if configured
        if shouldFailSave {
            let failError = PresentationError.sessionStartFailed(reason: "Save failed")
            error = failError
            throw failError
        }
        
        // In a real implementation, this would save to UserDefaults or a settings repository
        // For now, we just mark as saved
        
        // Update original settings
        originalSettings = SettingsSnapshot(
            defaultBackend: defaultBackend,
            defaultLanguage: defaultLanguage,
            autoExportEnabled: autoExportEnabled,
            autoExportFormat: autoExportFormat,
            autoExportLocation: autoExportLocation,
            sampleRate: sampleRate,
            captureSystemAudio: captureSystemAudio,
            captureMicrophone: captureMicrophone,
            audioFormat: audioFormat,
            llmProvider: llmProvider,
            openRouterAPIKey: openRouterAPIKey,
            ollamaEndpoint: ollamaEndpoint,
            noteStyle: noteStyle
        )
        
        hasUnsavedChanges = false
        
        // Simulate async save
        try await Task.sleep(for: .milliseconds(50))
    }
    
    func resetToDefaults() async throws {
        guard !isLoading else {
            throw PresentationError.validationFailed(field: "reset", reason: "Operation in progress")
        }
        
        isLoading = true
        defer { isLoading = false }
        
        guard let original = originalSettings else {
            return
        }
        
        // Restore original settings
        defaultBackend = original.defaultBackend
        defaultLanguage = original.defaultLanguage
        autoExportEnabled = original.autoExportEnabled
        autoExportFormat = original.autoExportFormat
        autoExportLocation = original.autoExportLocation
        sampleRate = original.sampleRate
        captureSystemAudio = original.captureSystemAudio
        captureMicrophone = original.captureMicrophone
        audioFormat = original.audioFormat
        llmProvider = original.llmProvider
        openRouterAPIKey = original.openRouterAPIKey
        ollamaEndpoint = original.ollamaEndpoint
        noteStyle = original.noteStyle
        
        hasUnsavedChanges = false
        
        // Simulate async reset
        try await Task.sleep(for: .milliseconds(50))
    }
    
    func validateAPIKey(_ key: String) async -> Bool {
        // Simulate offline check
        if isOffline {
            isAPIKeyValid = false
            return false
        }
        
        // Simple validation: key must be non-empty and have minimum length
        let isValid = !key.isEmpty && key.count >= 10 && key.hasPrefix("sk-")
        isAPIKeyValid = isValid
        return isValid
    }
    
    func exportSettings(to url: URL) async throws {
        let settings = SettingsExport(
            defaultBackend: defaultBackend.rawValue,
            defaultLanguage: defaultLanguage,
            autoExportEnabled: autoExportEnabled,
            autoExportFormat: autoExportFormat.rawValue,
            sampleRate: sampleRate,
            captureSystemAudio: captureSystemAudio,
            captureMicrophone: captureMicrophone,
            audioFormat: audioFormat.rawValue,
            llmProvider: llmProvider.rawValue,
            noteStyle: noteStyle.rawValue
        )
        
        let data = try JSONEncoder().encode(settings)
        try data.write(to: url)
    }
    
    func importSettings(from url: URL) async throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            let failError = PresentationError.transcriptLoadFailed(id: TranscriptID(), reason: "Settings file not found")
            error = failError
            throw failError
        }
        
        let data = try Data(contentsOf: url)
        let imported = try JSONDecoder().decode(SettingsExport.self, from: data)
        
        // Apply imported settings
        defaultBackend = BackendID(imported.defaultBackend)
        defaultLanguage = imported.defaultLanguage
        autoExportEnabled = imported.autoExportEnabled
        autoExportFormat = ExportFormat(rawValue: imported.autoExportFormat) ?? .plainText
        sampleRate = imported.sampleRate
        captureSystemAudio = imported.captureSystemAudio
        captureMicrophone = imported.captureMicrophone
        audioFormat = AudioRecordingFormat(rawValue: imported.audioFormat) ?? .wav
        llmProvider = LLMProvider(rawValue: imported.llmProvider) ?? .openRouter
        noteStyle = NoteGenerationStyle(rawValue: imported.noteStyle) ?? .concise
        
        markAsChanged()
    }
    
    // MARK: - Private Methods
    
    private func validateSettings() throws {
        // Validate sample rate
        guard sampleRate > 0 else {
            let failError = PresentationError.validationFailed(field: "sampleRate", reason: "Sample rate must be positive")
            error = failError
            throw failError
        }
        
        // Validate language code (2-5 characters)
        guard defaultLanguage.count >= 2 && defaultLanguage.count <= 5 else {
            let failError = PresentationError.validationFailed(field: "language", reason: "Invalid language code")
            error = failError
            throw failError
        }
        
        // Validate at least one audio source is enabled
        guard captureSystemAudio || captureMicrophone else {
            let failError = PresentationError.validationFailed(field: "audio", reason: "At least one audio source must be enabled")
            error = failError
            throw failError
        }
    }
    
    private func validateAudioCapture() {
        // Ensure at least one audio capture is enabled
        if !captureSystemAudio && !captureMicrophone {
            // Re-enable microphone if both were disabled
            captureMicrophone = true
        }
    }
}

// MARK: - Settings Export Model

private struct SettingsExport: Codable {
    let defaultBackend: String
    let defaultLanguage: String
    let autoExportEnabled: Bool
    let autoExportFormat: String
    let sampleRate: Int
    let captureSystemAudio: Bool
    let captureMicrophone: Bool
    let audioFormat: String
    let llmProvider: String
    let noteStyle: String
}
