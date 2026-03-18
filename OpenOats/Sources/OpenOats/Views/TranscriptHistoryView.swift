import SwiftUI

struct TranscriptHistoryView: View {
    @Bindable var settings: AppSettings
    @State private var store = HistoryStore()
    @State private var selectedSession: TranscriptSession?
    @State private var sessionContent: String = ""
    @State private var isLoadingContent = false
    @State private var sessionToDelete: TranscriptSession?
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationSplitView {
            sidebarView
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            detailView
        }
        .frame(minWidth: 700, minHeight: 480)
        .onAppear {
            reloadSessions()
        }
        .onChange(of: settings.notesFolderPath) {
            reloadSessions()
        }
        .confirmationDialog(
            "Delete this transcript?",
            isPresented: $showDeleteConfirm,
            presenting: sessionToDelete
        ) { session in
            Button("Delete \(session.fileName)", role: .destructive) {
                try? store.delete(session)
                if selectedSession?.id == session.id {
                    selectedSession = nil
                    sessionContent = ""
                }
            }
        } message: { session in
            Text("\u{201C}\(session.dateDisplay)\u{201D} will be permanently deleted.")
        }
    }

    // MARK: - Sidebar

    private var sidebarView: some View {
        VStack(spacing: 0) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                TextField("Search sessions\u{2026}", text: $store.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !store.searchText.isEmpty {
                    Button {
                        store.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)

            Divider()

            if store.sessions.isEmpty {
                emptyStateView(message: "No saved transcripts found in\n\(settings.notesFolderPath)")
            } else if store.filteredSessions.isEmpty {
                emptyStateView(message: "No sessions match \u{201C}\(store.searchText)\u{201D}")
            } else {
                List(store.filteredSessions, selection: $selectedSession) { session in
                    sessionRow(session)
                        .tag(session)
                }
                .listStyle(.sidebar)
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    reloadSessions()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
            }
        }
    }

    private func sessionRow(_ session: TranscriptSession) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(session.dateDisplay)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            HStack(spacing: 8) {
                Label(session.durationDisplay, systemImage: "clock")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Label("\(session.utteranceCount)", systemImage: "text.bubble")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([session.filePath])
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }
            Divider()
            Button(role: .destructive) {
                sessionToDelete = session
                showDeleteConfirm = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Detail

    private var detailView: some View {
        Group {
            if let session = selectedSession {
                VStack(spacing: 0) {
                    // Detail toolbar
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.dateDisplay)
                                .font(.system(size: 13, weight: .semibold))
                            Text("\(session.utteranceCount) utterances \u{00B7} \(session.durationDisplay)")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([session.filePath])
                        } label: {
                            Label("Show in Finder", systemImage: "folder")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button(role: .destructive) {
                            sessionToDelete = session
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)

                    Divider()

                    if isLoadingContent {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            Text(sessionContent)
                                .font(.system(size: 12, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                        }
                    }
                }
                .onChange(of: selectedSession) {
                    loadContent(for: session)
                }
                .onAppear {
                    loadContent(for: session)
                }
            } else {
                emptyStateView(message: "Select a session to view its transcript")
            }
        }
    }

    // MARK: - Helpers

    private func emptyStateView(message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func reloadSessions() {
        let dir = URL(fileURLWithPath: settings.notesFolderPath)
        store.load(from: dir)
    }

    private func loadContent(for session: TranscriptSession) {
        isLoadingContent = true
        sessionContent = ""
        Task {
            let content = await store.loadContent(for: session)
            sessionContent = content
            isLoadingContent = false
        }
    }
}
