# Dupora

> **Find Duplicates. Reclaim Space.**
>
> A production-grade duplicate file finder and cleaner for Windows 10/11 x64.

**SUPPORTED PLATFORM: Windows 10/11 x64.** Dupora is a Windows-only
application. It does not build or ship for macOS, Linux, iOS, or Android as
an installable app.

**Repository:** https://github.com/syedmshadab-maker/dupora

`duplicate-file-finder` · `duplicate-cleaner` · `file-deduplication` ·
`blake3` · `flutter` · `rust` · `windows` · `storage-utility`

A production-grade duplicate file finder and cleaner for Windows. Exact
duplicates only, verified by full-file BLAKE3 - never filename, metadata, or
partial-content heuristics.

## What it does

1. **Discover** files across selected drives/folders (internal storage,
   external drives, USB, SD cards).
2. **Filter** in three stages, so the expensive step (full cryptographic
   hashing) only ever runs on files that survived the cheap ones: group by
   exact size -> sub-group by an 8 KB head+tail fingerprint -> verify
   survivors with a full streaming BLAKE3 hash.
3. **Present** duplicate groups with smart-selection strategies (keep
   oldest/newest/shortest-path/first) that never select a protected
   location or the file marked "keep".
4. **Delete safely** - to the Windows Recycle Bin, with pre-delete
   existence/size/mtime re-verification immediately before every delete.
5. **Cache** every hash persistently (Drift/SQLite), so a second scan of an
   unchanged tree reuses cached hashes instead of re-hashing.

## Technology and why

| Layer | Choice | Why |
|---|---|---|
| UI | Flutter/Dart | Native Windows desktop rendering with a productive, type-safe UI framework. |
| Native engine | Rust | Memory-safe, no-GC-pause streaming hashing; required by spec for the performance-critical path. |
| Dart↔Rust bridge | Hand-rolled `dart:ffi` | Not `flutter_rust_bridge` - see ARCHITECTURE.md for the reasoning (toolchain risk, unneeded complexity for this project's actual async needs). |
| Hashing | BLAKE3 (`blake3` crate) | Specified by the brief; fast, parallelizable, cryptographically strong. |
| Database | Drift (SQLite) | Not Isar - Isar's maintenance has stalled and its latest release predates this project's SDKs; SQLite via Drift is the more defensible choice for a cache that must survive SDK upgrades. See ARCHITECTURE.md. |
| State management | `provider` + a single `ChangeNotifier` | One well-scoped, linear workflow (pick folders → scan → review → delete) doesn't benefit from a larger dependency-injection framework. |
| Windows APIs | `win32`/`ffi` packages | Volume enumeration and Recycle Bin deletion (`SHFileOperationW`) not covered by pure-Dart/Flutter APIs. |

## Project status

**Fully built and runtime-verified, including the actual production
executable, under a dedicated production-readiness audit.**

- The full Rust engine: builds, passes its full test suite (including
  official BLAKE3 golden vectors), `cargo clippy -D warnings` clean, `cargo
  fmt --check` clean.
- The full Dart application: `flutter analyze` clean, `dart format` clean,
  full unit/widget test suite passing, including an end-to-end pipeline
  test against real files on disk and the real compiled native engine (not
  mocked).
- **The compiled executable was launched and driven end-to-end** via
  Flutter's `integration_test` package (see TESTING.md), which runs against
  the real running app's real widget tree rather than a mock:
  - `app_test.dart`: adds a folder, scans with the real BLAKE3 engine,
    detects a duplicate, applies smart selection, deletes through the real
    "Move to Trash?" dialog, and - verified directly against the
    filesystem - the duplicate was gone while the kept copy and an
    unrelated file survived. A second test verified mid-scan cancellation.
  - `dataset_test.dart`: a controlled dataset covering identical files
    under different names/directories, same-size-different-content,
    zero-byte files, a 3 MiB pair (mmap hashing path), and a genuinely
    `LockFileEx`-locked file correctly reported as a scan error, not a
    crash - plus a rescan proving incremental-cache behavior.
  - `stress_test.dart`: 5,000 files / 400 duplicate groups, with real
    measured wall-clock timing, real process memory
    (`ProcessInfo.currentRss`), a measured cache-speedup factor, and
    cancellation under load - see PERFORMANCE.md for the actual numbers.
  - Also verified separately: the compiled exe survives two full process
    restarts cleanly, with `dupora_cache.sqlite` persisting correctly on
    disk across them.
- Windows storage-volume detection (`GetLogicalDrives`/`GetDriveType`/
  `GetDiskFreeSpaceEx`) and Recycle Bin deletion (`SHFileOperationW`) are
  exercised as part of these same real runs.

**Deliberately scoped down:**
- Video-frame and PDF-page thumbnails render a file-type icon instead of a
  decoded frame/page (no bundled ffmpeg/pdfium decoder); image thumbnails
  are fully real, decoded via the pure-Dart `image` package.
- No dedicated `criterion` throughput benchmark harness - see PERFORMANCE.md
  for the full, honest breakdown of what is and isn't backed by measurement
  in this build.
- Windows-connected Android phones, external SD cards behind an MTP/Portable
  Devices interface, and similar non-drive-letter storage are not yet
  enumerated - see Known Limitations below.

See each linked document for specifics, and CHANGELOG.md for the full
history.

## Quick start

```powershell
git clone https://github.com/syedmshadab-maker/dupora.git
cd dupora
cd rust && cargo build --release && cd ..
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter test
flutter run -d windows    # requires MSVC Build Tools - see BUILD.md
```

See **BUILD.md** for the exact build commands, **ARCHITECTURE.md** for how
the pieces fit together and the reasoning behind each non-obvious decision,
**TESTING.md** for the full test inventory, **PERFORMANCE.md** for the
performance design and its (honestly labeled) limits, and **SECURITY.md**
for the delete-safety and untrusted-input model.

## Known Limitations

- Windows-connected Android phones/tablets that expose storage only through
  Portable Devices (MTP), rather than a drive letter, are not yet
  enumerated or scannable. The storage-detection layer is structured so
  this can be added without touching callers (see ARCHITECTURE.md), but the
  Windows Shell/Portable Devices integration itself is not implemented yet.
- Video/PDF thumbnails are file-type icons, not rendered frames/pages.
- The 64 MiB/4-core parallel-hashing threshold is a documented constant,
  not a value tuned against measured throughput on real HDD/SSD/USB
  hardware; the Windows integration test verified correctness at small
  scale, not throughput at the scales the spec targets.
- No perceptual/visual similarity detection for photos yet - duplicate
  detection is exact-content-match only (BLAKE3), by design (see
  SECURITY.md's exact-duplicate guarantee).

## Release instructions

See **BUILD.md** for the complete command sequence.

```powershell
cd rust && cargo build --release && cd ..
flutter build windows --release
# Output: build\windows\x64\runner\Release\dupora.exe
# (plus dupora_engine.dll, sqlite3.dll, and plugin DLLs bundled alongside it)
```

Requires the MSVC Build Tools ("Desktop development with C++" workload);
see BUILD.md if `flutter doctor` reports Visual Studio as missing.

A distributable Windows installer (`Dupora-Setup-x64-vX.Y.Z.exe`, built with
WiX Toolset - not a self-extracting script), an MSI, and a portable ZIP are
built from that release output via `installer/dupora.wxs` and
`installer/bundle.wxs` - see BUILD.md's "Windows installer" section for the
exact commands and the real install/launch/uninstall verification performed
against them.
