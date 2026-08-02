import SwiftUI

/// Notes browsing: folders sidebar + notes list + single-note editor.
struct NotesSectionView: View {
    var body: some View {
        HStack(spacing: 0) {
            NotesSidebarView()
            Rectangle()
                .fill(.secondary.opacity(0.2))
                .frame(width: 1)
            NoteEditorView()
        }
    }
}
