use std::fs::File;
use std::io::{BufReader, Read};
use std::path::Path;

use super::{CancelToken, ProgressCounter, DIGEST_LEN};
use crate::error::{EngineError, EngineResult};

/// Files at or below this size are read via a plain buffered stream; mmap
/// setup overhead is not worth it for tiny files.
const SMALL_FILE_THRESHOLD: u64 = 1024 * 1024; // 1 MiB
/// Files at or above this size become candidates for multi-threaded BLAKE3
/// tree hashing (`update_rayon`), provided the machine has enough cores.
/// Below this the file is still mmap'd, but hashed on a single thread:
/// spinning up the rayon pool costs more than it saves for smaller inputs,
/// and unnecessary parallelism on HDD/USB devices just contends for the same
/// disk head anyway.
const PARALLEL_THRESHOLD: u64 = 64 * 1024 * 1024; // 64 MiB
/// Granularity at which we re-check cancellation / publish progress while
/// hashing a memory-mapped file.
const MMAP_CHUNK: usize = 8 * 1024 * 1024; // 8 MiB
/// Buffer size for the small-file buffered path.
const BUFFERED_CHUNK: usize = 256 * 1024; // 256 KiB
/// Minimum logical core count before parallel BLAKE3 is considered worthwhile.
const MIN_CORES_FOR_PARALLEL: usize = 4;

#[derive(Debug)]
pub struct FileHash(pub [u8; DIGEST_LEN]);

/// Hash `path` end-to-end with BLAKE3, choosing a buffered, mmap, or
/// mmap+parallel strategy adaptively based on file size and hardware.
///
/// Never materializes the whole file in a `Vec`: buffered reads stream
/// through a bounded buffer, and the mmap paths let the OS page cache manage
/// residency instead of the process heap holding the entire file.
pub fn hash_file_full(
    path: &Path,
    cancel: CancelToken,
    progress: ProgressCounter,
) -> EngineResult<FileHash> {
    let path_str = path.to_string_lossy().to_string();
    let file = File::open(path).map_err(|e| EngineError::from_io_at(e, &path_str))?;
    let meta = file
        .metadata()
        .map_err(|e| EngineError::from_io_at(e, &path_str))?;
    let len = meta.len();

    if len == 0 {
        progress.set(0);
        return Ok(FileHash(*blake3::hash(&[]).as_bytes()));
    }

    if len <= SMALL_FILE_THRESHOLD {
        return hash_buffered(file, cancel, progress);
    }

    match hash_mmap(&file, len, cancel, progress) {
        Ok(h) => Ok(h),
        Err(EngineError::Cancelled) => Err(EngineError::Cancelled),
        // Some filesystems (network shares, certain FUSE/SAF-backed mounts)
        // do not support mmap; gracefully fall back to buffered streaming
        // rather than failing the whole scan.
        Err(_) => {
            use std::io::Seek;
            let mut file = File::open(path).map_err(|e| EngineError::from_io_at(e, &path_str))?;
            file.seek(std::io::SeekFrom::Start(0))
                .map_err(|e| EngineError::from_io_at(e, &path_str))?;
            hash_buffered(file, cancel, progress)
        }
    }
}

fn hash_buffered(
    file: File,
    cancel: CancelToken,
    progress: ProgressCounter,
) -> EngineResult<FileHash> {
    let mut reader = BufReader::with_capacity(BUFFERED_CHUNK, file);
    let mut hasher = blake3::Hasher::new();
    let mut buf = vec![0u8; BUFFERED_CHUNK];
    let mut processed: u64 = 0;

    loop {
        if cancel.is_cancelled() {
            return Err(EngineError::Cancelled);
        }
        let n = reader.read(&mut buf).map_err(EngineError::Io)?;
        if n == 0 {
            break;
        }
        hasher.update(&buf[..n]);
        processed += n as u64;
        progress.set(processed);
    }

    Ok(FileHash(*hasher.finalize().as_bytes()))
}

