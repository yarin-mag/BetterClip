// BetterClip/UI/Preferences/PreferencesView.swift
import SwiftUI
import KeyboardShortcuts
import LaunchAtLogin

struct PreferencesView: View {
    @AppStorage("layoutMode")    private var layoutModeRaw = LayoutMode.full.rawValue
    @AppStorage("historyLimit")  private var historyLimit  = 200
    @AppStorage("maxImageSizeMB") private var maxImageSizeMB = 10
    @AppStorage("launchAtLogin") private var launchAtLogin = true
    @AppStorage("autoPasteAndClose") private var autoPasteAndClose = false

    @State private var showCleanHistoryConfirmation = false
    @State private var isCleaningHistory = false
    @State private var cleanHistoryResult: (clipsDeleted: Int, blobsCleaned: Int)?
    @State private var showCleanHistorySuccess = false

    private var layoutMode: Binding<LayoutMode> {
        Binding(
            get: { LayoutMode(rawValue: layoutModeRaw) ?? .full },
            set: { layoutModeRaw = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section("Panel") {
                Picker("Layout", selection: layoutMode) {
                    ForEach(LayoutMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Text("Hotkey: ⌘⇧V")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("History") {
                Stepper("Keep last \(historyLimit) items", value: $historyLimit,
                        in: 50...1000, step: 50)
                Stepper("Max image size: \(maxImageSizeMB) MB", value: $maxImageSizeMB,
                        in: 1...100, step: 5)
            }

            Section("History & Privacy") {
                Button(role: .destructive) {
                    showCleanHistoryConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("Clear All Clipboard History")
                    }
                }
                .disabled(isCleaningHistory)
                Text("Deletes clipboard history. Snippets and settings are kept safe.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { val in LaunchAtLogin.isEnabled = val }
            }

            Section("Paste Behavior") {
                Toggle("Auto-paste and close panel", isOn: $autoPasteAndClose)
                Text(autoPasteAndClose ? "Pastes automatically with ⌘V simulation" : "Just copies to clipboard; you press ⌘V manually")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 380)
        .confirmationDialog(
            "Clear Clipboard History?",
            isPresented: $showCleanHistoryConfirmation,
            presenting: ()
        ) { _ in
            Button("Clear History", role: .destructive) {
                isCleaningHistory = true
                Task {
                    do {
                        let result = try Database.shared.deleteAllClips()
                        cleanHistoryResult = result
                        showCleanHistorySuccess = true
                    } catch {
                        print("Error clearing history: \(error)")
                    }
                    isCleaningHistory = false
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: { _ in
            Text("This will delete all \(cleanHistoryResult?.clipsDeleted ?? 0) clips from your history.\n\n✓ Snippets and folders: kept\n✓ Settings: kept")
        }
        .alert("History Cleared", isPresented: $showCleanHistorySuccess) {
            Button("OK") { showCleanHistorySuccess = false }
        } message: {
            if let result = cleanHistoryResult {
                Text("Cleared \(result.clipsDeleted) clips. Snippets kept safe.")
            }
        }
    }
}
