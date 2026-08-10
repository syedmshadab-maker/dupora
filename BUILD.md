# Build

## Prerequisites (all platforms)

- Flutter SDK (this repo was built against Flutter 3.41.9 / Dart 3.11.5,
  stable channel).
- Rust (stable) - install via [rustup](https://rustup.rs).
- The native engine must be built **before** the Flutter app looks for it:

  ```powershell
  cd rust
  cargo build --release
  cd ..
  ```

  `lib/core/native/dupora_native_bindings.dart` probes several relative
  paths (`rust/target/release/`, `../rust/target/release/`, etc.) so
  `flutter run`/`flutter test` find the freshly built library without any
  manual copying during development. Packaged release builds need an
  explicit copy step per platform - see below.

## Windows

```powershell
cd rust
cargo build --release
cd ..
flutter build windows --release
```

**Status: fully built and runtime-verified in this repository's own build
session.** This environment initially had no MSVC toolchain and no admin
rights or package manager (`winget`/`choco`) to install one interactively.
The MSVC Build Tools 2022 bootstrapper (`vs_buildtools.exe --quiet --wait
--norestart`, workloads `Microsoft.VisualStudio.Workload.VCTools` +
`Microsoft.VisualStudio.Component.VC.Tools.x86.x64` +
`Microsoft.VisualStudio.Component.Windows11SDK.22621`) was run directly and
completed successfully despite the lack of an elevated admin token - `flutter
doctor` subsequently reported `[√] Visual Studio - develop Windows apps
(Visual Studio Build Tools 2022 17.14.37)` with no issues. From there:

- `flutter build windows --release` succeeded:
  `build\windows\x64\runner\Release\dupora.exe` (91 KB launcher; the real
  weight is in the bundled DLLs below).
- The release directory contains `dupora.exe`, `dupora_engine.dll` (1.37 MB,
  the real Rust engine), `flutter_windows.dll`, `sqlite3.dll`,
  `sqlite3_flutter_libs_plugin.dll`, and `file_selector_windows_plugin.dll`
  - confirmed by direct directory listing, not just build-log inference.
- The `windows/CMakeLists.txt` `install(FILES ...)` rule that bundles
  `dupora_engine.dll` next to `Runner.exe` (added earlier in this project,
  alongside the Flutter-generated rules for `flutter_windows.dll` and
  plugin libraries) is confirmed working: that's how the DLL got there.
- **The compiled executable was launched and driven end-to-end** via
  `flutter test integration_test/app_test.dart -d windows` (see TESTING.md
  for full detail): it added a real folder, scanned it with the real
  native BLAKE3 engine, correctly identified the one genuine duplicate pair
  while excluding an unrelated file, applied smart selection, and deleted
  the duplicate through the real Windows Recycle Bin confirmation dialog -
  verified by checking the actual filesystem afterward (deleted file gone,
  kept file present, unrelated file untouched). A second test verified
  mid-scan cancellation. Both passed.

If you're setting this up fresh on a machine that already has MSVC (e.g. a
normal dev workstation or GitHub Actions' `windows-latest` runner), you only
need the three commands at the top of this section. If you're in an
environment as constrained as this one was, the install command that worked
here was:

```powershell
$env:USERPROFILE\vs_buildtools.exe --quiet --wait --norestart --nocache `
  --add Microsoft.VisualStudio.Workload.VCTools `
  --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
  --add Microsoft.VisualStudio.Component.Windows11SDK.22621 `
  --includeRecommended
# (download vs_buildtools.exe first: https://aka.ms/vs/17/release/vs_buildtools.exe)
flutter doctor    # confirm the Visual Studio check now passes
cd rust && cargo build --release && cd ..
flutter build windows --release
```

This installed ~3.4 GB to `C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools`
and took about 12 minutes on this machine's network connection.

## Android

Requirements: Android SDK + NDK (this build used NDK 28.2.13676358),
`rustup target add aarch64-linux-android armv7-linux-androideabi
x86_64-linux-android`. `rust/.cargo/config.toml` in this repo points at the
NDK's clang wrappers for linking; set `CC_aarch64_linux_android` (and the
armv7/x86_64 equivalents) to the matching `*-clang.cmd` wrapper so `cc-rs`
(used by `blake3`'s build script for its NEON intrinsics) can compile, e.g.:

```powershell
$env:CC_aarch64_linux_android = "$env:ANDROID_HOME\ndk\28.2.13676358\toolchains\llvm\prebuilt\windows-x86_64\bin\aarch64-linux-android30-clang.cmd"
cd rust
cargo build --release --target aarch64-linux-android
cd ..
```

Copy the resulting `.so` into `android/app/src/main/jniLibs/arm64-v8a/libdupora_engine.so`
(repeat per ABI), then:

```powershell
flutter build apk --release
# or, for Play Store distribution:
flutter build appbundle --release
```

minSdk is pinned to 30 (Android 11) in `android/app/build.gradle.kts` per
the project's target-platform requirement.

**Status of this build's Android verification: actually built and
confirmed to contain the native engine.** In this session:

- `cargo build --release --target aarch64-linux-android` succeeded against
  NDK 28.2.13676358, producing a real `libdupora_engine.so`.
- That `.so` was staged into `android/app/src/main/jniLibs/arm64-v8a/`.
- `flutter build apk --debug` then succeeded, producing
  `build/app/outputs/flutter-apk/app-debug.apk`. Inspecting the APK's
  contents confirms `lib/arm64-v8a/libdupora_engine.so` is bundled inside
  it alongside Flutter's own `libflutter.so` and `libsqlite3.so` - i.e. the
  Kotlin (`StorageChannel.kt`, `SafChannel.kt`), Dart, and Rust pieces all
  compile and package together correctly for a real Android target.
- `flutter build apk --release --target-platform android-arm64` then
  succeeded too: `build/app/outputs/flutter-apk/app-release.apk`, 23.4 MB,
  R8-minified, confirmed (by inspecting the archive) to still contain
  `lib/arm64-v8a/libdupora_engine.so`.

**What remains unverified:** no physical Android device or running
emulator session was used, so while both APKs are built and contain the
correct native code, the SAF/storage `MethodChannel` code paths have not
been exercised at *runtime* (tapping "Add Folder," picking a SAF tree,
scanning it, etc.) - see TESTING.md.

**ABI coverage:** the release APK above is `arm64-v8a` only - the ABI real
Android phones/tablets have used since 2019 and the right default for a
build-verification pass. `armv7-linux-androideabi` (legacy 32-bit devices)
and `x86_64-linux-android` (emulators) cross-compile via the identical
`.cargo/config.toml` + `CC_<target>` pattern documented above; producing a
universal multi-ABI release is one more `cargo build --target` invocation
per ABI plus `flutter build apk --release` (no `--target-platform` filter)
away, not attempted for all three ABIs together in this session.

## macOS

```bash
cd rust
cargo build --release --target aarch64-apple-darwin   # Apple Silicon
cargo build --release --target x86_64-apple-darwin    # Intel
cd ..
lipo -create -output rust/target/release/libdupora_engine_universal.dylib \
  rust/target/aarch64-apple-darwin/release/libdupora_engine.dylib \
  rust/target/x86_64-apple-darwin/release/libdupora_engine.dylib
flutter build macos --release
```

`macos/Runner/TrashChannel.swift` needs to be part of the Xcode project
target (added via `macos/Runner.xcodeproj` if not auto-picked-up) for the
Trash `MethodChannel` to register. **Not built or run in this session -
no macOS hardware was available.**

## Linux

```bash
cd rust
cargo build --release
cd ..
flutter build linux --release
```

Needs the GTK3 development headers Flutter's Linux desktop embedder
requires (`libgtk-3-dev` and friends) on the build machine. **Not built or
run in this session - no Linux hardware was available**; `LinuxDeleter`'s
`gio trash` call and `LinuxStorageDetector`'s `/proc/mounts` parsing were
validated with unit tests against synthetic input instead (see TESTING.md).

## Verifying without a full platform build

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

All of the above were run and pass in this repository's current state (see
TESTING.md for full output).

## CI

`.github/workflows/ci.yml` runs the verification block above (Rust fmt/
clippy/test, Dart format/analyze/test) on every push, plus a Windows
release-build job (which will succeed on GitHub's hosted runners, which
have the MSVC toolchain preinstalled, unlike this build environment).
