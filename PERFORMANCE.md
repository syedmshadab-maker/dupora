# Performance

**SUPPORTED PLATFORM: Windows 10/11 x64.**

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

## Measured results (real, not estimated)

`integration_test/stress_test.dart` runs the actual compiled Windows exe
(not a mock, not the engine in isolation) against a generated dataset and
prints real numbers. This is what was actually observed on this
single-VM, no-HDD, no-multi-terabyte-dataset build machine - see "What
wasn't measured" below for the honest boundary of what this does and
doesn't demonstrate.

**Dataset:** 5,000 files - 400 duplicate groups of 10 identical files each
(4,000 files), plus 1,000 unique files. Files are small (a few hundred
bytes each) - this stresses per-file/per-isolate dispatch overhead, not
raw hashing throughput on large files (see `dataset_test.dart` for that:
a 3 MiB pair correctly exercises the mmap path in well under a second).

| Metric | Result |
|---|---|
| Dataset generation (5,000 files) | ~2.9s |
| Cold scan, 5,000 files on disk / 4,000 hashed (1,000 unique-sized files correctly never hashed at all - Stage 1 filtering) | **44.0s wall clock (~91 files/sec average)** |
| Correctness at this scale | 400/400 groups found exactly, 0 false positives, 0 false negatives, 0 errors |
| Repeated scan of the same unchanged tree (fully cached) | **3.7s - 11.8x faster than the cold scan** |
| Peak process memory during the cold scan (`ProcessInfo.currentRss`, measured from inside the running app) | baseline 259.6 MB → peak 333.6 MB (**+74.1 MB** for 5,000 files in flight) |
| Mid-scan cancellation under this load | confirmed stops promptly |

**Honest read of the 91 files/sec number:** this is measured, not
hypothetical, and it is *not* a number to be proud of in isolation - for
files this small, per-file overhead (isolate dispatch, native FFI call
setup, SQLite cache round-trip) dominates over actual BLAKE3 compute time,
which is genuinely fast (nanoseconds to microseconds for a few hundred
bytes). A real-world dataset with a more typical size distribution
(documents, photos, videos - KB to GB, not uniformly tiny) would see much
higher effective throughput, since large-file hashing time would then
dominate instead of per-file dispatch overhead - `dataset_test.dart`'s
3 MiB pair hashes in a small fraction of a second, consistent with that.
The 11.8x cache speedup is the number that matters most for real-world
"scan the same folder again" usage, and it held up under load, not just
in the cache's own unit tests.

## What wasn't measured

This build ran entirely on a single Windows development VM with no HDD, no
USB 2.0 device, and no multi-terabyte dataset available to test against.
The stress test above measures *thousands* of files, not the *millions*
the spec's performance targets ultimately describe - per the explicit
instruction not to claim multi-million-file performance without measuring
it, that claim is not made here. The following remain *design intentions
backed by correctness tests*, not measured performance claims:

- Throughput at the 100,000 / 1,000,000-file scales.
- Memory behavior at those scales (5,000 files measured +74MB; the
  architecture is designed to avoid per-file heavy objects at any scale -
  see "Bounded worker pool" above - but this wasn't verified beyond
  5,000).
- The 64 MiB / 4-core parallel-hashing thresholds were not tuned against
  measured data on spinning disks, USB drives, or varied CPU configurations
  - they encode the qualitative guidance in the spec ("do not blindly
    parallelize HDD/USB spinning-disk workloads") as fixed constants rather
    than runtime-measured decisions.
- Thumbnail generation throughput/memory ceiling under a results grid with
  thousands of entries.
- Performance on spinning disks (HDD) or USB 2.0 - only the VM's own SSD
  was available.

Anyone taking this further in a real environment should start by running
`integration_test/stress_test.dart` with a larger `_totalFiles` value and a
more realistic size distribution, with DevTools attached, and validating
(or retuning) the constants named above against what's actually observed.
