#!/usr/bin/env node

const https = require('https');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { execSync } = require('child_process');
const os = require('os');

const VERSION = '1.0.16';
const REPO = 'yarin-mag/BetterClip';
const DMG_URL = `https://github.com/${REPO}/releases/download/v${VERSION}/BetterClip-${VERSION}.dmg`;
const TEMP_DIR = path.join(os.tmpdir(), 'betterclip-install');
const DMG_PATH = path.join(TEMP_DIR, 'BetterClip.dmg');
const MOUNT_POINT = path.join(TEMP_DIR, 'mount');
const APP_PATH = '/Applications/BetterClip.app';
const CHECKSUM_URL = `https://github.com/${REPO}/releases/download/v${VERSION}/BetterClip-${VERSION}.dmg.sha256`;
const CHECKSUM_PATH = path.join(TEMP_DIR, 'BetterClip.dmg.sha256');
const ALLOWED_HOSTS = new Set([
  'github.com',
  'objects.githubusercontent.com',
  'release-assets.githubusercontent.com',
  'codeload.github.com'
]);

function validateDownloadUrl(url) {
  const parsed = new URL(url);
  if (parsed.protocol !== 'https:' || !ALLOWED_HOSTS.has(parsed.hostname)) {
    throw new Error(`Download from untrusted URL blocked: ${url}`);
  }
  return parsed;
}

async function downloadFile(url, dest, depth = 0) {
  if (depth > 5) {
    throw new Error(`Too many redirects (>5) when downloading ${url}`);
  }
  validateDownloadUrl(url);
  return new Promise((resolve, reject) => {
    const file = fs.createWriteStream(dest);
    https.get(url, (response) => {
      if ([301, 302, 303, 307, 308].includes(response.statusCode)) {
        file.close();
        const location = response.headers.location;
        if (!location) {
          return reject(new Error('Redirect received with no Location header'));
        }
        let redirectUrl;
        try {
          redirectUrl = new URL(location, url).toString();
          validateDownloadUrl(redirectUrl);
        } catch {
          return reject(new Error(`Invalid redirect URL: ${location}`));
        }
        return downloadFile(redirectUrl, dest, depth + 1).then(resolve, reject);
      }
      if (response.statusCode !== 200) {
        file.close();
        return reject(new Error(`Download failed with HTTP ${response.statusCode}: ${url}`));
      }
      response.pipe(file);
      file.on('finish', () => {
        file.close();
        resolve();
      });
    }).on('error', (err) => {
      file.close();
      reject(err);
    });
  });
}

function verifyChecksum(filePath, checksumFilePath) {
  const checksumFileContent = fs.readFileSync(checksumFilePath, 'utf8').trim();
  const expectedHash = checksumFileContent.split(/\s+/)[0].toLowerCase();
  if (!/^[a-f0-9]{64}$/.test(expectedHash)) {
    throw new Error(`Malformed checksum file: expected a 64-char hex digest, got: "${expectedHash}"`);
  }
  const fileBuffer = fs.readFileSync(filePath);
  const actualHash = crypto.createHash('sha256').update(fileBuffer).digest('hex');
  if (actualHash !== expectedHash) {
    throw new Error(
      `DMG integrity check FAILED.\n  Expected: ${expectedHash}\n  Actual:   ${actualHash}\n` +
      `The download may have been tampered with. Aborting installation.`
    );
  }
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

    console.log('🔒 Verifying integrity...');
    await downloadFile(CHECKSUM_URL, CHECKSUM_PATH);
    verifyChecksum(DMG_PATH, CHECKSUM_PATH);
    console.log('✅ Integrity verified\n');

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

if (require.main === module) {
  install();
}

module.exports = {
  VERSION,
  validateDownloadUrl,
  verifyChecksum
};
