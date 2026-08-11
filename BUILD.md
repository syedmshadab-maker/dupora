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

### Windows installer

`installer/dupora.wxs` and `installer/bundle.wxs` build the distributable
installer with [WiX Toolset](https://wixtoolset.org/) v5 (a `dotnet` global
tool, not a system install - see below for why that mattered here).
`dupora.wxs` compiles to an MSI containing every file from
`build\windows\x64\runner\Release\` plus Start Menu/Desktop shortcuts and an
Add/Remove Programs entry; `bundle.wxs` wraps that MSI in a Burn bootstrapper
to produce a single self-contained `.exe`. Neither is a self-extracting
script - both are genuine Windows Installer / Burn packages inspectable with
`msiexec` and any MSI tooling.

```powershell
dotnet tool install --global wix
wix extension add WixToolset.UI.wixext/5.0.2 -g
wix extension add WixToolset.BootstrapperApplications.wixext/5.0.2 -g

wix build installer\dupora.wxs -arch x64 -ext WixToolset.UI.wixext `
  -d RepoRoot="$PWD" -d ReleaseDir="$PWD\build\windows\x64\runner\Release" `
  -o dist\Dupora-Setup-x64-v1.0.0.msi

wix build installer\bundle.wxs -arch x64 -ext WixToolset.BootstrapperApplications.wixext `
  -d RepoRoot="$PWD" -d MsiPath="$PWD\dist\Dupora-Setup-x64-v1.0.0.msi" `
  -o dist\Dupora-Setup-x64-v1.0.0.exe
