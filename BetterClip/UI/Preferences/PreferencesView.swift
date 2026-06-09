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
    }
}
