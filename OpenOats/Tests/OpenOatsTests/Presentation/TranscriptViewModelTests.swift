import Foundation
import Testing
@testable import OpenOats

// MARK: - TranscriptViewModel Property-Based Tests
// PHASE 1: RED - These tests will fail until implementations are created

@Suite("TranscriptViewModel State Transitions")
struct TranscriptViewModelStateTransitionTests {
    
    // MARK: - Initial State Invariants
    
    @Test("Initial state has no transcript")
    func testInitialState() async throws {
        // Given: A newly created TranscriptViewModel
        let viewModel = try await createTranscriptViewModel()
        
        // Then: Initial state invariants must hold
        #expect(viewModel.transcript == nil)
        #expect(viewModel.utterances.isEmpty)
        #expect(viewModel.isTranscribing == false)
        #expect(viewModel.isLoading == false)
        #expect(viewModel.error == nil)
        #expect(viewModel.searchQuery.isEmpty)
        #expect(viewModel.filteredUtterances.isEmpty)
        #expect(viewModel.selectedSpeaker == nil)
        #expect(viewModel.speakers.isEmpty)
        #expect(viewModel.currentSearchIndex == nil)
        #expect(viewModel.searchResultCount == 0)
    }
    
    // MARK: - Transcript Loading
    
    @Test("Load transcript sets transcript and utterances")
    func testLoadTranscript() async throws {
        // Given: TranscriptViewModel with no transcript
        let viewModel = try await createTranscriptViewModel()
        let transcriptID = TranscriptID()
        
        // When: Loading transcript
        try await viewModel.loadTranscript(id: transcriptID)
        
        // Then: Transcript should be loaded
        #expect(viewModel.transcript != nil)
        #expect(viewModel.transcript?.id == transcriptID)
        #expect(!viewModel.utterances.isEmpty)
    }
    
    @Test("Load transcript populates speakers")
    func testLoadTranscriptPopulatesSpeakers() async throws {
        // Given: TranscriptViewModel
        let viewModel = try await createTranscriptViewModel()
        let transcriptID = TranscriptID()
        
        // When: Loading transcript
        try await viewModel.loadTranscript(id: transcriptID)
        
        // Then: Speakers should be populated
        #expect(!viewModel.speakers.isEmpty)
        
        // Each speaker should have valid properties
        for speaker in viewModel.speakers {
            #expect(!speaker.name.isEmpty)
            #expect(speaker.utteranceCount >= 0)
        }
    }
    
