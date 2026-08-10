# Security

## Threat model for this application

Dupora reads and deletes files at the user's explicit direction. The
primary risks are: (1) deleting the wrong file, (2) crashing or hanging on
adversarial/malformed filesystem input, and (3) misidentifying two
different files as duplicates. This document covers how each is mitigated
and what is explicitly out of scope.

## Exact-duplicate guarantee

Two files are only ever reported as duplicates when:

```
same size AND same full BLAKE3-256 digest
```

computed by streaming the *entire* file content (never truncated, never
sampled). The Stage 2 partial fingerprint (`rust/src/hashing/partial.rs`) is
explicitly documented and tested as a **filter only** - see
`rust/tests/adversarial.rs::same_size_different_content_never_hash_equal`
and `.../different_filename_same_content_hash_equal`. Filename, extension,
modification time, and any other metadata never factor into the duplicate
decision.

This is a cryptographic, not information-theoretic, guarantee: a hash
collision is possible in principle for any hash function, including
BLAKE3. The application does not, and should not, claim mathematical
certainty beyond BLAKE3's published security margin.

## Delete safety

`SafeDeleteCoordinator` (`lib/features/deletion/safe_delete_service.dart`)
enforces, in order, immediately before every OS-level delete call:

1. **Protected-location refusal.** `ProtectedLocations` blocks OS,
   application, and user-designated directories (`lib/features/deletion/protected_locations.dart`).
2. **Keep-file backstop.** The file explicitly marked "keep" for its
   duplicate group can never be passed to delete, independent of whatever
   selection UI state produced the request.
3. **Existence + identity re-check.** The file must still exist, and its
   current on-disk size must still match what was recorded during the scan.
   A file that changed size since the scan is refused rather than deleted -
   it may no longer be the file the user reviewed.
4. **Duplicate-request de-duplication.** A path already in flight or
   already processed in the same coordinator instance is rejected rather
   than deleted twice.

Deletion uses the platform trash/recycle bin wherever one exists (Windows
Recycle Bin via `SHFileOperationW`+`FOF_ALLOWUNDO`; macOS Trash via
`FileManager.trashItem`; Linux via `gio trash` / the freedesktop.org Trash
spec). Android has no SAF-level trash primitive, so its delete is
permanent (`DocumentsContract.deleteDocument`) - the Results screen shows a
different, more explicit warning dialog in that case
(`lib/ui/screens/results_screen.dart::_confirmAndDelete`) rather than the
normal "moved to Trash" copy.

## Untrusted filesystem input

Paths, filenames, and file content are all treated as untrusted:

- **Path traversal / unusual paths**: the scanner never constructs paths by
  string-concatenating untrusted segments into a shell command or SQL
  query; all filesystem access goes through `dart:io`/Rust `std::fs` typed
  APIs, and the cache uses parameterized Drift queries exclusively.
- **Symlink loops**: not followed by default (`followSymlinks: false`);
  when explicitly enabled, `file_discovery.dart` tracks resolved real paths
  in a visited-set to prevent cycles.
- **Malformed/invalid-Unicode filenames**: `rust/tests/adversarial.rs::unicode_filename_hashes_correctly`
  exercises multi-script Unicode paths. Filenames that are not valid UTF-8
  after Dart's UTF-16-to-UTF-8 conversion are rejected with
  `StatusCode::InvalidArgument` by the FFI layer rather than causing
  undefined behavior (`rust/src/ffi/mod.rs::ffi_invalid_utf8_path_is_rejected_not_ub`).
  Pathological lone-UTF-16-surrogate filenames (extremely rare in practice)
  are a known limitation of this UTF-8-based FFI boundary - see
  README's Known Limitations.
- **Inaccessible / disappearing files, permission failures**: caught
  per-entry during discovery and per-file during hashing; recorded as
  `ScanError`s, never crash the scan
  (`rust/tests/adversarial.rs::inaccessible_file_does_not_panic_and_reports_error`,
  `test/features/scanner/scan_engine_test.dart::an inaccessible path is reported as a scan error`).
- **Files changing during a scan**: mmap-based hashing has an inherent race
  if a file is truncated/rewritten while mapped; this is a known, documented
  risk of the mmap strategy (see `hash_mmap`'s doc comment) rather than a
  silent correctness bug. The Stage 3 identity re-check in
  `SafeDeleteCoordinator` mitigates the highest-impact case (deleting a file
  that changed after being reviewed as a duplicate).

## FFI safety

Every `extern "C"` function in `rust/src/ffi/` is wrapped in
`std::panic::catch_unwind`: a Rust panic must never unwind across the FFI
boundary (undefined behavior). A caught panic is mapped to
`StatusCode::Unexpected` rather than propagating.

Native memory passed across the boundary (cancellation flags, progress
counters, path buffers) is always caller-allocated and caller-freed
(`package:ffi`'s `calloc`/`calloc.free` on the Dart side); Rust never frees
Dart-owned memory and never returns owned heap pointers Dart would need to
free (the one exception, `dupora_engine_version()`, returns a `'static`
string literal).

## Logging

Scan/deletion operations are logged at a structural level (counts, paths,
durations, error categories) - never file *contents*. See TESTING.md/README
for what's implemented vs. deferred in the logging subsystem.

## Out of scope

- Protecting against a malicious actor with the same OS-user privileges as
  Dupora itself (e.g. a concurrent process actively racing to swap file
  content between the partial and full hash reads). This is a general
  TOCTOU class of issue inherent to any userspace file tool and is not
  specific to this application.
- Sandboxing the Rust engine beyond normal OS process memory protection.
