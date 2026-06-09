# npm BetterClip Installer

This is an npm package that downloads and installs BetterClip for macOS.

## Installation

```bash
npm install -g @betterclip/betterclip
```

Or with yarn:

```bash
yarn global add @betterclip/betterclip
```

## What it does

1. ✅ Downloads the latest BetterClip DMG from GitHub Releases
2. ✅ Mounts the DMG
3. ✅ Copies BetterClip.app to /Applications
4. ✅ Cleans up temporary files
5. ✅ Shows helpful tips

## Usage

```bash
# Start the app
open -a BetterClip

# Or use npm to launch
betterclip
```

## System Requirements

- macOS 14.0 or later
- Node.js 14+
- npm 6+

## Troubleshooting

**"Permission denied" when running installer**
```bash
sudo npm install -g betterclip
```

**DMG won't mount**
- Check your internet connection
- Verify the release exists on GitHub

**App won't launch**
```bash
# Grant execute permissions
chmod +x /Applications/BetterClip.app/Contents/MacOS/BetterClip

# Try launching again
open -a BetterClip
```

## Uninstall

```bash
rm -rf /Applications/BetterClip.app
npm uninstall -g @betterclip/betterclip
```

## More Info

See the [main repository](https://github.com/yarin-mag/BetterClip) for docs and source code.
