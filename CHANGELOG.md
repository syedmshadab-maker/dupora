# Changelog

All notable changes to this project are documented here.

## [Unreleased] - 2026-08-11 - Production-readiness audit

A dedicated audit pass: full repository review for unfinished/unsafe code,
rerunning the entire quality gate, completing the Windows release build
(MSVC installed, real `flutter build windows --release`), and driving the
actual compiled executable through `integration_test` rather than only
testing the engine in isolation.

### Fixed

- **FFI panic/undefined-behavior gap** in the Android SAF incremental
  hasher (`rust/src/ffi/stream_hasher.rs`): two of its four `extern "C"`
  functions weren't wrapped in `catch_unwind` and could panic-and-unwind
  across the FFI boundary after a lock-poisoning cascade. Fixed with a
  poison-recovering lock plus consistent `catch_unwind` coverage.
- **Unhandled scan-failure exception** could leave the UI stuck on the
  Scanning screen forever with no recovery. `AppController.startScan()`
  now catches and surfaces failures via a dismissible error banner; also
  fixed `lastError` being captured for a different failure case but never
  actually displayed anywhere.
- **Weak pre-delete identity check**: `SafeDeleteCoordinator` checked file
  size only; a same-size replacement file at the same path could have
  slipped through. Now also checks modification time. Added 9 dedicated
  tests for this previously-untested safety-critical path.
- **Unbounded stale-cache growth**: cache rows for deleted files were
  never pruned. Added `HashCacheRepository.pruneMissing`, run once per
  scan after discovery.
- Added a reentrancy guard against double-tapping "Start Scan."

### Added

- `integration_test/dataset_test.dart`: a controlled real-world dataset
  (identical files under different names/directories, same-size-different-
  content, zero-byte, a 3 MiB mmap-path pair, a genuinely locked/
  inaccessible file, incremental rescan) run against the real compiled
  Windows executable.
- `integration_test/stress_test.dart`: 5,000 files / 400 duplicate groups
  against the real exe, with real measured wall-clock timing, real process
  memory (`ProcessInfo.currentRss`), a measured cache-speedup factor, and
  cancellation under load - see PERFORMANCE.md for the numbers.
- `test/features/deletion/safe_delete_service_test.dart` (9 tests) and
  4 new `HashCacheRepository.pruneMissing` tests.

### Verified (this pass)

- Windows: MSVC Build Tools installed in this environment; `flutter build
  windows --release` produces a working `dupora.exe` with
  `dupora_engine.dll` bundled; driven end-to-end via `integration_test`
  covering every item on the audit's Windows checklist (storage detection,
  folder selection, scan, duplicate detection, BLAKE3, progress,
  cancellation, cache, result grouping, smart selection, Recycle Bin
  deletion) plus two full process restarts confirming
  `dupora_cache.sqlite` persists correctly on disk.
- Android: release APK builds cleanly; `aapt2 dump` confirms
  `libdupora_engine.so`, the adaptive launcher icon
  (`mipmap/ic_launcher{,_background,_foreground}`), and the
  `com.dupora.dupora` package are all correctly present (resource names
  are shrinker-obfuscated in release builds, which is expected - `aapt2`
  resolves them properly regardless). No device/emulator was available in
  this environment, so on-device runtime behavior remains unverified -
  stated plainly, not claimed.
- macOS/Linux: unchanged from the previous verification pass - code-
  complete, host-unverified. No such hardware exists in this environment.

## [1.0.0] - 2026-08-10

### Added

**Native engine (Rust)**
- Streaming BLAKE3 hashing with adaptive buffered/mmap/parallel strategy.
- Stage 2 partial fingerprint (head + tail + length).
- Cooperative cancellation and native-memory progress reporting for FFI callers.
- Incremental (chunked) hasher for byte streams that don't originate from a
  filesystem path (Android SAF).
- Hand-rolled C ABI (`rust/src/ffi/`), documented as a deviation from the
  originally-suggested `flutter_rust_bridge` - see ARCHITECTURE.md.

**Scanning pipeline (Dart)**
- Stage 0 file discovery on a dedicated isolate: symlink-loop guard,
  per-entry error isolation, real hidden/system attribute detection on
  Windows.
- Pure, unit-testable Stage 1/2/3 duplicate-detection funnel.
- Bounded, persistent isolate worker pool for hashing (never unbounded).
- `ScanEngine` orchestrator: throttled progress stream, pause/resume,
  cooperative cancellation.

**Persistence**
- Drift/SQLite hash cache with identity-based validity (size + mtime +
  device ID + algorithm version), auto-invalidating on mismatch, enabling
  incremental rescans.
- Settings persisted via `shared_preferences`.

**Storage detection**
- Windows: real volume enumeration via Win32 (`GetLogicalDrives`,
  `GetDriveType`, `GetDiskFreeSpaceEx`, `GetVolumeInformation`).
- macOS/Linux: written against documented platform conventions
  (`/Volumes`, `/proc/mounts`), host-unverified (no such hardware
  available during this build).
- Android: `StorageManager`-based volume listing plus a full SAF bridge
  (tree picking, persisted permissions, document listing, chunked
  streaming reads into the Rust hasher), device-unverified.

**Deletion**
- Windows: real Recycle Bin via `SHFileOperationW` (`FOF_ALLOWUNDO`).
- macOS: `FileManager.trashItem` via a Swift `MethodChannel`, host-unverified.
- Linux: `gio trash` with a freedesktop.org Trash-spec fallback,
  host-unverified (fallback formatting logic is unit-tested in isolation).
- Android: `DocumentsContract.deleteDocument` (permanent; no SAF trash
  exists), device-unverified.
- `SafeDeleteCoordinator`: pre-delete existence/size verification,
  protected-location refusal, keep-file backstop, duplicate-request guard.

**UI**
- Home (storage/folder selection), Scan (live progress), Results
  (duplicate groups, smart selection, delete flow with trash/permanent-delete
  aware confirmation), Settings screens.
- Real image thumbnails (pure-Dart decode/resize, disk+memory cache) with
  category-icon fallback for video/audio/PDF/document/archive/other.

**Testing**
- 24 Rust tests: unit tests, official BLAKE3 golden vectors, adversarial
  cases.
- 48 Dart tests: pure-logic unit tests, real in-memory-database integration
  tests, a full-pipeline end-to-end suite against real files and the real
  native engine, and widget tests.

**Documentation**
- README, ARCHITECTURE, BUILD, TESTING, PERFORMANCE, SECURITY, this
  CHANGELOG.

### Fixed
- A `ReceivePort`-never-completes hang in `ScanEngine.start()`'s discovery
  loop that made every scan hang forever after Stage 0 finished. Caught by
  the first full-pipeline integration test; see TESTING.md.

### Known limitations
See README.md's "Known Limitations" section - primarily: no MSVC toolchain
available in the build environment (blocks a literal `flutter build
windows` release exe), no macOS/Linux/Android hardware available to
exercise those platforms' native code paths, and no dedicated `criterion`
throughput benchmark harness.