```

**Why WiX instead of Inno Setup, and why per-user scope instead of
per-machine:** Inno Setup was tried first (it's the more commonly recommended
tool for this kind of installer). Its own installer (`innosetup-6.7.3.exe`)
refused to run at all in this sandboxed environment - `ExitCode 1`
("Setup failed to initialize") both as a normal install and with
`/PORTABLE=1` - because it requires administrator elevation that isn't
available here, and no 7-Zip was present to extract it as an archive
instead. WiX, obtained via `dotnet tool install --global wix` (installs into
the user's own profile, no elevation needed), does not have this problem.
The MSI was first authored with `Scope="perMachine"` (the conventional
default, installing to `Program Files`), and it built fine - but installing
it failed with **Windows Installer error 1925** ("You do not have sufficient
privileges to complete this installation for all users of the machine"),
for the same underlying reason Inno Setup failed: no admin rights in this
environment. Switching to `Scope="perUser"`, installing to
`%LocalAppData%\Programs\Dupora` (the same non-admin-install convention used
by VS Code, Discord, and Slack), resolved this and allowed a full,
genuine, non-elevated install/launch/uninstall cycle to be verified
end-to-end in this environment - see below. On a normal user's own machine
with administrator rights, `Scope="perMachine"` would also work; `perUser`
was chosen specifically because it is the scope that is actually
installable and testable without administrator rights, which is exactly the
constraint this build environment has.

**Verified in this environment** (`dist\Dupora-Setup-x64-v1.0.0.exe /quiet`,
via `Start-Process -Wait -PassThru` for reliable exit-code capture):
- Silent install: exit code 0. All 24 files present under
  `%LocalAppData%\Programs\Dupora` (dupora.exe, dupora_engine.dll,
  sqlite3.dll, flutter_windows.dll, both plugin DLLs, and the full `data\`
  tree - flutter_assets, fonts, shaders, icudtl.dat, app.so).
- Start Menu (`Dupora.lnk` + `Uninstall Dupora.lnk`) and Desktop
  (`Dupora.lnk`) shortcuts created; Add/Remove Programs entry registered
  (`DisplayName=Dupora`, `DisplayVersion=1.0.0.0`, `Publisher=Dupora`) under
  both the bundle's own HKCU uninstall key and the underlying MSI's
  per-user-managed HKLM uninstall key (both are normal for a per-user Burn+MSI
  install and require no elevation to write).
- Launched `dupora.exe` from the installed location (independent of
  `D:\DUPORA`): process started, stayed running, and correctly initialized
  its Drift/SQLite cache database at
  `%APPDATA%\com.dupora\dupora\dupora_cache.sqlite` - the same behavior
  already verified functionally correct end-to-end (scan, BLAKE3, duplicate
  detection, Recycle Bin deletion) against this identical binary set via
  `integration_test` (see TESTING.md). This installer pass re-verifies that
  *packaging* didn't break anything, not the application logic itself, which
  was already covered by `integration_test`; a full UI-driven functional
  re-test of the *installed copy specifically* wasn't repeated because
  `integration_test` builds and drives its own Flutter-managed binary and
  can't be pointed at an arbitrary already-installed `.exe`.
- Silent uninstall (`/uninstall /quiet`): exit code 0. Install directory,
  both shortcuts, and the Add/Remove Programs entry were all confirmed gone
  afterward.
- The portable ZIP (`dist\Dupora-Portable-x64.zip` - just a zipped copy of
  `build\windows\x64\runner\Release\`) was separately extracted to a clean
  location and its `dupora.exe` launched the same way, with the same
  result.

`dist\SHA256SUMS.txt` has SHA-256 checksums (Windows PowerShell
`Get-FileHash`, cross-checked with `sha256sum`) for the installer, the MSI,
the portable ZIP, and the release APK.

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

**Compiles successfully on a real `macos-latest` GitHub Actions runner**
(verified via `.github/workflows/release.yml`, run 31437939750, after
fixing `macos/Runner.xcodeproj/project.pbxproj` to actually register
`macos/Runner/TrashChannel.swift` in the Runner target's build phase - it
existed in the repo but Xcode was silently never compiling it, which
`flutter build macos --release` caught immediately as `error: cannot find
'TrashChannel' in scope`). This is **build verification only**: no macOS
hardware exists in this project's build sessions, so the Trash
`MethodChannel` itself, and the app generally, have never been launched or
exercised at runtime on macOS. It also isn't attached to GitHub Releases
yet - see "Automated GitHub Releases" below for why (the native engine
library isn't bundled into the packaged `.app` for this platform).

## Linux

```bash
cd rust
cargo build --release
cd ..
flutter build linux --release
```

Needs the GTK3 development headers Flutter's Linux desktop embedder
requires (`libgtk-3-dev` and friends) on the build machine. Not built or
run on local hardware in any of this project's sessions - no Linux
machine has ever been available here - but built and bundled for real on
a GitHub-hosted `ubuntu-latest` (x86_64) runner, via
`.github/workflows/release.yml`'s `build-linux` job:

- **Native engine bundling**: `rust/target/release/libdupora_engine.so`
  (built via plain `cargo build --release`, no cross-compilation needed
  since the runner's own architecture matches the target) is installed by
  `linux/CMakeLists.txt` into `build/linux/x64/release/bundle/lib/
  libdupora_engine.so`, next to the plugin libraries, mirroring the exact
  `install(FILES ...)` pattern `windows/CMakeLists.txt` already used for
  `dupora_engine.dll`. This was the actual gap: the file existed in the
  Rust build output but nothing copied it into the Flutter Linux bundle
  Flutter itself produces.
- **FFI loader**: `lib/core/native/dupora_native_bindings.dart`'s Linux
  branch now resolves `bundle/lib/libdupora_engine.so` via an explicit,
  unambiguous path computed from `Platform.resolvedExecutable`'s directory
  (`<exe dir>/lib/libdupora_engine.so`), rather than relying only on a bare
  `dlopen("libdupora_engine.so")` and the executable's `$ORIGIN/lib` RPATH
  - which Flutter's own bundled libraries rely on safely because they're
  linked at compile time (`target_link_libraries`), a different resolution
  path than a pure runtime `dlopen` call from inside the Dart VM. Windows,
  macOS, and Android loading are unchanged.
- **Runtime verification**: `integration_test/linux_native_engine_test.dart`
  drives the actual compiled bundle's executable via `flutter drive`
  (`xvfb-run -a flutter drive --driver=test_driver/integration_test.dart
  --target=integration_test/linux_native_engine_test.dart -d linux
  --profile` - `--profile` because Flutter Driver hard-refuses `--release`
  entirely on desktop platforms, and GitHub's runner has no display, hence
  `xvfb-run`) - it calls the native engine directly first (proving
  `DynamicLibrary.open` succeeds with no fallback needed), then runs a
  real scan against two genuinely identical files and one same-size-but-
  different-content file, and asserts the duplicate pair is correctly
  found while the different-content file is correctly excluded - only
  possible if the real BLAKE3 engine actually executed. See TESTING.md for
  the full result and exact GitHub Actions run ID.
- **Architecture**: x86_64 only - GitHub's `ubuntu-latest` runner is
  x86_64, and that's the only architecture built, verified, or claimed. No
  ARM64 Linux build exists.
- **Portable package**: CI packages the verified bundle as
  `Dupora-Linux-x64-vX.Y.Z.tar.gz` (`tar -C build/linux/x64/release -czf
  ... bundle`). To run it: `tar xzf Dupora-Linux-x64-vX.Y.Z.tar.gz && ./
  bundle/dupora` - no installation, and Rust/Cargo/Flutter are not
  required on the machine running it. Not included in the already-published
  `v1.0.0` release; attached automatically starting with the next tag.
- `LinuxDeleter`'s `gio trash` call and `LinuxStorageDetector`'s
  `/proc/mounts` parsing are separately validated with unit tests against
  synthetic input (see TESTING.md) - the runtime verification above
  exercises scanning and hashing, not deletion.

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
clippy/test, Dart format/analyze/test) on every push to `master` and on
every pull request, plus per-platform release-build jobs for Windows,
Android, macOS, and Linux (which will succeed on GitHub's hosted runners,
which have each platform's toolchain preinstalled, unlike this sandboxed
build environment).

## Automated GitHub Releases

`.github/workflows/release.yml` builds and publishes a full GitHub Release
automatically whenever a version tag is pushed:

```powershell
git tag v1.0.0
git push origin v1.0.0
```

This triggers, in order: the same Rust + Dart quality gate as CI (any
failure stops everything - no partially-validated release is ever
published); a Windows job that builds the release exe, compiles the WiX
MSI + Burn bootstrapper installer from `installer/dupora.wxs` and
`installer/bundle.wxs` exactly as described above, builds the portable
ZIP, and actually silently installs, launches, and uninstalls the
generated installer on the runner as a smoke test; and an Android job that
cross-compiles the arm64 engine, builds a release APK, and verifies its
contents with `aapt2` (package identity, adaptive launcher icon, native
engine library). Once the Windows and Android jobs both succeed, a final
job generates `SHA256SUMS.txt` and publishes a GitHub Release for the tag
with all artifacts attached.

**Version numbers are never hardcoded in the workflow.** The tag itself
(`vX.Y.Z`) is the single source of truth; a `prepare` job parses it and
passes the result to every other job via `flutter build --build-name=...
--build-number=...` (for the app) and a WiX `-d AppVersion=...` variable
(for the installer), keeping the tag, the built app, and the installer
version consistent.

**What CI actually produces vs. what it doesn't:**

- **Windows, Android, and Linux are the three release-gating platforms** -
  a release is only published once all three succeed. The Windows job's
  installer is genuinely install/launch/uninstall-tested, and the Linux
  job's bundle is genuinely runtime-tested (real native-engine load, real
  BLAKE3 hashing, real duplicate detection), on the runner itself before
  anything is published - not just compiled. No `continue-on-error`
  anywhere in this set: if any of the three fails, it fails honestly and
  the release does not happen.
- **macOS is built on a GitHub-hosted runner as a compile-health check
  only** (`continue-on-error: true`, so a failure here never blocks the
  release) and its output is deliberately *not* attached to a release: it
  compiles (fixed 2026-08-11, run 31437939750 - see the macOS section
  above), but its packaged `.app` doesn't bundle the native engine library
  yet, the same gap Linux had until this fix (run ID recorded in the
  Linux section above). This is not a claim that macOS support doesn't
  work at the source level (see README's Known Limitations) - only that
  the *packaged, distributable* artifact isn't ready yet, for one
  precisely identified, already-solved-once-for-Linux reason.
- The workflow also supports manual `workflow_dispatch` runs (for testing
  the pipeline itself without cutting a release) - these compute a
  placeholder `0.0.0-dev.<run number>` version and run every job above,
  but the final release-publishing job only ever runs for an actual
  `vX.Y.Z` tag push, never from a manual run or an arbitrary branch.
