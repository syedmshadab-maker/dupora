# Performance

## Design choices and their rationale

### Adaptive hashing strategy (`rust/src/hashing/blake3_engine.rs`)

| File size | Strategy | Why |
|---|---|---|
| 0 bytes | Direct `blake3::hash(&[])`, no I/O | Avoids opening a mmap/buffered reader for nothing. |
| ≤ 1 MiB | Buffered stream, 256 KiB chunks | mmap setup cost isn't worth it for small files. |
| \> 1 MiB | Memory-mapped, sequential `update()` in 8 MiB chunks | Lets the OS page cache manage residency instead of the process heap holding the file; chunking (rather than one `update()` call over the whole mapping) keeps cancellation/progress responsive. |
| ≥ 64 MiB **and** ≥ 4 logical cores | Memory-mapped, `update_rayon()` (multi-threaded BLAKE3 tree hashing) | BLAKE3's tree structure parallelizes cleanly on large inputs; below this size or core count, thread-pool spin-up cost exceeds the benefit. |

The 64 MiB / 4-core thresholds are conservative, documented constants
(`PARALLEL_THRESHOLD`, `MIN_CORES_FOR_PARALLEL`) rather than the result of a
tuning pass on real hardware variety - see "What wasn't benchmarked" below.
Critically, **parallelism is never applied blindly**: a HDD/USB device
doesn't get faster because more CPU threads are reading from it
concurrently, and the spec explicitly warns against this. The current
implementation's only signal for "is this worth parallelizing" is file size
+ core count; it does not detect rotational vs. solid-state media. See
Known Limitations in README.md.

### Never loads a whole file into memory

Buffered mode streams through a 256 KiB `Vec<u8>` buffer, reused across
reads. mmap mode never copies file bytes into the Rust heap at all - the OS
maps pages on demand. Neither path scales with file size in *process heap*
usage; a 20 GB file costs the same handful of KiB in Rust-owned memory as a
20 MB one.

### Bounded worker pool, not per-file isolates

`HashWorkerPool` spawns `recommendedWorkerCount()` isolates once per scan
(clamped to [2, 16]) and reuses them for every hash job in that scan. A
1,000,000-file scan does not spawn 1,000,000 isolates, File objects, or
thumbnails - see ARCHITECTURE.md's concurrency section and the project
spec's explicit "do not create unlimited isolates/tasks" / "must not
require 1,000,000 full File objects + all hashes in RAM" requirements.

### Cache-first hashing

Every Stage 2/3 hash call is preceded by a cache lookup
(`HashCacheRepository.lookup`); a cache hit skips the native call entirely.
`test/features/scanner/scan_engine_test.dart`'s incremental-rescan test
demonstrates this behaviorally. This is the single largest real-world
performance lever for repeat scans of mostly-unchanged trees, larger than
any hashing-algorithm micro-optimization.

### Throttled progress emission

`ScanProgress` is emitted on a 250ms timer, not per-file/per-byte, so the
UI never rebuilds faster than a human can perceive regardless of scan
throughput (spec: "do not rebuild the entire UI tree on every byte read").

## Benchmark suite

`rust/tests/adversarial.rs::huge_file_uses_parallel_mmap_path_and_matches_reference`
exercises the parallel code path functionally (correctness, not throughput)
against an 80 MiB generated file. A dedicated `criterion`-based
micro-benchmark harness (comparing buffered vs. mmap vs. mmap+parallel
throughput numerically, per the spec's "Create a benchmark suite" /
"Compare: buffered BLAKE3 / mmap BLAKE3 / parallel BLAKE3") was scoped but
not implemented in this pass - see Known Limitations.

## What wasn't benchmarked on real hardware

This build ran entirely on a single Windows development VM with no HDD, no
USB 2.0 device, and no multi-terabyte dataset available to test against.
The compiled Windows release executable was verified end-to-end at small
scale (a handful of files) via `integration_test/app_test.dart` - see
TESTING.md - which proves *functional correctness* of the real exe
(scanning, hashing, deletion all genuinely work), but that test says
nothing about throughput at scale. The following remain *design intentions
backed by correctness tests*, not measured performance claims:

- Actual files/sec and MB/sec throughput at the 10,000 / 100,000 /
  1,000,000-file scales the spec targets.
- Real memory-usage profiling of a million-file scan (the architecture is
  designed to avoid holding per-file heavy objects, per above, but this was
  not profiled with a memory profiler against a real million-file tree).
- The 64 MiB / 4-core parallel-hashing thresholds were not tuned against
  measured data on spinning disks, USB drives, or varied CPU configurations
  - they encode the qualitative guidance in the spec ("do not blindly
    parallelize HDD/USB spinning-disk workloads") as fixed constants rather
    than runtime-measured decisions.
- Thumbnail generation throughput/memory ceiling under a results grid with
  thousands of entries.

Anyone taking this further in a real environment should start by running
the app against a representative dataset with `--profile`/DevTools attached
and validating (or retuning) the constants named above.