fn hash_mmap(
    file: &File,
    len: u64,
    cancel: CancelToken,
    progress: ProgressCounter,
) -> EngineResult<FileHash> {
    // SAFETY: the file handle is exclusively ours for the duration of this
    // call. External mutation of the underlying file while mapped is an
    // inherent mmap risk (see SECURITY.md: "files changing during scan").
    let mmap = unsafe { memmap2::Mmap::map(file) }.map_err(EngineError::Io)?;

    let use_parallel = len >= PARALLEL_THRESHOLD && num_cpus::get() >= MIN_CORES_FOR_PARALLEL;

    let mut hasher = blake3::Hasher::new();
    let mut offset: usize = 0;
    let total = mmap.len();

    while offset < total {
        if cancel.is_cancelled() {
            return Err(EngineError::Cancelled);
        }
        let end = (offset + MMAP_CHUNK).min(total);
        let slice = &mmap[offset..end];
        if use_parallel {
            hasher.update_rayon(slice);
        } else {
            hasher.update(slice);
        }
        offset = end;
        progress.set(offset as u64);
    }

    Ok(FileHash(*hasher.finalize().as_bytes()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;

    fn cancel_none() -> CancelToken {
        CancelToken::none()
    }
    fn progress_none() -> ProgressCounter {
        ProgressCounter::none()
    }

    #[test]
    fn empty_file_matches_reference_blake3_empty_hash() {
        let dir = crate::test_util::tempdir();
        let path = dir.path().join("empty.bin");
        File::create(&path).unwrap();

        let result = hash_file_full(&path, cancel_none(), progress_none()).unwrap();
        assert_eq!(result.0, *blake3::hash(&[]).as_bytes());
    }

    #[test]
    fn small_and_large_paths_agree_with_reference_blake3() {
        let dir = crate::test_util::tempdir();

        // Small (buffered) path.
        let small_path = dir.path().join("small.bin");
        let small_data: Vec<u8> = (0..10_000u32).map(|i| (i % 251) as u8).collect();
        File::create(&small_path)
            .unwrap()
            .write_all(&small_data)
            .unwrap();
        let small_result = hash_file_full(&small_path, cancel_none(), progress_none()).unwrap();
        assert_eq!(small_result.0, *blake3::hash(&small_data).as_bytes());

        // Large (mmap, single-threaded) path: > SMALL_FILE_THRESHOLD but
        // below PARALLEL_THRESHOLD.
        let large_path = dir.path().join("large.bin");
        let large_data: Vec<u8> = (0..2_500_000u32).map(|i| (i % 251) as u8).collect();
        File::create(&large_path)
            .unwrap()
            .write_all(&large_data)
            .unwrap();
        let large_result = hash_file_full(&large_path, cancel_none(), progress_none()).unwrap();
        assert_eq!(large_result.0, *blake3::hash(&large_data).as_bytes());
    }

    #[test]
    fn cancellation_is_honored() {
        let dir = crate::test_util::tempdir();
        let path = dir.path().join("cancel.bin");
        let data = vec![0xABu8; 5 * 1024 * 1024];
        File::create(&path).unwrap().write_all(&data).unwrap();

        let flag: u8 = 1;
        let cancel = unsafe { CancelToken::new(Some(&flag as *const u8)) };
        let result = hash_file_full(&path, cancel, progress_none());
        assert!(matches!(result, Err(EngineError::Cancelled)));
    }

    #[test]
    fn progress_reaches_full_file_length() {
        let dir = crate::test_util::tempdir();
        let path = dir.path().join("progress.bin");
        let data = vec![0x11u8; 3 * 1024 * 1024];
        File::create(&path).unwrap().write_all(&data).unwrap();

        let mut counter: u64 = 0;
        let progress = unsafe { ProgressCounter::new(Some(&mut counter as *mut u64)) };
        hash_file_full(&path, cancel_none(), progress).unwrap();
        assert_eq!(counter, data.len() as u64);
    }

    #[test]
    fn nonexistent_file_reports_not_found() {
        let dir = crate::test_util::tempdir();
        let path = dir.path().join("does_not_exist.bin");
        let err = hash_file_full(&path, cancel_none(), progress_none()).unwrap_err();
        assert!(matches!(err, EngineError::NotFound(_)));
    }
}
