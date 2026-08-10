# Changelog

All notable changes to this project are documented here. This is the
initial build, so everything below is v1.0.0.

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
