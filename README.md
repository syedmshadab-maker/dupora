# Dupora

A cross-platform, production-grade duplicate file finder and cleaner for
Windows, macOS, Linux, and Android 11+. Exact duplicates only, verified by
full-file BLAKE3 - never filename, metadata, or partial-content heuristics.

## What it does

1. **Discover** files across selected drives/folders (internal storage,
   external drives, USB, SD cards, Android SAF trees).
2. **Filter** in three stages, so the expensive step (full cryptographic
   hashing) only ever runs on files that survived the cheap ones: group by
   exact size -> sub-group by an 8 KB head+tail fingerprint -> verify
   survivors with a full streaming BLAKE3 hash.
3. **Present** duplicate groups with smart-selection strategies (keep
   oldest/newest/shortest-path/first) that never select a protected
   location or the file marked "keep".
4. **Delete safely** - platform trash/Recycle Bin wherever one exists, with
   pre-delete existence/size re-verification and an explicit warning on
   platforms (Android) where deletion is permanent.
5. **Cache** every hash persistently (Drift/SQLite), so a second scan of an
   unchanged tree reuses cached hashes instead of re-hashing.

## Technology and why

| Layer | Choice | Why |
|---|---|---|
| UI | Flutter/Dart | Cross-platform requirement across 4 OS targets from one codebase. |
| Native engine | Rust | Memory-safe, no-GC-pause streaming hashing; required by spec for the performance-critical path. |
| Dart↔Rust bridge | Hand-rolled `dart:ffi` | Not `flutter_rust_bridge` - see ARCHITECTURE.md for the reasoning (toolchain risk, unneeded complexity for this project's actual async needs). |
| Hashing | BLAKE3 (`blake3` crate) | Specified by the brief; fast, parallelizable, cryptographically strong. |
| Database | Drift (SQLite) | Not Isar - Isar's maintenance has stalled and its latest release predates this project's SDKs; SQLite via Drift is the more defensible choice for a cache that must survive SDK upgrades. See ARCHITECTURE.md. |
| State management | `provider` + a single `ChangeNotifier` | One well-scoped, linear workflow (pick folders → scan → review → delete) doesn't benefit from a larger dependency-injection framework. |

## Project status - what's real vs. what's unverified

This was built in a single sandboxed session with **no macOS/Linux
hardware and no Android device/emulator** available. Everything below is
stated precisely rather than rounded up:

**Windows: fully built and runtime-verified, including the actual
production executable.**
- The full Rust engine: builds, 24/24 tests pass (including official
  BLAKE3 golden vectors), `cargo clippy -D warnings` clean, `cargo fmt
  --check` clean.
- The full Dart application: `flutter analyze` clean, `dart format` clean,
  48/48 tests pass, including an end-to-end pipeline test against real
  files on disk and the real compiled native engine (not mocked).
- The MSVC Build Tools this environment initially lacked were installed
  directly (`vs_buildtools.exe --quiet --wait`, no admin token needed in
  practice) and `flutter build windows --release` succeeded:
  `build\windows\x64\runner\Release\dupora.exe`, with `dupora_engine.dll`,
  `sqlite3.dll`, and all plugin DLLs confirmed bundled next to it by direct
  directory inspection.
- **The compiled executable was launched and driven end-to-end** via
  Flutter's `integration_test` package (`flutter test
  integration_test/app_test.dart -d windows`), which runs against the real
  running app's real widget tree rather than a mock: it added a real
  folder, tapped the real "Start Scan" button, scanned with the real
  BLAKE3 engine, correctly grouped two identical files while excluding an
  unrelated one, applied smart selection, tapped the real delete button,
  confirmed the real "Move to Trash?" dialog, and - verified directly
  against the filesystem afterward - the duplicate was gone, the kept copy
  and the unrelated file were untouched. A second test verified mid-scan
  cancellation. Both passed. Full detail in TESTING.md.
- Windows storage-volume detection (`GetLogicalDrives`/`GetDriveType`/
  `GetDiskFreeSpaceEx`) and Recycle Bin deletion (`SHFileOperationW`) are
  exercised as part of that same real run.

**Android: cross-compiled and packaged for real; not device-tested.** The
Rust engine was cross-compiled for `aarch64-linux-android` against NDK
28.2.13676358, staged into `jniLibs`, and both `flutter build apk --debug`
and `flutter build apk --release` succeeded (23.4 MB, R8-minified) -
inspecting both APKs confirms `libdupora_engine.so` is bundled inside
alongside Flutter's own native libraries. Kotlin (`StorageChannel.kt`,
`SafChannel.kt`), Dart, and Rust all compile and package together
correctly for a real Android target. What's *not* verified is runtime
behavior on a physical device or emulator - see BUILD.md.

**Code-complete, architecturally integrated, but not runtime-verified
here** (see BUILD.md/TESTING.md for exactly why, per platform):
- macOS storage detection + Trash deletion (Swift `MethodChannel`) - no
  macOS host available.
- Linux storage detection + Trash deletion - no Linux host available;
  the parsing/formatting logic itself *is* unit-tested against synthetic
  input.
- Android SAF browsing/hashing/deletion and `StorageManager` volume listing
  *at runtime* - the Kotlin/Dart/Rust code compiles and packages correctly
  into a working APK (see above), but no Android device or emulator
  session was used to actually tap through the SAF picker flow.

**Deliberately scoped down:**
- Video-frame and PDF-page thumbnails render a file-type icon instead of a
  decoded frame/page (no bundled ffmpeg/pdfium decoder); image thumbnails
  are fully real, decoded via the pure-Dart `image` package.
- No dedicated `criterion` throughput benchmark harness, and the Windows
  integration test above ran at small scale (a handful of files) to verify
  correctness, not at the 10K/100K/1M-file scale the spec targets for
  performance - see PERFORMANCE.md for what performance claims are and
  aren't backed by measurement in this build.

None of the above is used to claim a false "it's done" - see each linked
document for specifics, and CHANGELOG.md for the full list.

## Quick start

```powershell
git clone <repo>
cd dupora
cd rust && cargo build --release && cd ..
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter test              # 48/48 passing
flutter run -d windows    # requires MSVC Build Tools - see BUILD.md
```

See **BUILD.md** for every platform's exact build commands (including the
ones that couldn't be completed here and precisely why), **ARCHITECTURE.md**
for how the pieces fit together and the reasoning behind each non-obvious
decision, **TESTING.md** for the full test inventory, **PERFORMANCE.md** for
the performance design and its (honestly labeled) limits, and **SECURITY.md**
for the delete-safety and untrusted-input model.

## Known Limitations

- macOS, Linux, and Android native code paths are written against their
  documented platform APIs but were not exercised on real hardware/emulator
  in this build session (Windows *was* - see above).
- Video/PDF thumbnails are file-type icons, not rendered frames/pages.
- The 64 MiB/4-core parallel-hashing threshold is a documented constant,
  not a value tuned against measured throughput on real HDD/SSD/USB
  hardware; the Windows integration test verified correctness at small
  scale, not throughput at the scales the spec targets.
- Android's storage-permission flow (SAF tree picking) is implemented as a
  platform-channel bridge but not yet wired into a dedicated Home-screen UI
  affordance for Android specifically - the Home screen's "Add Folder"
  button currently shows a placeholder message on Android directing to a
  future SAF-picker entry point.

## Release instructions

See **BUILD.md** for the complete, per-platform command sequence. For
Windows (fully verified in this build):

```powershell
cd rust && cargo build --release && cd ..
flutter build windows --release
# Output: build\windows\x64\runner\Release\dupora.exe
# (plus dupora_engine.dll, sqlite3.dll, and plugin DLLs bundled alongside it)
```

Requires the MSVC Build Tools ("Desktop development with C++" workload);
see BUILD.md if `flutter doctor` reports Visual Studio as missing.
