// BetterClip/UI/Snippets/SnippetEditorView.swift
import SwiftUI

struct SnippetEditorView: View {
    @Environment(\.dismiss) private var dismiss

    var existingSnippet: Snippet? = nil
    var prefillContent: String = ""
    var folderId: Int64? = nil
    var onSave: (() -> Void)? = nil

    @State private var name: String = ""
    @State private var content: String = ""
    @State private var selectedFolderId: Int64? = nil
    @State private var folders: [SnippetFolder] = []
    @State private var error: String? = nil
    @FocusState private var focusedField: Field?

    private enum Field { case name, content }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(existingSnippet == nil ? "New Snippet" : "Edit Snippet")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Name").font(.subheadline).foregroundStyle(.secondary)
                TextField("e.g. Email signature", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .name)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Content").font(.subheadline).foregroundStyle(.secondary)
                TextEditor(text: $content)
                    .font(.system(size: 13, design: .monospaced))
                    .frame(minHeight: 120)
                    .border(Color.secondary.opacity(0.3))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Folder").font(.subheadline).foregroundStyle(.secondary)
                Picker("", selection: $selectedFolderId) {
                    Text("No Folder").tag(Optional<Int64>.none)
                    ForEach(folders) { folder in
                        Text(folder.name).tag(folder.id)
                    }
                }
                .labelsHidden()
            }

            if let error {
                Text(error).foregroundStyle(.red).font(.caption)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.escape)
                Button("Save") { save() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear {
            name = existingSnippet?.name ?? ""
            content = existingSnippet?.content ?? prefillContent
            folders = (try? SnippetStore.shared.folders()) ?? []
            let initialFolderId = existingSnippet?.folderId ?? folderId
            // A deleted folder has no Picker row; show "No Folder" rather than a blank picker.
            selectedFolderId = folders.contains { $0.id == initialFolderId } ? initialFolderId : nil
            DispatchQueue.main.async {
                focusedField = .name
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        do {
            if var existing = existingSnippet {
                existing.name = trimmedName
                existing.content = content
                existing.folderId = selectedFolderId
                try SnippetStore.shared.update(existing)
            } else {
                _ = try SnippetStore.shared.createSnippet(
                    name: trimmedName, content: content, folderId: selectedFolderId)
            }
            onSave?()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
