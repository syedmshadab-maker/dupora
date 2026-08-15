# Changelog

All notable changes to this project are documented here.

## [Unreleased] - Windows deletion/runtime safety hardening

A reliability/safety pass over the deletion pipeline, cache startup,
thumbnail lifecycle, and scan runtime - no new features, no platform or
version changes.

### Fixed

- `AppController` could call `notifyListeners()` after `dispose()` from an
  async continuation (e.g. a batch delete still in flight when the widget
  tree is torn down), which throws in a `ChangeNotifier`. Every async
  method now routes through a disposed-checking `_notify()` helper, and
  `dispose()` cancels the live scan-progress subscription and signals the
  in-flight `ScanEngine` to cancel rather than leaving it running
  unobserved.
- **A completed scan no longer preselects anything for deletion.**
  `startScan()` previously called `_applyDefaultSelection()` immediately
  after every scan, marking most duplicates for deletion before the user
  had done anything. The required flow is Scan -> review -> explicit
  Smart Select (or manual per-file selection) -> review -> explicit delete
  confirmation; `_applyDefaultSelection()` is removed, and `keepFileFor()`
  still computes the "keep" candidate on demand for the UI's star
  indicator without touching the selection set.
- `HashCacheDatabase.open()` had no error handling at all; a corrupted,
  schema-mismatched, or locked cache file would throw uncaught during app
  startup. It now verifies the database with a real query immediately
  after opening, quarantines an unusable file and rebuilds a fresh cache
  in its place, and falls back to an in-memory database (app still fully
  usable, just without cache persistence this session) if even that
  fails.
- `ThumbnailService.getThumbnail()` had no cancellation support and
  decoded images synchronously on the calling isolate. It now accepts an
  optional `ThumbnailCancelToken` (checked at each await boundary so a
  scrolled-away tile's in-flight request stops doing further unnecessary
  work) and offloads decoding to a separate isolate via `Isolate.run` so a
  large or hostile image can't block the caller.
- `WindowsDeleter`/`SafeDeleteCoordinator` previously classified every
  `SHFileOperationW` failure as one generic `failed` outcome. Two new
  outcomes, `locked` and `permissionDenied`, are now derived from a
  documented Win32 error-code probe (`ERROR_SHARING_VIOLATION` /
  `ERROR_LOCK_VIOLATION` / `ERROR_ACCESS_DENIED`) rather than guessing
  from `SHFileOperationW`'s own legacy `DE_*` return codes.
- `ScanEngine.start()` allocated its `CancelSignal` and constructed the
  worker pool before the `try`/`finally` that shuts the pool down and
  frees that native memory; a worker-isolate spawn failure would leak
  both. Both are now inside the `try`.
- `ProtectedLocations` did not protect a portable (non-installed) build's
  own directory, only an installed copy under `Program Files`/
  `LOCALAPPDATA`. It now also protects `dirname(Platform.resolvedExecutable)`.

### Added

- Structured logging (`package:logging`, routed to `debugPrint`) for
  handled-but-notable failures: cache recovery, volume enumeration, scan
  failures.
- Real, non-mocked adversarial tests: a locked-file delete via a genuine
  exclusive Win32 handle, a read-only-file delete, a directory
  junction/reparse-point escape attempt (default-blocked, opt-in via
  `followSymlinks`), cache corruption recovery against a real corrupt
  SQLite file, Unicode/spaced filenames, a 100-file duplicate group, a
  near-MAX_PATH-length file, and a Rust-panic-across-FFI-boundary proof.
  The Windows integration stress test now covers 10,000 files (600
  duplicate groups) and adds a real Recycle-Bin batch-delete phase.

## [Unreleased] - Windows-only refactor

Dupora is now an intentionally Windows-only application (Windows 10/11
x64). This is a scope pivot, not a regression: the Android, macOS, and
Linux app targets added and verified in earlier releases (see the [1.1.0]
entry below) are removed rather than left to bit-rot unmaintained.

### Removed

- `android/`, `macos/`, `linux/` platform directories and their
  `branding/{android,macos,linux}/` assets.
- Per-platform storage detectors and deleters:
  `safe_delete_{android,linux,macos}.dart`,
  `storage_detector_{android,linux,macos}.dart`.
- Android Storage Access Framework (SAF) support: `saf_bridge.dart`, the
  Kotlin `SafChannel`, and the SAF-only incremental-hashing FFI path
  (`IncrementalHasher` in `hash_engine.dart`, the `streamHasher*` bindings,
  and `rust/src/ffi/stream_hasher.rs`) - this path existed solely to hash
  bytes streamed from SAF documents, which no longer applies once the
  Android app is gone.
- `integration_test/{linux,macos}_native_engine_test.dart`,
  `test/features/deletion/safe_delete_linux_test.dart`,
  `test/features/storage/data/storage_detector_linux_test.dart`.
- `build-android`, `build-macos`, `build-linux` jobs from
  `.github/workflows/ci.yml` and `.github/workflows/release.yml`; the
  release workflow now only builds and publishes Windows artifacts.

### Changed

- `PlatformDeleter.forPlatform()`, `StorageDetector.forPlatform()`,
  `ProtectedLocations._defaultRootsForPlatform()`, and
  `DuporaNativeBindings._openLibrary()` now have Windows-only bodies. The
  factory methods themselves are kept (not inlined) as a seam for a future
  Windows-native Portable Devices/MTP implementation - removing the
  Android *app* does not remove the intent to support Android
  phones/tablets connected to Windows over USB. See ARCHITECTURE.md.
