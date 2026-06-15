# BetterClip — Security, Crash & Bug Report

**Date**: 2026-06-15  
**Scope**: Full repository audit (`main` branch)  
**Audited files**: `npm/bin/install.js`, `BetterClip/Core/Database.swift`, `BetterClip/Core/BlobStore.swift`, `BetterClip/Core/ClipboardMonitor.swift`, `BetterClip/Core/PasteboardWriter.swift`, `BetterClip/App/AppDelegate.swift`

---

## Resolution Status

All findings in this report were resolved for release `v1.0.6`:

- The npm installer validates redirect destinations, limits redirect depth, rejects unsuccessful HTTP responses, and verifies the release DMG against its SHA-256 asset.
- The release workflow generates, verifies, and publishes the companion `.sha256` asset.
- Blob writes propagate failures so broken database references are not created.
- Database recovery falls back to an in-memory database instead of force-crashing.

---

## Summary

| ID | Severity | Category | File | Confidence |
|----|----------|----------|------|------------|
| VULN-1 | Medium | Supply Chain / No Integrity Check | `npm/bin/install.js:50` | 9/10 |
| VULN-2 | Medium | Unvalidated Redirect URL | `npm/bin/install.js:23` | 8/10 |
| BUG-1 | High | Data Integrity | `BetterClip/Core/BlobStore.swift:23` | 9/10 |
| CRASH-1 | Medium | Crash / Force Unwrap | `BetterClip/Core/Database.swift:15` | 7/10 |
| BUG-2 | Low | Robustness | `npm/bin/install.js:21-23` | — |

---

## Security Vulnerabilities

### VULN-1 — No integrity verification of downloaded DMG

- **File**: `npm/bin/install.js:50,66-77`
- **Severity**: Medium
- **Category**: `supply_chain`
- **Confidence**: 9/10

**Description**

The installer downloads a DMG from GitHub over HTTPS and immediately mounts and installs it without any cryptographic verification:

```js
// Line 50 — download
await downloadFile(DMG_URL, DMG_PATH);

// Lines 66-77 — mount and install with zero integrity checks
execSync(`hdiutil attach "${DMG_PATH}" -mountpoint "${MOUNT_POINT}" -nobrowse`, { stdio: 'pipe' });
execSync(`cp -r "${srcApp}" "${APP_PATH}"`, { stdio: 'pipe' });
```

No SHA-256 hash check, no `codesign -v` verification, and no pinned expected digest anywhere in the script.

**Exploit Scenario**

An attacker with network position (corporate SSL inspection proxy, compromised CA, DNS hijack with valid cert) intercepts the HTTPS request to GitHub, serves a malicious DMG, and the installer silently mounts and copies it to `/Applications`. The app runs with the installing user's permissions. This attack executes once per machine and is invisible to the victim.

**Recommendation**

Hardcode the expected SHA-256 digest of each release in the script and verify before mounting:

```js
const EXPECTED_SHA256 = 'abc123...'; // pin per VERSION

const actualHash = crypto.createHash('sha256').update(fs.readFileSync(DMG_PATH)).digest('hex');
if (actualHash !== EXPECTED_SHA256) {
  throw new Error(`DMG integrity check failed. Expected ${EXPECTED_SHA256}, got ${actualHash}`);
}
```

---

### VULN-2 — Redirect URL not validated against expected domain

- **File**: `npm/bin/install.js:21-23`
- **Severity**: Medium
- **Category**: `open_redirect / ssrf`
- **Confidence**: 8/10

**Description**

`downloadFile` follows 301/302 redirects by passing `response.headers.location` directly into a recursive call with no domain validation:

```js
if (response.statusCode === 302 || response.statusCode === 301) {
  file.close();
  return downloadFile(response.headers.location, dest).then(resolve, reject);
}
```

The redirect target is never validated against the expected domains (`github.com`, `objects.githubusercontent.com`). Node.js `https.get()` accepts any HTTPS URL, so an attacker-controlled redirect to `https://evil.com/malicious.dmg` would be silently followed.

**Exploit Scenario**

Combined with VULN-1's TLS MitM scenario: attacker intercepts the initial GitHub request and injects a `302 Location: https://attacker.com/backdoor.dmg` response. The installer transparently downloads from the attacker's server. Even without MitM, a compromised GitHub redirect rule (CDN misconfiguration) can trigger this path.

**Recommendation**

Validate the redirect target hostname before following:

```js
const allowed = ['github.com', 'objects.githubusercontent.com', 'codeload.github.com'];
const loc = new URL(response.headers.location);
if (!allowed.includes(loc.hostname)) {
  throw new Error(`Unexpected redirect to untrusted host: ${loc.hostname}`);
}
```

