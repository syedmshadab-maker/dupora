# Architecture

**SUPPORTED PLATFORM: Windows 10/11 x64.**

## Overview

Dupora is a Flutter (Dart) application with a Rust native engine, targeting
Windows 10/11 x64.

```
┌─────────────────────────────────────────────────────────────┐
│  Flutter / Dart (UI, orchestration, filesystem, database)    │
│                                                                │
│  lib/ui/            Screens, widgets, AppController           │
│  lib/features/       storage · scanner · duplicates · preview │
│                       deletion · settings · cache              │
│  lib/core/native/    dart:ffi bindings to the Rust engine      │
└───────────────────────────┬────────────────────────────────┘
                             │ dart:ffi (C ABI)
┌───────────────────────────┴────────────────────────────────┐
│  Rust (rust/) - dupora_engine                                 │
│  Streaming BLAKE3 hashing, partial fingerprinting,             │
│  adaptive buffered/mmap/parallel strategy                      │
└─────────────────────────────────────────────────────────────┘
```

Rust owns exactly the performance/correctness-critical hashing path. File
discovery, the duplicate-detection funnel's orchestration, the persistent
cache, and all UI/state live in Dart. This keeps the FFI surface small
(4 functions) and lets the bulk of the application be written, tested, and
iterated on in a single language.

## Key engineering decisions

### Hand-rolled `dart:ffi` instead of `flutter_rust_bridge`

The original brief suggested `flutter_rust_bridge`. It was dropped in favor
of a small, hand-written `extern "C"` surface (`rust/src/ffi/`) plus
matching `dart:ffi` bindings (`lib/core/native/`), for three reasons:

1. **Toolchain risk.** `flutter_rust_bridge_codegen` is itself a substantial
   Rust program with its own dependency tree, and needed to work at the same
   moment as a brand-new Rust toolchain, a brand-new Flutter SDK, and no
   internet-cached build artifacts. A hand-rolled binding has no codegen
   step to fail.
2. **The async/callback problem it solves isn't needed here.** FRB's main
   complexity is bridging async Rust work back to Dart via generated
   callback/stream plumbing. This project's hashing calls are simple,
   bounded, synchronous C functions; Dart achieves concurrency by calling
   them from background isolates (see below), not by making Rust async.
3. **Progress/cancellation via shared memory, not callbacks.** The scan
   engine's cancellation token and progress counter are single bytes/words
   of `calloc`-allocated native memory. Dart passes a pointer in; Rust reads
   it every I/O chunk (cancellation) or writes to it every chunk (progress).
   A different Dart isolate polls the same address concurrently. This works
   because non-Dart-heap memory is shared across all isolates in a process,
   and it is both simpler and cheaper than marshaling callback invocations
   across the FFI boundary.

This is documented as a deliberate deviation per the brief's own instruction
to prefer a better engineering solution over the originally suggested one
when it improves reliability/maintainability.

### Concurrency model: bounded isolate pool, blocking native calls

`HashWorkerPool` (`lib/features/scanner/data/hash_worker_pool.dart`) spawns
a **fixed** number of persistent Dart isolates (`recommendedWorkerCount()`,
derived from `dupora_logical_cpu_count()` and clamped to [2, 16] - "do not
create unlimited isolates/tasks" per spec). Each worker isolate makes a
**synchronous, blocking** call into the native engine. Blocking is
harmless because:

- it happens on a background isolate, never the UI isolate;
- the coordinator isolate observes progress by polling native memory, not
  by waiting on the blocked call to return.

Jobs (`HashJob`) queue in the pool when all workers are busy; a worker pulls
the next queued job the instant it frees up. This gives bounded, backpressured
concurrency without ever spawning a new isolate per file.

### Database: Drift (SQLite) over Isar

The spec explicitly allowed Isar "if it remains the best choice." It does
not: Isar's last release predates this project's Dart/Flutter SDK versions
and its upstream maintenance has stalled (a community fork exists, itself a
signal of the risk). For a *persistent cache that must survive SDK
upgrades*, that's a correctness/longevity risk this project isn't willing
to take. Drift wraps SQLite - transactional, actively maintained, and the
most battle-tested embedded database that exists - with a type-safe Dart
query layer and code generation via `build_runner`. See
`lib/features/cache/hash_cache_database.dart`.

### Duplicate detection funnel

`lib/features/scanner/data/duplicate_funnel.dart` implements Stage 1-3 as
pure, dependency-free grouping functions (no isolates, no native calls, no
I/O), so they're trivially unit-testable:

```
groupBySizeCandidates      Stage 1: group by exact size, drop singletons
groupByPartialCandidates   Stage 2: sub-group by 8KB head+tail fingerprint
groupByFullHashCandidates  Stage 3: sub-group by full BLAKE3 -> DuplicateGroup
```

`ScanEngine` (`lib/features/scanner/scan_engine.dart`) orchestrates: it
calls Stage 0 discovery, applies the pure grouping functions, and dispatches
the actual hashing (Stage 2/3) through the cache and worker pool described
above. A file only ever reaches Stage 3 full hashing if it survived *both*
Stage 1 (unique size excluded) and Stage 2 (unique partial fingerprint
excluded) - the latter is a correctness deduction, not a heuristic: a
different partial fingerprint proves the files' head/tail bytes differ,
so their full content cannot be identical.

### Progress reporting

`ScanProgress` is a single immutable snapshot broadcast on a throttled
stream (`Timer.periodic(250ms)` in `ScanEngine`), not re-emitted per file or
per byte - "the UI must not rebuild on every byte read" per spec. Byte-level
throughput/ETA is computed from Stage 3's native progress counters (summed
across in-flight jobs) rather than Stage 0-2, since Stage 3 is where the
overwhelming majority of I/O time is spent for realistic workloads.

### Storage detection and deletion: Windows-only, with a seam for future device support

`StorageDetector` and `PlatformDeleter` are small factory-backed interfaces
(`lib/features/storage/data/storage_detector.dart`,
`lib/features/deletion/safe_delete_service.dart`) with a single Windows
implementation today (`storage_detector_windows.dart`,
`safe_delete_windows.dart`). The factory shape (`StorageDetector
.forPlatform()`, `PlatformDeleter.forPlatform()`) is kept deliberately,
rather than collapsing to a direct constructor call, so a future
Windows-native Portable Devices/MTP implementation (for Android
phones/tablets connected over USB that don't expose a drive letter) has a
seam to plug into without touching any call site. That feature is not
implemented yet - see README's Known Limitations.

## Directory layout

```
lib/
  core/
    native/       dart:ffi bindings + high-level hashing wrapper
    utils/        small platform-detail helpers (file attributes)
  features/
    storage/      Windows volume detection (domain + data)
    scanner/      Stage 0 discovery, funnel, worker pool, ScanEngine
    duplicates/   DuplicateGroup, smart-selection strategies
    cache/        Drift schema + repository (incremental scanning)
    preview/      thumbnail generation/caching
    deletion/     safe-delete coordinator + Windows Recycle Bin delete
    settings/     settings model + persistence
  ui/
    screens/      Home, Scan, Results, Settings
    state/        AppController (single ChangeNotifier)
    widgets/      shared presentational widgets

rust/
  src/
    hashing/      adaptive BLAKE3 engine + partial fingerprint
    ffi/          extern "C" surface
  tests/          golden BLAKE3 vectors + adversarial cases
```
