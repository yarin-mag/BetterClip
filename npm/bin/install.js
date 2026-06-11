#!/usr/bin/env node

const https = require('https');
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const os = require('os');

const VERSION = '1.0.2';
const REPO = 'yarin-mag/BetterClip';
const DMG_URL = `https://github.com/${REPO}/releases/download/v${VERSION}/BetterClip-${VERSION}.dmg`;
const TEMP_DIR = path.join(os.tmpdir(), 'betterclip-install');
const DMG_PATH = path.join(TEMP_DIR, 'BetterClip.dmg');
const MOUNT_POINT = path.join(TEMP_DIR, 'mount');
const APP_PATH = '/Applications/BetterClip.app';

async function downloadFile(url, dest) {
  return new Promise((resolve, reject) => {
    const file = fs.createWriteStream(dest);
    https.get(url, (response) => {
      if (response.statusCode === 302 || response.statusCode === 301) {
        file.close();
        return downloadFile(response.headers.location, dest).then(resolve, reject);
      }
      response.pipe(file);
      file.on('finish', () => {
        file.close();
        resolve();
      });
    }).on('error', reject);
  });
}

async function install() {
  try {
    console.log('🍎 BetterClip Installer\n');

    // Check macOS
    if (process.platform !== 'darwin') {
      console.error('❌ BetterClip requires macOS');
      process.exit(1);
    }

    // Create temp directory
    if (!fs.existsSync(TEMP_DIR)) {
      fs.mkdirSync(TEMP_DIR, { recursive: true });
    }

    console.log(`📥 Downloading BetterClip v${VERSION}...`);
    await downloadFile(DMG_URL, DMG_PATH);
    console.log('✅ Downloaded\n');

    // Check if app already exists
    if (fs.existsSync(APP_PATH)) {
      console.log(`📦 BetterClip already installed at ${APP_PATH}`);
      console.log(`To update, uninstall first: rm -rf ${APP_PATH}`);
      cleanup();
      process.exit(0);
    }

    // Mount DMG
    console.log('🔧 Mounting DMG...');
    if (!fs.existsSync(MOUNT_POINT)) {
      fs.mkdirSync(MOUNT_POINT, { recursive: true });
    }
    execSync(`hdiutil attach "${DMG_PATH}" -mountpoint "${MOUNT_POINT}" -nobrowse`, {
      stdio: 'pipe'
    });
    console.log('✅ Mounted\n');

    // Copy app
    console.log('📋 Installing to /Applications...');
    const srcApp = path.join(MOUNT_POINT, 'BetterClip.app');
    if (!fs.existsSync(srcApp)) {
      throw new Error('BetterClip.app not found in DMG');
    }
    execSync(`cp -r "${srcApp}" "${APP_PATH}"`, { stdio: 'pipe' });
    console.log('✅ Installed\n');

    // Unmount
    console.log('🧹 Cleaning up...');
    execSync(`hdiutil detach "${MOUNT_POINT}"`, { stdio: 'pipe' });
    cleanup();
    console.log('✅ Done\n');

    console.log('🎉 BetterClip is ready!\n');
    console.log('Start with: open -a BetterClip');
    console.log('Global hotkey: ⌘⇧V (Command+Shift+V)\n');
    console.log('📖 Tips:');
    console.log('  • Launch at login: Preferences → General → "Launch at login"');
    console.log('  • Clear history: Preferences → "History & Privacy"\n');

  } catch (error) {
    console.error('❌ Installation failed:', error.message);
    cleanup();
    process.exit(1);
  }
}

function cleanup() {
  try {
    if (fs.existsSync(TEMP_DIR)) {
      fs.rmSync(TEMP_DIR, { recursive: true, force: true });
    }
  } catch (e) {
    // Ignore cleanup errors
  }
}

install();
