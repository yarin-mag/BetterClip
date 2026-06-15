const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');

const { validateDownloadUrl, verifyChecksum } = require('../bin/install');

test('accepts GitHub release asset download hosts', () => {
  assert.doesNotThrow(() => validateDownloadUrl('https://github.com/yarin-mag/BetterClip/releases'));
  assert.doesNotThrow(() => validateDownloadUrl('https://release-assets.githubusercontent.com/file'));
});

test('rejects non-HTTPS and untrusted download hosts', () => {
  assert.throws(() => validateDownloadUrl('http://github.com/file'), /untrusted URL/);
  assert.throws(() => validateDownloadUrl('https://example.com/file'), /untrusted URL/);
});

test('verifies a matching SHA-256 checksum and rejects mismatches', () => {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'betterclip-test-'));
  const file = path.join(tempDir, 'asset.dmg');
  const checksum = path.join(tempDir, 'asset.dmg.sha256');
  const contents = Buffer.from('verified release asset');
  const digest = crypto.createHash('sha256').update(contents).digest('hex');

  try {
    fs.writeFileSync(file, contents);
    fs.writeFileSync(checksum, `${digest}  asset.dmg\n`);
    assert.doesNotThrow(() => verifyChecksum(file, checksum));

    fs.writeFileSync(checksum, `${'0'.repeat(64)}  asset.dmg\n`);
    assert.throws(() => verifyChecksum(file, checksum), /integrity check FAILED/);
  } finally {
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
});

test('rejects malformed checksum files', () => {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'betterclip-test-'));
  const file = path.join(tempDir, 'asset.dmg');
  const checksum = path.join(tempDir, 'asset.dmg.sha256');

  try {
    fs.writeFileSync(file, 'asset');
    fs.writeFileSync(checksum, `${'z'.repeat(64)}  asset.dmg\n`);
    assert.throws(() => verifyChecksum(file, checksum), /Malformed checksum file/);
  } finally {
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
});