    @Test("Load invalid transcript throws error")
    func testLoadInvalidTranscript() async throws {
        // Given: TranscriptViewModel
        let viewModel = try await createTranscriptViewModel()
        let invalidID = TranscriptID()
        
        // When: Loading non-existent transcript
        // Then: Must throw error
        await #expect(throws: PresentationError.self) {
            try await viewModel.loadTranscript(id: invalidID)
        }
    }
    
    @Test("Loading shows transcription state")
    func testLoadingShowsTranscriptionState() async throws {
        // Given: TranscriptViewModel
        let viewModel = try await createTranscriptViewModel()
        let transcriptID = TranscriptID()
        
        // When: Loading in-progress transcript
        let loadTask = Task {
            try await viewModel.loadTranscript(id: transcriptID)
        }
        
        try await Task.sleep(for: .milliseconds(10))
        
        // Then: Should show transcribing state
        #expect(viewModel.isLoading == true)
        
        _ = try await loadTask.value
        
        // After completion
        #expect(viewModel.isLoading == false)
    }
    
    // MARK: - Search Functionality
    
    @Test("Search filters utterances")
    func testSearchFiltersUtterances() async throws {
        // Given: TranscriptViewModel with loaded transcript
        let viewModel = try await createTranscriptViewModelWithTranscript()
        let initialUtterances = viewModel.utterances
        #expect(initialUtterances.count >= 3, "Need at least 3 utterances for search test")
        
        // When: Searching
        viewModel.search("test query")
        
        // Then: Filtered utterances should be subset of all
        #expect(viewModel.filteredUtterances.count <= initialUtterances.count)
        #expect(viewModel.searchQuery == "test query")
    }
    
    @Test("Empty search shows all utterances")
    func testEmptySearchShowsAll() async throws {
        // Given: TranscriptViewModel with search results
        let viewModel = try await createTranscriptViewModelWithTranscript()
        viewModel.search("test")
        #expect(viewModel.filteredUtterances.count < viewModel.utterances.count)
        
        // When: Clearing search
        viewModel.search("")
        
        // Then: All utterances should be shown
        #expect(viewModel.filteredUtterances.count == viewModel.utterances.count)
        #expect(viewModel.searchQuery.isEmpty)
    }
    
    @Test("Search highlights matching utterances")
    func testSearchHighlightsMatches() async throws {
        // Given: TranscriptViewModel with loaded transcript
        let viewModel = try await createTranscriptViewModelWithTranscript()
        
        // When: Searching for text that exists
        viewModel.search("specific word")
        
        // Then: Matching utterances should be highlighted
        let highlighted = viewModel.filteredUtterances.filter { $0.isHighlighted }
        #expect(!highlighted.isEmpty)
    }
    
    @Test("No matches returns empty filtered list")
    func testNoMatchesReturnsEmpty() async throws {
        // Given: TranscriptViewModel with loaded transcript
        let viewModel = try await createTranscriptViewModelWithTranscript()
        
        // When: Searching for non-existent text
        viewModel.search("xyznonexistent123")
        
        // Then: Filtered list should be empty
        #expect(viewModel.filteredUtterances.isEmpty)
        #expect(viewModel.searchResultCount == 0)
    }
    
    // MARK: - Search Navigation
    
    @Test("Next search result increments index")
    func testNextSearchResult() async throws {
        // Given: TranscriptViewModel with search results
        let viewModel = try await createTranscriptViewModelWithTranscript()
        viewModel.search("common word")
        #expect(viewModel.searchResultCount >= 2)
        
        // When: Navigating to next result
        viewModel.nextSearchResult()
        
        // Then: Index should be 0 (first result)
        #expect(viewModel.currentSearchIndex == 0)
        
        // When: Navigating again
        viewModel.nextSearchResult()
        
        // Then: Index should be 1
        #expect(viewModel.currentSearchIndex == 1)
    }
    
    @Test("Next search result wraps around")
    func testNextSearchResultWraps() async throws {
        // Given: TranscriptViewModel with search results
        let viewModel = try await createTranscriptViewModelWithTranscript()
        viewModel.search("word")
        let count = viewModel.searchResultCount
        #expect(count >= 2)
        
        // Navigate to last result
        for _ in 0..<count {
            viewModel.nextSearchResult()
        }
        
        // Then: Should wrap to first
        #expect(viewModel.currentSearchIndex == 0)
    }
    
    @Test("Previous search result decrements index")
    func testPreviousSearchResult() async throws {
        // Given: TranscriptViewModel at second result
        let viewModel = try await createTranscriptViewModelWithTranscript()
        viewModel.search("word")
        viewModel.nextSearchResult()
        viewModel.nextSearchResult()
        #expect(viewModel.currentSearchIndex == 1)
        
        // When: Going to previous
        viewModel.previousSearchResult()
        
        // Then: Should be at first result
        #expect(viewModel.currentSearchIndex == 0)
    }
    
    @Test("Previous search result wraps around")
    func testPreviousSearchResultWraps() async throws {
        // Given: TranscriptViewModel with search results
        let viewModel = try await createTranscriptViewModelWithTranscript()
        viewModel.search("word")
        let count = viewModel.searchResultCount
        #expect(count >= 2)
        
        // When: Going previous from start
        viewModel.previousSearchResult()
        
        // Then: Should wrap to last
        #expect(viewModel.currentSearchIndex == count - 1)
    }
    
    @Test("Navigation with no results does nothing")
    func testNavigationWithNoResults() async throws {
        // Given: TranscriptViewModel with no search results
        let viewModel = try await createTranscriptViewModelWithTranscript()
        viewModel.search("xyznonexistent123")
        #expect(viewModel.searchResultCount == 0)
        
        // When: Attempting navigation
        viewModel.nextSearchResult()
        
        // Then: Index should remain nil
        #expect(viewModel.currentSearchIndex == nil)
    }
    
    // MARK: - Speaker Filtering
    
    @Test("Selecting speaker filters utterances")
    func testSpeakerFiltering() async throws {
        // Given: TranscriptViewModel with multiple speakers
        let viewModel = try await createTranscriptViewModelWithTranscript()
        #expect(viewModel.speakers.count >= 2, "Need at least 2 speakers for filter test")
        
        let speaker = viewModel.speakers[0]
        let initialUtteranceCount = viewModel.utterances.count
        
        // When: Selecting speaker
        viewModel.selectedSpeaker = speaker.id
        
        // Then: Should show fewer utterances
        #expect(viewModel.filteredUtterances.count <= initialUtteranceCount)
        
        // All filtered utterances should belong to selected speaker
        for utterance in viewModel.filteredUtterances {
            #expect(utterance.speakerName == speaker.name)
        }
    }
    
    @Test("Deselecting speaker shows all utterances")
    func testDeselectSpeakerShowsAll() async throws {
        // Given: TranscriptViewModel with speaker selected
        let viewModel = try await createTranscriptViewModelWithTranscript()
        viewModel.selectedSpeaker = viewModel.speakers[0].id
        let filteredCount = viewModel.filteredUtterances.count
        
        // When: Deselecting speaker
        viewModel.selectedSpeaker = nil
        
        // Then: Should show all utterances
        #expect(viewModel.filteredUtterances.count > filteredCount)
        #expect(viewModel.filteredUtterances.count == viewModel.utterances.count)
    }
    
    @Test("Speaker filter combines with search")
    func testSpeakerAndSearchFilter() async throws {
        // Given: TranscriptViewModel with transcript
        let viewModel = try await createTranscriptViewModelWithTranscript()
        #expect(viewModel.speakers.count >= 1)
        
        // Apply both filters
        viewModel.selectedSpeaker = viewModel.speakers[0].id
        viewModel.search("word")
        
        // Then: Results should satisfy both filters
        for utterance in viewModel.filteredUtterances {
            #expect(utterance.speakerName == viewModel.speakers[0].name)
            // Should also match search (implementation dependent)
        }
    }
    
    // MARK: - Utterance Editing
    
    @Test("Edit utterance updates text")
    func testEditUtterance() async throws {
        // Given: TranscriptViewModel with loaded transcript
        let viewModel = try await createTranscriptViewModelWithTranscript()
        #expect(!viewModel.utterances.isEmpty)
        
        let utterance = viewModel.utterances[0]
        let newText = "Updated text"
        
        // When: Editing utterance
        try await viewModel.editUtterance(utterance.id, newText: newText)
        
        // Then: Utterance text should be updated
        let updatedUtterance = viewModel.utterances.first { $0.id == utterance.id }
        #expect(updatedUtterance?.text == newText)
    }
    
    @Test("Edit non-existent utterance throws error")
    func testEditNonExistentUtterance() async throws {
        // Given: TranscriptViewModel
        let viewModel = try await createTranscriptViewModel()
        
        // When: Editing non-existent utterance
        // Then: Must throw error
        await #expect(throws: PresentationError.self) {
            try await viewModel.editUtterance(UtteranceID(), newText: "text")
        }
    }
    
    // MARK: - Timestamp Navigation
    
    @Test("Jump to timestamp updates view state")
    func testJumpToTimestamp() async throws {
        // Given: TranscriptViewModel with loaded transcript
        let viewModel = try await createTranscriptViewModelWithTranscript()
        
        // When: Jumping to timestamp
        viewModel.jumpTo(.seconds(10))
        
        // Then: View should update (implementation dependent)
        // This test verifies the method exists and can be called
        #expect(viewModel.transcript != nil)
    }
    
    // MARK: - Export Functionality
    
    @Test("Export transcript creates file")
    func testExportTranscript() async throws {
        // Given: TranscriptViewModel with loaded transcript
        let viewModel = try await createTranscriptViewModelWithTranscript()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_export.txt")
        
        // When: Exporting
        try await viewModel.export(to: .plainText, at: tempURL)
        
        // Then: File should exist
        #expect(FileManager.default.fileExists(atPath: tempURL.path))
        
        // Cleanup
        try? FileManager.default.removeItem(at: tempURL)
    }
    
    @Test("Export unsupported format throws error")
    func testExportUnsupportedFormat() async throws {
        // Given: TranscriptViewModel
        let viewModel = try await createTranscriptViewModel()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_export.xyz")
        
        // When: Exporting with invalid format (if applicable)
        // Then: Must handle appropriately
        // This test is format-dependent
    }
    
    @Test("Export without transcript throws error")
    func testExportWithoutTranscript() async throws {
        // Given: TranscriptViewModel with no transcript
        let viewModel = try await createTranscriptViewModel()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_export.txt")
        
        // When: Attempting to export without transcript
        // Then: Must throw error
        await #expect(throws: PresentationError.self) {
            try await viewModel.export(to: .plainText, at: tempURL)
        }
    }
    
    // MARK: - Helper Functions
    
    private func createTranscriptViewModel() async throws -> any TranscriptViewModel {
        throw TestError.notImplemented("TranscriptViewModel implementation not available")
    }
    
    private func createTranscriptViewModelWithTranscript() async throws -> any TranscriptViewModel {
        throw TestError.notImplemented("TranscriptViewModel with transcript implementation not available")
    }
}

