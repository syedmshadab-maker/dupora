# Testing

## Current status

```
cargo test                                                24 / 24 passing   (rust/)
flutter test                                              61 / 61 passing   (test/)
flutter test integration_test/app_test.dart -d windows      2 / 2 passing   (real compiled exe)
flutter test integration_test/dataset_test.dart -d windows  1 / 1 passing   (real compiled exe)
flutter test integration_test/stress_test.dart -d windows   1 / 1 passing   (real compiled exe)
flutter drive --target=integration_test/linux_native_engine_test.dart
  -d linux --profile (GitHub Actions ubuntu-latest)          1 / 1 passing   (real compiled bundle)
flutter drive --target=integration_test/macos_native_engine_test.dart
  -d macos --profile (GitHub Actions macos-latest)            1 / 1 passing   (real compiled .app)
flutter analyze                                              0 issues
cargo clippy                                                   0 warnings (-D warnings)
dart format                                                    clean
cargo fmt --check                                              clean
```

Run everything yourself:

```powershell
cd rust
cargo fmt --check
cargo clippy --release --all-targets -- -D warnings
cargo test --release

cd ..
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test

# Requires a Windows build environment (MSVC) - see BUILD.md:
flutter test integration_test/app_test.dart -d windows
flutter test integration_test/dataset_test.dart -d windows
flutter test integration_test/stress_test.dart -d windows

# Requires a Linux build environment (GTK3 dev headers) plus a display -
# xvfb-run provides a virtual one on a headless CI runner. --profile, not
# --release: Flutter Driver refuses to run in release mode on desktop at
# all. See BUILD.md.
xvfb-run -a flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/linux_native_engine_test.dart -d linux --profile

# Requires a macOS build environment (Xcode) - a real GUI session exists
# on GitHub's macos-latest runners, so no xvfb-equivalent is needed. Same
# --profile reasoning as Linux. See BUILD.md.
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/macos_native_engine_test.dart -d macos --profile
```

## Rust (`rust/`)

### Unit tests (inline `#[cfg(test)]` modules)

- `src/hashing/blake3_engine.rs`: empty file, small (buffered) vs. large
  (mmap) code paths agree with the reference `blake3` crate, cancellation
  is honored mid-hash, progress reaches the full file length, a missing
  file reports `NotFound`.
- `src/hashing/partial.rs`: identical content -> identical fingerprint;
  a documented boundary case where content differing *only* in the middle
  (outside both 8KB windows) intentionally still fingerprint-matches
  (Stage 2 is a filter, not a verifier - Stage 3 is what must catch it);
  small-file-below-window hashes the whole content.
- `src/ffi/mod.rs`: an FFI round-trip call matches the direct Rust call;
  a `NotFound` status surfaces correctly; invalid UTF-8 path bytes are
  rejected with `InvalidArgument` rather than causing undefined behavior.
- `src/ffi/stream_hasher.rs`: incremental (chunked) hashing matches a
  one-shot reference hash; a finalized handle cannot be reused; abort
  discards a handle without panicking.

### `rust/tests/golden_vectors.rs`

Hashes files whose content and expected digests were downloaded verbatim
from the official BLAKE3 repository's
[`test_vectors.json`](https://github.com/BLAKE3-team/BLAKE3/blob/master/test_vectors/test_vectors.json)
(input lengths 0, 1, 63, 64, 65, 1024, 2048) and asserts our engine's output
matches byte-for-byte. This is deliberately **not** "two runs of our own
code agree with each other" - it's an independent, externally-sourced
correctness check.

### `rust/tests/adversarial.rs`

Same-size/different-content never match; different-filename/same-content
always match; zero-byte files match each other; a file large enough to
exercise the parallel `update_rayon` mmap path still matches the reference
implementation; cancellation mid-hash returns promptly; a missing file
doesn't panic; a fingerprint window that exactly equals the file size (no
overlap, no gap) doesn't panic; multi-script Unicode filenames hash
correctly.

### Why no `tempfile` crate

`rust/Cargo.toml`'s dev-dependencies intentionally exclude `tempfile`: it
transitively pulls in `getrandom` -> `windows-sys`, which needs a
`dlltool`-capable full mingw-w64 binutils to build raw-dylib import stubs.
This machine's rustup-provided GNU toolchain ships only a linker (`ld`), not
full binutils, and there is no admin access or package manager available to
install one (see BUILD.md). A ~20-line hand-rolled `TempDir` helper
(`src/test_util.rs` for unit tests, `tests/common/mod.rs` for integration
tests) replaces it rather than widening the toolchain requirement for a
convenience dependency.