---

## Bugs

### BUG-1 — Silent blob write failure creates orphaned DB references (broken images)

- **File**: `BetterClip/Core/BlobStore.swift:19-26`
- **Severity**: High (data integrity)
- **Confidence**: 9/10

**Description**

`BlobStore.write()` returns the SHA-256 hash unconditionally, even if the underlying `data.write()` call silently fails via `try?`:

```swift
func write(_ data: Data) -> String {
    let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    let url = directory.appendingPathComponent(hash)
    if !FileManager.default.fileExists(atPath: url.path) {
        try? data.write(to: url, options: .atomic)  // ← silent failure
    }
    return hash  // ← returned regardless of whether write succeeded
}
```

The code comment at lines 14–15 states *"callers already handle nil gracefully"*, but callers do **not** handle this correctly. `ClipboardMonitor.poll()` stores the returned hash in a `Clip` and inserts it into the database (lines 39–40 of `ClipboardMonitor.swift`). The database row exists with a valid-looking hash, but no blob file is on disk.

**Impact**

When the user views their clipboard history, all image clips captured during a disk-full event appear as broken/missing image placeholders with no error message. The orphaned database rows persist forever. On subsequent restarts the user still sees broken images and has no way to clean them up short of clearing all history.

**Steps to reproduce**

1. Fill disk to near-capacity.
2. Copy a screenshot to clipboard.
3. Open BetterClip — the image entry appears in history as a broken placeholder.
4. Free disk space. The broken entry remains.

**Recommendation**

Propagate write errors so callers can decide whether to insert the DB record:

```swift
func write(_ data: Data) throws -> String {
    let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    let url = directory.appendingPathComponent(hash)
    if !FileManager.default.fileExists(atPath: url.path) {
        try data.write(to: url, options: .atomic)  // propagate, don't swallow
    }
    return hash
}
```

Update `ClipboardMonitor.poll()` to skip DB insertion when `BlobStore.write` throws.

---

## Crash Risks

### CRASH-1 — Force unwrap in Database singleton recovery path

- **File**: `BetterClip/Core/Database.swift:13-15`
- **Severity**: Medium
- **Confidence**: 7/10

**Description**

The singleton initializer attempts recovery from a corrupt database by deleting it and recreating it. The recreation uses `try!`, which will crash the app if it also fails:

```swift
// Recovery: corrupt or unreadable DB — delete and start fresh (history lost).
try? FileManager.default.removeItem(at: dbURL)
return try! Database(path: dbURL.path)  // ← crashes if this also fails
```

Scenarios where this crashes:
- Disk is full between the delete and the new file creation
- `~/Library/Application Support/BetterClip/` has been `chmod`-ed to read-only by the user or another process
- A sandboxed backup/security tool holds an exclusive lock on the path immediately after deletion

**Impact**

App crash at launch, unrecoverable without manual filesystem intervention. No user-facing error message is shown.

**Recommendation**

Replace `try!` with proper error handling and fall back to an in-memory database:

```swift
let fallback = (try? Database(path: dbURL.path)) ?? Database()  // in-memory fallback
return fallback
```

---

## Robustness Issues

### BUG-2 — Unbounded recursive redirect following causes stack overflow

- **File**: `npm/bin/install.js:17-31`
- **Severity**: Low
- **Category**: Robustness

`downloadFile` follows redirects via unbounded recursion with no depth limit. A redirect loop (`A → B → A`) or a server returning many chained redirects will exhaust the Node.js call stack with `RangeError: Maximum call stack size exceeded`, leaving a partially-written temp file and a mounted (but undetached) DMG directory.

**Recommendation**: Add a `depth` parameter (max 5) and throw on overflow.

---

## Areas Reviewed with No Findings

| Area | File | Result |
|------|------|--------|
| SQL injection | `Database.swift` | All queries use GRDB parameterized `arguments:` — safe |
| Path traversal (BlobStore) | `BlobStore.swift:29,33` | Hash always SHA-256 hex; can't contain `../` |
| Keyboard simulation auth | `PasteboardWriter.swift:30` | Properly gated on `AXIsProcessTrusted()` |
| Hardcoded secrets | All files | None found |
| Crypto implementation | `BlobStore.swift:20` | Standard CryptoKit SHA-256 — correct |
| Clipboard data exposure | `ClipboardMonitor.swift` | Data stored in user-owned `~/Library/Application Support` |
| XPC / IPC attack surface | All Swift files | No IPC mechanisms used |