- README/BUILD/TESTING/SECURITY/ARCHITECTURE/PERFORMANCE now state the
  supported platform as Windows 10/11 x64 and no longer describe
  cross-platform build/test/verification steps.

## [1.1.0] - 2026-08-11 - Linux and macOS release-ready

Linux and macOS join Windows and Android as fully release-gating,
runtime-verified platforms - `.github/workflows/release.yml` now builds,
verifies, and attaches real artifacts for all four on every tagged
release, with no `continue-on-error` anywhere in that set.

### Fixed

- **macOS wouldn't even compile**: `macos/Runner/TrashChannel.swift`
  (the Trash-deletion Swift bridge) existed in the repo but was never
  registered in `Runner.xcodeproj`'s build target, so Xcode silently
  never built it - `MainFlutterWindow.swift`'s reference to it failed
  with `cannot find 'TrashChannel' in scope`. Fixed by registering it in
  the Xcode project (PBXBuildFile/PBXFileReference/PBXGroup/
  PBXSourcesBuildPhase), the smallest correct change mirroring how every
  other Runner source file is already registered.
- **Linux release bundle never included the native BLAKE3 engine**:
  `libdupora_engine.so` was built but nothing copied it into
  `build/linux/x64/release/bundle/`, so the packaged app would have
  failed the first time it tried to hash anything.
  `linux/CMakeLists.txt` now installs it into `bundle/lib/`, mirroring
  the pattern `windows/CMakeLists.txt` already used for
  `dupora_engine.dll`; `dupora_native_bindings.dart`'s Linux loader now
  also resolves it via an explicit path relative to the running
  executable, rather than relying solely on bare `dlopen` + RPATH
  resolution.
- **macOS had the identical native-engine-bundling gap**, once it could
  compile: `libdupora_engine.dylib` (a genuine universal arm64+x86_64
  binary) wasn't embedded in the packaged `.app`.
  `macos/Runner.xcodeproj`'s previously-empty "Bundle Framework"
  copy-files build phase now embeds it into `Contents/Frameworks/`; the
  FFI loader gained the same explicit, executable-relative resolution
  strategy already used for Linux.

### Added

- `integration_test/linux_native_engine_test.dart` and
  `integration_test/macos_native_engine_test.dart`: drive the real
  compiled release bundle/app on GitHub-hosted `ubuntu-latest`/
  `macos-latest` runners (`flutter drive --profile` - Flutter Driver
  refuses `--release` entirely on desktop) - call the native engine
  directly first (proving no `DynamicLibrary.open` failure), then run a
  real scan against a controlled dataset and assert correct duplicate
  detection. No mocks. Both genuinely passed in CI (Linux: run
  31461334167, after diagnosing and fixing three real CI/test-tooling
  issues along the way, not blindly retried; macOS: run 31462917213, on
  the first attempt, applying what Linux's debugging had already
  surfaced).
- `.github/workflows/release.yml`: `build-linux` and `build-macos` now
  verify the native library is actually bundled, run the new integration
  tests, and package `Dupora-Linux-x64-vX.Y.Z.tar.gz` /
  `Dupora-macOS-vX.Y.Z.zip` for `release-publish` to attach. Neither has
  `continue-on-error` anymore, making all four platforms release-gating.

### Known limitations (honest, not silently claimed as fixed)

- macOS artifacts are not code-signed or notarized (no Apple Developer
  certificate available in this pipeline) - Gatekeeper will warn on
  first launch.
- Trash deletion (`TrashChannel.swift`) and volume detection on both
  Linux and macOS remain unexercised by these tests (which cover
  scan/hash/detect, not delete or storage enumeration) and by any real
  hardware in this project's build sessions.

## [Unreleased] - 2026-08-11 - Windows distributable installer

- Added `installer/dupora.wxs` (MSI) and `installer/bundle.wxs` (Burn
  bootstrapper `.exe`), built with WiX Toolset v5, packaging the complete
  verified `build\windows\x64\runner\Release\` tree (dupora.exe,
  dupora_engine.dll, sqlite3.dll, flutter_windows.dll, plugin DLLs, the full
  `data\` asset tree) with Start Menu/Desktop shortcuts, an Add/Remove
  Programs entry, and the Dupora icon - no source, build caches, or dev
  tooling included.
- Pivoted from Inno Setup to WiX, and from per-machine to per-user MSI
  scope, both because this build environment has no administrator rights -
  see BUILD.md's "Windows installer" section for the full detail and why
  that doesn't compromise the installer's legitimacy (per-user installs to
  `%LocalAppData%\Programs` are the same convention VS Code/Discord/Slack
  use).
- Verified for real in this environment: silent install (exit 0, all 24
  files + both shortcuts + ARP entry present), the installed exe launched
  and ran independently of `D:\DUPORA` (confirmed via its cache database
  being created at the correct per-user path), and silent uninstall (exit
  0, everything removed). Full detail in BUILD.md.
- `dist/Dupora-Portable-x64.zip` (the same Release tree, zip-and-run,
  independently verified the same way) and `dist/SHA256SUMS.txt` (installer,
  MSI, portable ZIP, release APK) were also produced.

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
