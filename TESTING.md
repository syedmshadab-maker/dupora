# Testing

## Current status

```
cargo test                                       24 / 24 passing   (rust/)
flutter test                                      48 / 48 passing   (test/)
flutter test integration_test/app_test.dart -d windows   2 / 2 passing   (real compiled exe)
flutter analyze                                    0 issues
cargo clippy                                         0 warnings (-D warnings)
dart format                                          clean
cargo fmt --check                                    clean
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
  algorithm-version bump) plus an explicit incremental-rescan simulation.
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

## What's intentionally not covered

- **Android SAF / device-channel Kotlin code** (`SafChannel.kt`,
  `StorageChannel.kt`) has no automated test coverage in this repository:
  Flutter's platform-channel unit-testing story requires either a running
  device/emulator or hand-mocking `MethodChannel` responses, and this build
  had no Android device/emulator session available (see BUILD.md). The
  Dart-side `SafBridge` was written against the documented `MethodChannel`
  contract but is unverified end-to-end.
- **macOS `TrashChannel.swift`** - no macOS host was available to compile
  or exercise it.
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
