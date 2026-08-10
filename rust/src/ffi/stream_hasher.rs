//! Handle-based incremental BLAKE3 hasher, exposed over FFI for callers that
//! cannot hand Rust a filesystem path - chiefly Android's Storage Access
//! Framework, where files are exposed only through a `ContentResolver`
//! stream. The Kotlin side reads SAF chunks and forwards each one here so
//! the actual BLAKE3 computation still happens in the native engine (see
//! `android/.../SafChannel.kt`), matching the project's requirement that
//! Rust owns hashing even for SAF-backed files.

use std::collections::HashMap;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::slice;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Mutex, OnceLock};

use crate::error::StatusCode;
use crate::hashing::DIGEST_LEN;

fn registry() -> &'static Mutex<HashMap<u64, blake3::Hasher>> {
    static REGISTRY: OnceLock<Mutex<HashMap<u64, blake3::Hasher>>> = OnceLock::new();
    REGISTRY.get_or_init(|| Mutex::new(HashMap::new()))
}

fn next_handle() -> u64 {
    static NEXT: AtomicU64 = AtomicU64::new(1);
    NEXT.fetch_add(1, Ordering::Relaxed)
}

/// Creates a new incremental hasher and returns an opaque non-zero handle.
#[no_mangle]
pub extern "C" fn dupora_stream_hasher_new() -> u64 {
    let handle = next_handle();
    registry()
        .lock()
        .unwrap()
        .insert(handle, blake3::Hasher::new());
    handle
}

/// Feeds one chunk of externally-sourced bytes (e.g. from a SAF
/// `InputStream`) into the hasher identified by `handle`.
///
/// # Safety
/// `ptr` must be valid for reads of `len` bytes.
#[no_mangle]
pub unsafe extern "C" fn dupora_stream_hasher_update(
    handle: u64,
    ptr: *const u8,
    len: usize,
) -> i32 {
    let result = catch_unwind(AssertUnwindSafe(|| {
        if ptr.is_null() && len > 0 {
            return StatusCode::InvalidArgument as i32;
        }
        let bytes = if len == 0 {
            &[]
        } else {
            slice::from_raw_parts(ptr, len)
        };
        let mut map = registry().lock().unwrap();
        match map.get_mut(&handle) {
            Some(hasher) => {
                hasher.update(bytes);
                StatusCode::Ok as i32
            }
            None => StatusCode::InvalidArgument as i32,
        }
    }));
    result.unwrap_or(StatusCode::Unexpected as i32)
}

/// Finalizes and removes the hasher identified by `handle`, writing the
/// 32-byte digest to `out_hash`.
///
/// # Safety
/// `out_hash` must be valid for writes of 32 bytes.
#[no_mangle]
pub unsafe extern "C" fn dupora_stream_hasher_finalize(handle: u64, out_hash: *mut u8) -> i32 {
    let result = catch_unwind(AssertUnwindSafe(|| {
        let mut map = registry().lock().unwrap();
        match map.remove(&handle) {
            Some(hasher) => {
                let digest = hasher.finalize();
                if !out_hash.is_null() {
                    std::ptr::copy_nonoverlapping(digest.as_bytes().as_ptr(), out_hash, DIGEST_LEN);
                }
                StatusCode::Ok as i32
            }
            None => StatusCode::InvalidArgument as i32,
        }
    }));
    result.unwrap_or(StatusCode::Unexpected as i32)
}

/// Discards the hasher identified by `handle` without finalizing (used on
/// cancellation/error cleanup so the registry never leaks entries).
#[no_mangle]
pub extern "C" fn dupora_stream_hasher_abort(handle: u64) -> i32 {
    registry().lock().unwrap().remove(&handle);
    StatusCode::Ok as i32
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn incremental_hash_matches_one_shot_reference() {
        let data = b"the quick brown fox jumps over the lazy dog, repeated many times";
        let handle = dupora_stream_hasher_new();
        for chunk in data.chunks(7) {
            let status =
                unsafe { dupora_stream_hasher_update(handle, chunk.as_ptr(), chunk.len()) };
            assert_eq!(status, StatusCode::Ok as i32);
        }
        let mut out = [0u8; DIGEST_LEN];
        let status = unsafe { dupora_stream_hasher_finalize(handle, out.as_mut_ptr()) };
        assert_eq!(status, StatusCode::Ok as i32);
        assert_eq!(out, *blake3::hash(data).as_bytes());
    }

    #[test]
    fn finalize_removes_handle_so_reuse_is_rejected() {
        let handle = dupora_stream_hasher_new();
        let mut out = [0u8; DIGEST_LEN];
        unsafe { dupora_stream_hasher_finalize(handle, out.as_mut_ptr()) };
        let status = unsafe { dupora_stream_hasher_finalize(handle, out.as_mut_ptr()) };
        assert_eq!(status, StatusCode::InvalidArgument as i32);
    }

    #[test]
    fn abort_discards_without_panicking() {
        let handle = dupora_stream_hasher_new();
        let status = dupora_stream_hasher_abort(handle);
        assert_eq!(status, StatusCode::Ok as i32);
    }
}