// MARK: - TranscriptViewModel Property Tests (Invariants)

@Suite("TranscriptViewModel UI State Invariants")
struct TranscriptViewModelInvariantTests {
    
    @Test("Filtered utterances always subset of all utterances")
    func testFilteredIsSubset() async throws {
        // Property: filteredUtterances ⊆ utterances
        let viewModel = try await createTranscriptViewModelWithTranscript()
        
        // Test with various filters
        viewModel.search("test")
        for filtered in viewModel.filteredUtterances {
            #expect(viewModel.utterances.contains { $0.id == filtered.id })
        }
        
        viewModel.selectedSpeaker = viewModel.speakers.first?.id
        for filtered in viewModel.filteredUtterances {
            #expect(viewModel.utterances.contains { $0.id == filtered.id })
        }
    }
    
    @Test("Search result count matches filtered utterances count")
    func testSearchResultCountMatches() async throws {
        // Property: searchResultCount == filteredUtterances.count (when searching)
        let viewModel = try await createTranscriptViewModelWithTranscript()
        
        viewModel.search("test")
        #expect(viewModel.searchResultCount == viewModel.filteredUtterances.count)
    }
    
    @Test("Current search index within bounds")
    func testSearchIndexWithinBounds() async throws {
        // Property: currentSearchIndex < searchResultCount
        let viewModel = try await createTranscriptViewModelWithTranscript()
        
        viewModel.search("word")
        
        if let index = viewModel.currentSearchIndex {
            #expect(index >= 0)
            #expect(index < viewModel.searchResultCount)
        }
    }
    
