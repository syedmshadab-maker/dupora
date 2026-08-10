//! Hand-rolled `dart:ffi` C ABI surface.
//!
//! We deliberately do not use `flutter_rust_bridge` here (see
//! `ARCHITECTURE.md` for the rationale). Every exported function is
//! synchronous/blocking; the Dart side calls these from background
//! isolates (never the UI isolate) so blocking is harmless, and
//! progress/cancellation are communicated through small blocks of native
//! memory the Dart side allocates and can poll or write to from any
//! isolate, without needing native-thread callback plumbing.
//!
//! Every function is wrapped in `catch_unwind`: a Rust panic must never
//! unwind across an `extern "C"` boundary (undefined behavior).

mod stream_hasher;

use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::Path;
use std::slice;

use crate::error::StatusCode;
use crate::hashing::{self, CancelToken, ProgressCounter, DIGEST_LEN};

pub use stream_hasher::{
    dupora_stream_hasher_abort, dupora_stream_hasher_finalize, dupora_stream_hasher_new,
    dupora_stream_hasher_update,
};

/// # Safety
/// `path_ptr` must point to `path_len` valid UTF-8 bytes.
unsafe fn path_from_raw<'a>(path_ptr: *const u8, path_len: usize) -> Result<&'a Path, StatusCode> {
    if path_ptr.is_null() {
        return Err(StatusCode::InvalidArgument);
    }
    let bytes = slice::from_raw_parts(path_ptr, path_len);
    match std::str::from_utf8(bytes) {
        Ok(s) => Ok(Path::new(s)),
        Err(_) => Err(StatusCode::InvalidArgument),
    }
}

unsafe fn write_digest(out_hash: *mut u8, digest: &[u8; DIGEST_LEN]) {
    if !out_hash.is_null() {
        std::ptr::copy_nonoverlapping(digest.as_ptr(), out_hash, DIGEST_LEN);
    }
}

/// Full BLAKE3 hash of a file (Stage 3 duplicate verification).
///
/// * `progress_ptr` - optional (may be null) pointer to a single `u64` the
///   caller polls from another isolate to observe bytes-processed.
/// * `cancel_ptr` - optional (may be null) pointer to a single `u8`; the
///   caller writes `1` from any isolate to request cancellation.
/// * `out_hash` - must point to a caller-owned 32-byte buffer.
///
/// Returns a [`StatusCode`] as `i32`.
///
/// # Safety
/// `path_ptr` must be valid for reads of `path_len` bytes. `progress_ptr`
/// and `cancel_ptr`, if non-null, must be valid for writes/reads
/// (respectively) for the duration of this call. `out_hash`, if non-null,
/// must be valid for writes of 32 bytes.
#[no_mangle]
pub unsafe extern "C" fn dupora_hash_file_full(
    path_ptr: *const u8,
    path_len: usize,
    progress_ptr: *mut u64,
    cancel_ptr: *const u8,
    out_hash: *mut u8,
) -> i32 {
    let result = catch_unwind(AssertUnwindSafe(|| {
        let path = match path_from_raw(path_ptr, path_len) {
            Ok(p) => p,
            Err(code) => return code as i32,
        };
        let cancel = CancelToken::new(if cancel_ptr.is_null() {
            None
        } else {
            Some(cancel_ptr)
        });
        let progress = ProgressCounter::new(if progress_ptr.is_null() {
            None
        } else {
            Some(progress_ptr)
        });

        match hashing::hash_file_full(path, cancel, progress) {
            Ok(hash) => {
                write_digest(out_hash, &hash.0);
                StatusCode::Ok as i32
            }
            Err(e) => e.status_code() as i32,
        }
    }));

    result.unwrap_or(StatusCode::Unexpected as i32)
}

/// Stage 2 partial fingerprint (head + tail + length). Filter only; never a
/// duplicate-verification result on its own.
///
/// # Safety
/// `path_ptr` must be valid for reads of `path_len` bytes. `out_hash`, if
/// non-null, must be valid for writes of 32 bytes.
#[no_mangle]
pub unsafe extern "C" fn dupora_partial_fingerprint(
    path_ptr: *const u8,
    path_len: usize,
    file_len: u64,
    out_hash: *mut u8,
) -> i32 {
    let result = catch_unwind(AssertUnwindSafe(|| {
        let path = match path_from_raw(path_ptr, path_len) {
            Ok(p) => p,
            Err(code) => return code as i32,
        };
        match hashing::partial_fingerprint(path, file_len) {
            Ok(fp) => {
                write_digest(out_hash, &fp.0);
                StatusCode::Ok as i32
            }
            Err(e) => e.status_code() as i32,
        }
    }));

    result.unwrap_or(StatusCode::Unexpected as i32)
}

/// Number of logical CPUs, used by the Dart scan engine to size its bounded
/// isolate worker pool. Centralized here so the "what counts as a capable
/// machine" heuristic lives next to the parallel-hashing threshold that uses
/// the same notion.
#[no_mangle]
pub extern "C" fn dupora_logical_cpu_count() -> usize {
    num_cpus::get()
}

/// Engine version string, primarily for diagnostics/about screens.
/// Returned pointer is `'static` (a Rust string literal) and must not be freed.
#[no_mangle]
pub extern "C" fn dupora_engine_version() -> *const std::os::raw::c_char {
    static VERSION: &str = concat!(env!("CARGO_PKG_VERSION"), "\0");
    VERSION.as_ptr() as *const std::os::raw::c_char
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs::File;
    use std::io::Write;

    #[test]
    fn ffi_roundtrip_hash_matches_direct_call() {
        let dir = crate::test_util::tempdir();
        let path = dir.path().join("ffi.bin");
        let data = vec![7u8; 4096];
        File::create(&path).unwrap().write_all(&data).unwrap();

        let path_bytes = path.to_str().unwrap().as_bytes();
        let mut out = [0u8; DIGEST_LEN];
        let status = unsafe {
            dupora_hash_file_full(
                path_bytes.as_ptr(),
                path_bytes.len(),
                std::ptr::null_mut(),
                std::ptr::null(),
                out.as_mut_ptr(),
            )
        };
        assert_eq!(status, StatusCode::Ok as i32);
        assert_eq!(out, *blake3::hash(&data).as_bytes());
    }

    #[test]
    fn ffi_reports_not_found_status() {
        let path_bytes = b"Z:\\definitely\\not\\a\\real\\path.bin".to_vec();
        let mut out = [0u8; DIGEST_LEN];
        let status = unsafe {
            dupora_hash_file_full(
                path_bytes.as_ptr(),
                path_bytes.len(),
                std::ptr::null_mut(),
                std::ptr::null(),
                out.as_mut_ptr(),
            )
        };
        assert_eq!(status, StatusCode::NotFound as i32);
    }

    #[test]
    fn ffi_invalid_utf8_path_is_rejected_not_ub() {
        let bad = [0xFFu8, 0xFEu8, 0xFDu8];
        let mut out = [0u8; DIGEST_LEN];
        let status = unsafe {
            dupora_hash_file_full(
                bad.as_ptr(),
                bad.len(),
                std::ptr::null_mut(),
                std::ptr::null(),
                out.as_mut_ptr(),
            )
        };
        assert_eq!(status, StatusCode::InvalidArgument as i32);
    }
}
