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
    @State private var error: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(existingSnippet == nil ? "New Snippet" : "Edit Snippet")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Name").font(.subheadline).foregroundStyle(.secondary)
                TextField("e.g. Email signature", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Content").font(.subheadline).foregroundStyle(.secondary)
                TextEditor(text: $content)
                    .font(.system(size: 13, design: .monospaced))
                    .frame(minHeight: 120)
                    .border(Color.secondary.opacity(0.3))
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
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        do {
            if var existing = existingSnippet {
                existing.name = trimmedName
                existing.content = content
                try SnippetStore.shared.update(existing)
            } else {
                _ = try SnippetStore.shared.createSnippet(
                    name: trimmedName, content: content, folderId: folderId)
            }
            onSave?()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
