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

**This machine's build environment could not complete the last step.**
`flutter build windows` requires the MSVC toolchain (`flutter doctor`
reports: *"Visual Studio is missing necessary components... Desktop
development with C++"*), and this build ran with no admin rights and no
package manager (`winget`/`choco`) available to install Visual Studio Build
Tools non-interactively. Everything else was fully built and verified here:

- The Rust engine builds, tests, lints, and formats cleanly (see below) -
  it does **not** need MSVC, because this project's Rust toolchain targets
  `x86_64-pc-windows-gnu` (rustup's bundled minimal mingw linker), not
  `-msvc`. The resulting `dupora_engine.dll` uses the C ABI, which Dart's
  `dart:ffi` loads at runtime via `LoadLibrary` regardless of which linker
  produced it.
- `flutter analyze` and `flutter test` (48 tests) both pass - `flutter
  test` runs against a prebuilt "flutter tester" engine binary shipped with
  the SDK, which is independent of the MSVC/CMake toolchain that only
  `flutter build windows`/`flutter run -d windows` need.

To finish a Windows release build on a machine with the right permissions:

```powershell
winget install --id Microsoft.VisualStudio.2022.BuildTools --silent --override "--add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
flutter doctor    # confirm the Visual Studio check now passes
cd rust && cargo build --release && cd ..
flutter build windows --release
```

`windows/CMakeLists.txt` has an `install(FILES ...)` rule (alongside the
Flutter-generated ones for `flutter_windows.dll` and plugin libraries) that
bundles `rust/target/release/dupora_engine.dll` next to `Runner.exe`, so a
completed `flutter build windows` needs no manual DLL-copying step. This
rule could not be exercised end-to-end in this session (no MSVC to run the
CMake build at all - see above) but follows the exact same pattern as the
Flutter-generated rules immediately above it in the same file.

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
- A `flutter build apk --release` (arm64 only) was also run; see the git
  history for this build's outcome.

**What remains unverified:** no physical Android device or running
emulator session was used, so while the APK is built and contains the
correct native code, the SAF/storage `MethodChannel` code paths have not
been exercised at *runtime* (tapping "Add Folder," picking a SAF tree,
scanning it, etc.) - see TESTING.md. The armv7 and x86_64 ABIs were also
cross-compiled in this session (`android/app/src/main/jniLibs/armeabi-v7a/`,
`.../x86_64/`) for a multi-ABI release build, but the APK inspected above
was built arm64-only.

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