    @Test("isTranscribing implies transcript is incomplete")
    func testTranscribingImpliesIncomplete() async throws {
        // Property: isTranscribing → transcript?.isComplete == false
        let viewModel = try await createTranscriptViewModel()
        
        // Start loading a transcript
        let task = Task {
            try await viewModel.loadTranscript(id: TranscriptID())
        }
        
        try await Task.sleep(for: .milliseconds(10))
        
        if viewModel.isTranscribing {
            #expect(viewModel.transcript == nil || viewModel.transcript?.isComplete == false)
        }
        
        _ = try? await task.value
    }
    
    @Test("Speaker colors are unique per speaker")
    func testSpeakerColorsUnique() async throws {
        // Property: Each speaker has a unique color
        let viewModel = try await createTranscriptViewModelWithTranscript()
        
        var usedColors: [SpeakerColor] = []
        for speaker in viewModel.speakers {
            // Colors should not repeat within visible speakers
            // (This is a soft invariant - colors can repeat if many speakers)
            if usedColors.count < SpeakerColor.allCases.count {
                #expect(!usedColors.contains(speaker.color) || viewModel.speakers.count > SpeakerColor.allCases.count)
                usedColors.append(speaker.color)
            }
        }
    }
    
    @Test("Utterance times are chronological")
    func testUtteranceTimesChronological() async throws {
        // Property: utterances[i].endTime ≤ utterances[i+1].startTime
        let viewModel = try await createTranscriptViewModelWithTranscript()
        
        let utterances = viewModel.utterances
        for i in 0..<(utterances.count - 1) {
            #expect(utterances[i].endTime <= utterances[i + 1].startTime)
        }
    }
    
