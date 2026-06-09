# Homebrew Tap Setup

This guide explains how to set up BetterClip as a Homebrew tap for distribution.

## Step 1: Create a New Repository

Create a new GitHub repository named `homebrew-betterclip` under your account (yarin-mag).

```bash
mkdir homebrew-betterclip
cd homebrew-betterclip
git init
```

## Step 2: Create the Tap Structure

```
homebrew-betterclip/
├── Formula/
│   └── betterclip.rb
└── README.md
```

## Step 3: Add the Formula File

Copy `Formula/betterclip.rb` from this repo to your new tap repo.

Update the SHA256 hash with the actual hash of your latest .dmg:

```bash
# Get the hash:
shasum -a 256 BetterClip.dmg
```

## Step 4: Create README

```markdown
# homebrew-betterclip

Homebrew tap for BetterClip.

## Installation

```bash
brew tap yarin-mag/betterclip
brew install betterclip
```

## Usage

```bash
betterclip   # Start the app
open -a BetterClip
```

Global hotkey: ⌘⇧V
```

## Step 5: Commit and Push

```bash
git add .
git commit -m "Initial tap setup"
git push -u origin main
```

## Installation Instructions for Users

Once the tap is set up, users can install with:

```bash
brew tap yarin-mag/betterclip
brew install betterclip
```

Or, to upgrade an existing installation:

```bash
brew upgrade betterclip
```

## Updating the Formula

Each time you release a new version:

1. Update version number in `Formula/betterclip.rb`
2. Update the URL with new tag
3. Update SHA256:
   ```bash
   shasum -a 256 ~/Downloads/BetterClip.dmg
   ```
4. Commit and push

The formula will automatically pull the latest DMG from GitHub Releases.

## Future: Submitting to Homebrew Core

Once BetterClip is more established, you can submit to the main Homebrew repository:

1. Create a PR to https://github.com/Homebrew/homebrew-core
2. This allows users to do: `brew install betterclip` (without the tap)
3. Requires community review but increases discoverability

For now, the custom tap is perfect for distribution!