## Dart (`test/`)

### Pure-logic unit tests (no isolates, no FFI, no I/O)

- `test/features/scanner/data/duplicate_funnel_test.dart` - Stage 1/2/3
  grouping functions in isolation.
- `test/features/duplicates/domain/selection_strategy_test.dart` - all four
  smart-selection strategies, and the protected-location backstop (a
  duplicate inside a protected folder is never selected for deletion even
  when the strategy would otherwise have picked it).
- `test/features/deletion/protected_locations_test.dart` - default OS
  roots are protected; ordinary user folders are explicitly verified
  *not* protected (the spec's "don't make protection so aggressive normal
  folders can't be cleaned").
- `test/features/deletion/safe_delete_linux_test.dart` - freedesktop.org
  `.trashinfo` sidecar formatting (percent-encoding, zero-padded
  timestamps), independent of a real Linux host.
- `test/features/storage/data/storage_detector_linux_test.dart` -
  `/proc/mounts` parsing against synthetic mount tables covering virtual
  filesystems, `/boot/efi` exclusion, octal-escaped mount points (e.g.
  spaces), removable-media classification, network shares, and a stat
  failure gracefully dropping a volume rather than crashing.

### Integration tests against real infrastructure

- `test/features/cache/hash_cache_repository_test.dart` - a real in-memory
  Drift/SQLite database (not mocked), covering cache-hit lookups and every
  invalidation trigger (size change, mtime change, device-ID mismatch,
  algorithm-version bump), an explicit incremental-rescan simulation, and
  `pruneMissing` (deleted-file cache rows are removed when they fall under
  a scanned root, and left alone when they don't).
- `test/features/deletion/safe_delete_service_test.dart` - real temp files
  on a real filesystem (not mocked) against a fake `PlatformDeleter`:
  successful trash/permanent delete, the keep-file backstop, protected
  locations, a file that no longer exists, a stale scan result whose
  on-disk size no longer matches (refused), the same check for mtime alone
  (a same-size replacement file at the same path - the exact "stale scan
  result deletes a different/new file" scenario - closes a gap a
  size-only check would have missed), duplicate-request rejection, and
  that a genuine platform-delete failure allows a later retry rather than
  permanently blocking the path.
- `test/features/scanner/scan_engine_test.dart` (tagged `integration` in
  `dart_test.yaml`) - the **full pipeline** against real temporary files on
  disk and the real native engine (loaded from `rust/target/release/`):
  duplicate detection across renamed copies, same-size-different-content
  exclusion, zero-byte-file handling, a genuinely inaccessible path
  reported as a scan error rather than a crash, mid-scan cancellation, and
  an incremental-rescan reuse check. This is the strongest correctness
  guarantee in the suite - nothing in it is mocked except settings.

### UI/widget tests

- `test/widget_test.dart` - the app's loading state renders without error
  before async init (settings/cache-DB/storage-enumeration) completes.
- `test/ui/results_screen_test.dart` - empty state, a populated duplicate
  group renders its file count and reclaimable size, and the delete button
  is disabled until something is selected.
- `test/ui/settings_screen_test.dart` - toggling a switch calls
  `updateSettings` with the expected value; protected locations render and
  are removable.

### Production-executable integration test (real compiled app)

`integration_test/app_test.dart`, run via
`flutter test integration_test/app_test.dart -d windows`, is a different
category from everything above: it builds and launches the **actual
Windows executable** and drives the **real widget tree** of that running
process (via `IntegrationTestWidgetsFlutterBinding`, not a mocked test
harness). Nothing here is a fake, a mock, or a headless simulation -
this is the production-artifact smoke test.

What it verifies, against a real app instance:

1. **Folder selection** → `AppController.addCustomFolder` (same method the
   "Add Folder" button calls; integration_test cannot drive the native OS
   file-picker dialog since it lives outside the Flutter engine, so the
   test calls the app's own method directly rather than faking the dialog).
2. **A real tap on the real "Start Scan" button**, which runs the actual
   `ScanEngine` → `HashWorkerPool` → `dart:ffi` → the real, bundled
   `dupora_engine.dll`, hashing real files with real BLAKE3.
3. **Duplicate detection correctness** against known ground truth: two
   files with identical content are grouped together; a third, different
   file is confirmed absent from every group; zero scan errors.
4. **Smart selection**: exactly one of the two duplicates is pre-selected
   for deletion, the other (the kept copy) is not.
5. **A real tap on the real delete button**, which shows the real
   Windows-specific confirmation dialog (`"Move to Trash?"` - proving the
   app correctly detected it's running with real Recycle Bin support), and
   a real tap on `"Move to Trash"`.
6. **The actual filesystem effect**, checked directly (not inferred): the
   deleted duplicate is gone from disk, the kept copy still exists, and an
   unrelated file elsewhere in the same folder was untouched.
7. A second test scans 25 files sharing content and calls
   `cancelScan()` almost immediately, verifying `ScanProgress.isCancelled`
   becomes `true` - the real cancellation path, not a simulated one.

Both tests passed:

```
00:00 +0: production build: scan, detect duplicates, delete to Recycle Bin
00:05 +1: production build: cancellation stops a scan cleanly
00:08 +2: All tests passed!
```

**Safety note:** every file this test reads, hashes, and deletes is created
by the test itself inside a fresh `Directory.systemTemp.createTemp()`
directory and cleaned up in `addTearDown`. It never touches, selects, or
deletes anything outside that directory - deliberately, since this
environment has real user files on other drives that must never be at risk
from an automated test run.

**How this was verified without reliable screen capture:** this build
environment is a remote/headless VM where OS-level screenshotting does not
reliably reflect the app's actual rendered window (it captures whatever the
remote viewer happens to show), and Flutter's Windows accessibility tree
was not reliably queryable via UI Automation or MSAA either. Rather than
drive the app blindly with synthetic keyboard/mouse input at guessed
screen coordinates - which would have been unable to verify what was
actually on screen before an irreversible action like a delete - this test
uses Flutter's own `integration_test` package, which operates on the real
widget tree from inside the running process itself. This is both more
reliable and safer than OS-level UI automation would have been.

### `integration_test/dataset_test.dart` - controlled real-world dataset

Same real-compiled-app approach, against a purpose-built dataset covering
every scenario in the release-audit checklist in one scan: identical files
under different names, identical files in different subdirectories,
same-size/different-content files, zero-byte files, a large (3 MiB) file
pair (exercises the mmap hashing path, not just the small-file buffered
path), and a genuinely `LockFileEx`-locked file (a mandatory lock on
Windows, which reliably blocks even a different isolate in the same
process from reading it - simulating a real "file in use by another
program" condition). A second scan after adding a new file and unlocking
the locked one confirms incremental-rescan/cache behavior end-to-end
through the real UI, not just the engine's own unit tests.

One real discovery while writing this test: a file with a size that
doesn't match any other file in the dataset is never read at all - Stage 1
filters it out before any hashing is attempted, by design. The first
version of this test locked a file with a unique size and asserted it
would produce a read-error; that assertion was wrong, not the app - the
app correctly never attempted to read it. Fixed by giving the locked file
a same-size sibling so it actually reaches an attempted (and blocked)
read.

### `integration_test/stress_test.dart` - scale, memory, cancellation under load

5,000 generated files (400 duplicate groups of 10 + 1,000 unique),
against the real compiled app. Verifies group-detection correctness at
this scale (400/400 groups, exactly), measures and prints real wall-clock
timing and real process memory (`ProcessInfo.currentRss`, sampled from
inside the running app - not an external estimate), verifies a repeated
scan of the same unchanged tree is meaningfully faster (cache effect
holding up under load, not just in a small unit test), and verifies
cancellation still takes effect promptly under this load. See
PERFORMANCE.md for the actual numbers this produced.

### `integration_test/linux_native_engine_test.dart` - Linux native-engine bundling verification

Written specifically to verify the fix for a real bug: the Linux release
bundle never included `libdupora_engine.so`, so the packaged app would
have failed the first time it tried to hash anything (see BUILD.md's
Linux section for the CMake/FFI-loader fix). Run via `flutter drive`
(`flutter test` doesn't support `--release`/`--profile` for this
invocation; `flutter drive` does, but hard-refuses `--release` on desktop
entirely, hence `--profile`) against the actual compiled Linux bundle on
GitHub Actions (`ubuntu-latest`, under `xvfb-run` since the runner has no
display).

**Actually passed on GitHub Actions run 31461334167** (2026-08-11), after
two earlier real failures on the same underlying fix that turned out to
be CI/test-tooling issues, not the fix itself - each diagnosed and fixed
in its own commit rather than blindly retried:
- Run 31439806896: `flutter test ... --release` doesn't support
  `--release` at all for this Flutter version → switched to `flutter
  drive` with a driver shim.
- Run 31440776286: `flutter drive --release` is unconditionally refused
  on desktop by Flutter Driver itself → switched to `--profile`.
- Run 31460545295: **the native engine load already succeeded here**
  (`Dupora native engine loaded successfully. Version: 0.1.0` in the real
  log) - the fix was already working. The test then failed its own
  `expect(find.byType(ScanScreen), findsOneWidget)` immediately after a
  single `tester.pump()`, because with only 3 tiny files the scan can
  finish faster than one pump observes on a loaded CI runner, going
  straight to the results screen. Removed that assertion in favor of
  `pumpUntil` waiting for the actual results screen - the thing that
  matters, not an intermediate frame.
- Run 31461334167: clean pass. Real log:
  `Dupora native engine loaded successfully. Version: 0.1.0`, then
  `Linux native-engine runtime verification passed: engine loaded, BLAKE3
  hashing executed, duplicate pair correctly identified, same-size/
  different-content pair correctly excluded`, then `All tests passed!`.

The test itself:

1. Calls `NativeHasher().engineVersion()` directly, before touching any
   UI - if the bundled `.so` weren't found, `DuporaNativeBindings
   ._openLibrary()` throws immediately here, with nothing downstream able
   to mask it.
2. Creates two genuinely identical files and one same-size-but-different-
   content file in a fresh temp directory.
3. Drives the real app through a real scan (`AppController.addCustomFolder`
   + "Start Scan", same pattern as `app_test.dart`).
4. Asserts exactly one duplicate group is found, containing exactly the
   two identical files, and that the same-size-different-content file is
   never classified as a duplicate of them - a result that's only
   possible if the actual Rust BLAKE3 engine executed a real full-content
   hash comparison, not just the Stage 1 size grouping.

No mocks anywhere in this path - real dlopen, real BLAKE3, real
filesystem, real widget tree.

### `integration_test/macos_native_engine_test.dart` - macOS native-engine bundling verification

Same bug, same shape of fix, same test structure as the Linux one above:
the macOS `.app` never embedded `libdupora_engine.dylib` (see BUILD.md's
macOS section for the Xcode-project/FFI-loader fix). Run via `flutter
drive --profile` against the actual compiled `.app` on GitHub Actions
(`macos-latest`) - no headless-display workaround needed, unlike Linux,
since macOS runners have a real GUI session.

**Passed on the first real CI attempt** (GitHub Actions run 31462917213,
2026-08-11) - applying the lessons already learned fixing Linux's
identical test (`flutter drive --profile` from the start, not `flutter
test --release`; `pumpUntil` for the results screen instead of a single
`pump()` before checking an intermediate screen) meant this one didn't
need multiple rounds of CI debugging. Real log:
`Dupora native engine loaded successfully. Version: 0.1.0`, then `macOS
native-engine runtime verification passed: engine loaded, BLAKE3 hashing
executed, duplicate pair correctly identified, same-size/different-content
pair correctly excluded`, then `All tests passed!`. The build's `Verify
the native engine is bundled` step also confirmed, via `lipo -info`, that
both the executable and the embedded dylib are genuine universal
(arm64 + x86_64) Mach-O binaries, not a single-architecture build.

Same test steps as Linux's version: call the native engine directly first
(no UI, proves `DynamicLibrary.open` succeeds), create the same controlled
dataset, drive a real scan through the real widget tree, assert correct
duplicate detection. No mocks.

## A hang bug this test suite caught

`file_discovery.dart`'s `ReceivePort` never completes its own `Stream` -
that's how `ReceivePort` works. `ScanEngine.start()`'s `await for` loop over
it had no explicit exit condition after the terminal `DiscoveryDone`
message, so every scan hung forever after discovery finished. This was
invisible in `flutter analyze` and in every unit test that didn't actually
run a full scan; the first full-pipeline `scan_engine_test.dart` run caught
it immediately (the test process never returned). Fixed by returning the
raw `ReceivePort` from `runFileDiscovery`, breaking out of the loop
explicitly on `DiscoveryDone`, and closing the port - see the "Bug fix"
section of the corresponding commit and `TESTING.md`'s existence as a
reminder that pure unit tests are not a substitute for end-to-end coverage.

## Bugs found by the production-readiness audit

A dedicated audit pass (full repository review + rerunning every test +
new real-exe integration tests) found four real issues, all fixed:

1. **FFI panic/undefined-behavior gap.** `dupora_stream_hasher_new`/`_abort`
   (Android SAF hashing path) weren't wrapped in `catch_unwind`, unlike
   every other `extern "C"` function in the crate, and all four call sites
   used a plain `.lock().unwrap()`. A panic while any *other* handle's
   lock was held would poison the mutex; the next call to either
   unwrapped function would then panic again and unwind across the FFI
   boundary - undefined behavior. Fixed with a poison-recovering lock
   helper and `catch_unwind` on both functions.
2. **Unhandled scan-failure exception.** `AppController.startScan()` had
   no error handling around the engine call - any exception mid-scan
   (database error, worker isolate failing to spawn, disk I/O failure)
   would leave the UI stuck on the Scanning screen forever with no
   recovery short of restarting the app. Now caught and surfaced via a
   (new) dismissible error banner on the Home screen; also fixed a
   related issue where `lastError` was already being captured for a
   different failure case (storage-volume enumeration) but was never
   actually displayed anywhere.
3. **Weak pre-delete identity check.** `SafeDeleteCoordinator` only
   checked file size before deleting - a same-size replacement file at
   the same path (the "stale scan result deletes a different/new file"
   scenario) would have slipped through. Now also checks mtime. This
   path had zero dedicated test coverage before the audit; it has 9 tests
   now (`safe_delete_service_test.dart`).
4. **Unbounded stale-cache growth.** A cache row for a file deleted from
   disk was never invalidated (nothing ever looks it up again by that
   exact path), so it would sit in the database forever across repeated
   scans of a tree with churn. Added `HashCacheRepository.pruneMissing`,
   run once per scan right after discovery.

Also investigated and found **not** to be a bug, despite looking
suspicious at first: whether `HashWorkerPool.shutdown()`'s forced
completion of pending jobs could free native memory (cancellation
signal/progress counter) while a worker isolate was still touching it.
Traced through the actual call sequencing - `ScanEngine.start()` always
fully `await`s every `Future.wait` batch of submitted jobs before
`shutdown()` ever runs in its `finally` block - and confirmed the forced-
completion path is unreachable from the current call site, not silently
racy.

## What's intentionally not covered

- **Android SAF / device-channel Kotlin code** (`SafChannel.kt`,
  `StorageChannel.kt`) has no automated test coverage in this repository:
  Flutter's platform-channel unit-testing story requires either a running
  device/emulator or hand-mocking `MethodChannel` responses, and this build
  had no Android device/emulator session available (see BUILD.md). The
  Dart-side `SafBridge` was written against the documented `MethodChannel`
  contract but is unverified end-to-end.
- **macOS `TrashChannel.swift`** - now confirmed to compile successfully
  on a real `macos-latest` GitHub Actions runner (`.github/workflows/
  release.yml`, run 31437939750, after fixing its Xcode-project
  registration - see BUILD.md). Still not exercised at runtime: no macOS
  host was available in any of this project's build sessions to actually
  launch the app or invoke the Trash channel.
- **Windows is no longer in this list.** An earlier draft of this document
  said the Windows release build and its runtime behavior were unverified;
  that's since been resolved - see BUILD.md and the integration-test
  section above. (One dead end worth recording: `dupora_engine.dll` and
  `sqlite3.dll` only get `LoadLibrary`'d into the process on first actual
  use - the first hash call and the first SQL query, respectively - not at
  `DynamicLibrary.open`/`NativeDatabase.open` call time. Watching for those
  DLLs in the process's loaded-module list immediately after launch
  produced a false "it's hung" signal during debugging; a diagnostic
  `print()` trace through `AppController.init()` showed every step
  completing in well under a second, and the integration test above
  confirms both DLLs really do load correctly once the app actually scans
  and caches something.)
