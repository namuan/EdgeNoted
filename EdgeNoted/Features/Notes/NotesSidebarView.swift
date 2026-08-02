import SwiftData
import SwiftUI

/// Folders and notes list. Pins, colors, and fold state come from local
/// SwiftData metadata; note names come live from Apple Notes.
struct NotesSidebarView: View {
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Query private var folderMetas: [FolderMeta]
    @Query private var noteMetas: [NoteMeta]

    private var isSearching: Bool {
        !appState.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            folderList
            Rectangle()
                .fill(.secondary.opacity(0.2))
                .frame(height: 1)
            noteList
        }
        .frame(width: 210)
    }

    // MARK: Folders

    private var folderList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                folderRow(name: nil, title: "All Notes", colorHex: nil, isPinned: false)
                ForEach(sortedFolders) { folder in
                    let meta = folderMetas.first { $0.folderID == folder.id }
                    folderRow(
                        name: folder.name,
                        title: folder.name,
                        colorHex: meta?.colorHex,
                        isPinned: meta?.isPinned == true
                    )
                    .contextMenu {
                        Button(meta?.isPinned == true ? "Unpin" : "Pin") {
                            MetaStore.setFolderPinned(meta?.isPinned != true, folderID: folder.id, in: modelContext)
                        }
                        colorMenu(title: "Folder Color") { hex in
                            MetaStore.setFolderColor(hex, folderID: folder.id, in: modelContext)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .frame(height: 140)
    }

    private func folderRow(name: String?, title: String, colorHex: String?, isPinned: Bool) -> some View {
        let selected = appState.selectedFolderName == name
        return Button {
            appState.selectFolder(name)
        } label: {
            HStack(spacing: 6) {
                if let color = AppColor.color(forHex: colorHex ?? "") {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: 4, height: 12)
                } else {
                    Image(systemName: "folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(title)
                    .lineLimit(1)
                    .font(.callout)
                Spacer(minLength: 0)
                if isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selected ? settings.activeTheme().accentColor.opacity(0.18) : Color.clear,
                in: RoundedRectangle(cornerRadius: 5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var sortedFolders: [NotesFolder] {
        appState.folders.sorted { lhs, rhs in
            let lhsPinned = folderMetas.first { $0.folderID == lhs.id }?.isPinned == true
            let rhsPinned = folderMetas.first { $0.folderID == rhs.id }?.isPinned == true
            if lhsPinned != rhsPinned { return lhsPinned }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    // MARK: Notes

    private var noteList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(sortedNotes) { note in
                    noteRow(note)
                }
            }
            .padding(.vertical, 4)
        }
        .overlay {
            if appState.isLoading && appState.notesList.isEmpty && !isSearching {
                ProgressView()
            } else if sortedNotes.isEmpty && !appState.isLoading {
                ContentUnavailableView(
                    isSearching ? "No results" : "No notes",
                    systemImage: "note.text",
                    description: Text(isSearching ? "Try a different search." : "Press ⌘N to create one.")
                )
            }
        }
    }

    private func noteRow(_ note: NoteSummary) -> some View {
        let meta = noteMetas.first { $0.noteID == note.id }
        let selected = appState.selectedNoteID == note.id
        let theme = settings.activeTheme()

        return Button {
            appState.selectNote(note.id)
        } label: {
            HStack(spacing: 6) {
                if let color = AppColor.color(forHex: meta?.colorHex ?? "") {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: 4, height: 14)
                }
                Text(note.name)
                    .lineLimit(1)
                    .font(.callout)
                    .foregroundStyle(selected ? theme.textColor : theme.secondaryColor)
                Spacer(minLength: 0)
                if meta?.isPinned == true {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(theme.secondaryColor)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selected ? theme.accentColor.opacity(0.18) : Color.clear,
                in: RoundedRectangle(cornerRadius: 5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(meta?.isPinned == true ? "Unpin" : "Pin") {
                MetaStore.setNotePinned(
                    meta?.isPinned != true,
                    noteID: note.id,
                    folderID: appState.selectedFolderName ?? "",
                    in: modelContext
                )
            }
            Button(meta?.isFolded == true ? "Expand Note" : "Fold Note") {
                MetaStore.setNoteFolded(
                    meta?.isFolded != true,
                    noteID: note.id,
                    folderID: appState.selectedFolderName ?? "",
                    in: modelContext
                )
            }
            colorMenu(title: "Note Color") { hex in
                MetaStore.setNoteColor(
                    hex,
                    noteID: note.id,
                    folderID: appState.selectedFolderName ?? "",
                    in: modelContext
                )
            }
        }
    }

    private var sortedNotes: [NoteSummary] {
        let source = isSearching ? appState.searchResults : appState.notesList
        return source.sorted { lhs, rhs in
            let lhsMeta = noteMetas.first { $0.noteID == lhs.id }
            let rhsMeta = noteMetas.first { $0.noteID == rhs.id }
            if lhsMeta?.isPinned != rhsMeta?.isPinned { return lhsMeta?.isPinned == true }
            let lhsIndex = lhsMeta?.orderIndex ?? Int.max
            let rhsIndex = rhsMeta?.orderIndex ?? Int.max
            if lhsIndex != rhsIndex { return lhsIndex < rhsIndex }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    // MARK: Shared

    private func colorMenu(title: String, apply: @escaping (String?) -> Void) -> some View {
        Menu(title) {
            ForEach(AppColor.noteColors, id: \.name) { item in
                Button {
                    apply(item.hex.isEmpty ? nil : item.hex)
                } label: {
                    if item.hex.isEmpty {
                        Text(item.name)
                    } else {
                        Label(item.name, systemImage: "circle.fill")
                            .foregroundStyle(AppColor.color(forHex: item.hex) ?? .secondary)
                    }
                }
            }
        }
    }
}
