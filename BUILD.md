# Build

**SUPPORTED PLATFORM: Windows 10/11 x64.** This is the only platform Dupora
builds or ships for.

## Prerequisites

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
  manual copying during development. `windows/CMakeLists.txt` handles
  bundling `dupora_engine.dll` next to the packaged release exe - see
  below.

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
and the portable ZIP.

## Verifying without a full build

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
every pull request, plus a Windows release-build job, all on
`windows-latest`.

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
generated installer on the runner as a smoke test. Once that job succeeds,
a final job generates `SHA256SUMS.txt` and publishes a GitHub Release for
the tag with all artifacts attached.

**Version numbers are never hardcoded in the workflow.** The tag itself
(`vX.Y.Z`) is the single source of truth; a `prepare` job parses it and
passes the result to every other job via `flutter build --build-name=...
--build-number=...` (for the app) and a WiX `-d AppVersion=...` variable
(for the installer), keeping the tag, the built app, and the installer
version consistent.

**What CI actually produces:**

- **The Windows job is release-gating.** A release is only published once
  it succeeds. The installer is genuinely install/launch/uninstall-tested
  on the runner itself before anything is published - not just compiled.
  No `continue-on-error`: if the job fails, it fails honestly and the
  release does not happen.
- The workflow also supports manual `workflow_dispatch` runs (for testing
  the pipeline itself without cutting a release) - these compute a
  placeholder `0.0.0-dev.<run number>` version and run every job above,
  but the final release-publishing job only ever runs for an actual
  `vX.Y.Z` tag push, never from a manual run or an arbitrary branch.
