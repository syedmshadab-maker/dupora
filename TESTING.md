# Testing

## Current status

```
cargo test        24 / 24 passing   (rust/)
flutter test       48 / 48 passing   (test/)
flutter analyze     0 issues
cargo clippy         0 warnings (-D warnings)
dart format          clean
cargo fmt --check    clean
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
- **A literal `flutter build windows` release binary** - blocked by a
  missing MSVC toolchain in this environment; see BUILD.md for the exact
  remediation command. `flutter test` uses a prebuilt engine binary
  independent of this toolchain, which is why the Dart test suite above
  still runs and passes on this machine.
