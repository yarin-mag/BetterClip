// BetterClip/Core/Preferences.swift
import Foundation

enum LayoutMode: String, CaseIterable {
    case compact = "compact"
    case full = "full"
    case popover = "popover"

    var displayName: String {
        switch self {
        case .compact: return "Compact (list only)"
        case .full:    return "Full (list + preview)"
        case .popover: return "Popover (menu bar)"
        }
    }
}

final class Preferences {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    var layoutMode: LayoutMode {
        get { LayoutMode(rawValue: defaults.string(forKey: "layoutMode") ?? "") ?? .full }
        set { defaults.set(newValue.rawValue, forKey: "layoutMode") }
    }

    var historyLimit: Int {
        get {
            let v = defaults.integer(forKey: "historyLimit")
            return v > 0 ? v : 200
        }
        set { defaults.set(newValue, forKey: "historyLimit") }
    }

    var maxImageSizeMB: Int {
        get {
            let v = defaults.integer(forKey: "maxImageSizeMB")
            return v > 0 ? v : 10
        }
        set { defaults.set(newValue, forKey: "maxImageSizeMB") }
    }

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: "launchAtLogin") }
        set { defaults.set(newValue, forKey: "launchAtLogin") }
    }

    var autoPasteAndClose: Bool {
        get {
            let exists = defaults.object(forKey: "autoPasteAndClose") != nil
            return exists ? defaults.bool(forKey: "autoPasteAndClose") : false
        }
        set { defaults.set(newValue, forKey: "autoPasteAndClose") }
    }
}
