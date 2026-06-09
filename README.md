# BetterClip

A native macOS menu-bar clipboard manager with searchable history, saved snippets, and a global hotkey panel.

## Features

- Clipboard history with FTS5 full-text search
- Text, image, RTF, URL, and file clip types with blob deduplication
- Snippet library with folders and a snippet manager window
- Global **⌘⇧V** hotkey to open the panel from anywhere
- Compact, full, and popover layout modes
- Auto-paste into the previously focused application
- Launch at login and configurable history limits

## Installation

### Homebrew (Recommended)

```bash
brew tap yarin-mag/betterclip
brew install betterclip
```

To upgrade:
```bash
brew upgrade betterclip
```

### npm

```bash
npm install -g @betterclip/betterclip
```

### Manual

Download the latest `.dmg` from [GitHub Releases](https://github.com/yarin-mag/BetterClip/releases), mount it, and drag `BetterClip.app` to `/Applications`.

## Requirements

- macOS 14.0+
- Xcode 15+ (for development)

## Build

```bash
xcodegen generate
xcodebuild build -project BetterClip.xcodeproj -scheme BetterClip -destination 'platform=macOS'
```

## Documentation

- Design spec: `docs/superpowers/specs/2026-06-08-betterclip-design.md`
- Implementation plan: `docs/superpowers/plans/2026-06-08-betterclip-implementation.md`

## License

Personal project.