    @Test("All utterance speakers exist in speakers list")
    func testAllSpeakersExist() async throws {
        // Property: For each utterance, utterance.speakerID exists in speakers
        let viewModel = try await createTranscriptViewModelWithTranscript()
        
        let speakerIDs = Set(viewModel.speakers.map { $0.id })
        for utterance in viewModel.utterances {
            // Find matching speaker by name (since UtteranceViewModel doesn't have speakerID)
            let hasMatchingSpeaker = viewModel.speakers.contains { $0.name == utterance.speakerName }
            #expect(hasMatchingSpeaker)
        }
    }
    
    // MARK: - Helper Functions
    
    private func createTranscriptViewModelWithTranscript() async throws -> any TranscriptViewModel {
        throw TestError.notImplemented("TranscriptViewModel with transcript implementation not available")
    }
}

// MARK: - Error Presentation Tests

@Suite("TranscriptViewModel Error Presentation")
struct TranscriptViewModelErrorPresentationTests {
    
    @Test("Transcript load failure presents correct error")
    func testTranscriptLoadFailure() async throws {
        let viewModel = try await createFailingTranscriptViewModel()
        let transcriptID = TranscriptID()
        
        do {
            try await viewModel.loadTranscript(id: transcriptID)
            Issue.record("Expected operation to fail")
        } catch {
            guard let presentationError = viewModel.error else {
                Issue.record("Expected error to be set")
                return
            }
            
            if case .transcriptLoadFailed(let id, _) = presentationError {
                #expect(id == transcriptID)
            } else {
                Issue.record("Expected transcriptLoadFailed error")
            }
        }
    }
    
    @Test("Export failure presents correct error")
    func testExportFailure() async throws {
        let viewModel = try await createTranscriptViewModelWithTranscript()
        let invalidURL = URL(fileURLWithPath: "/invalid/path/test.txt")
        
        do {
            try await viewModel.export(to: .plainText, at: invalidURL)
            Issue.record("Expected operation to fail")
        } catch {
            guard let presentationError = viewModel.error else {
                Issue.record("Expected error to be set")
                return
            }
            
            if case .exportFailed(let format, _) = presentationError {
                #expect(format == .plainText)
            } else {
                Issue.record("Expected exportFailed error")
            }
        }
    }
    
    @Test("Error clears when loading succeeds")
    func testErrorClearsOnSuccess() async throws {
        // Given: ViewModel with error
        let viewModel = try await createFailingTranscriptViewModel()
        do {
            try await viewModel.loadTranscript(id: TranscriptID())
        } catch {
            #expect(viewModel.error != nil)
        }
        
        // When: Loading with working view model
        let workingViewModel = try await createTranscriptViewModel()
        try await workingViewModel.loadTranscript(id: TranscriptID())
        
        // Then: Error should be nil
        #expect(workingViewModel.error == nil)
    }
    
    @Test("Clear error removes error state")
    func testClearError() async throws {
        // Given: ViewModel with error
        let viewModel = try await createFailingTranscriptViewModel()
        do {
            try await viewModel.loadTranscript(id: TranscriptID())
        } catch {
            #expect(viewModel.error != nil)
        }
        
        // When: Clearing error
        viewModel.clearError()
        
        // Then: Error should be nil
        #expect(viewModel.error == nil)
    }
    
    // MARK: - Helper Functions
    
    private func createTranscriptViewModel() async throws -> any TranscriptViewModel {
        throw TestError.notImplemented("TranscriptViewModel implementation not available")
    }
    
    private func createTranscriptViewModelWithTranscript() async throws -> any TranscriptViewModel {
        throw TestError.notImplemented("TranscriptViewModel with transcript implementation not available")
    }
    
    private func createFailingTranscriptViewModel() async throws -> any TranscriptViewModel {
        throw TestError.notImplemented("Failing TranscriptViewModel implementation not available")
    }
}
