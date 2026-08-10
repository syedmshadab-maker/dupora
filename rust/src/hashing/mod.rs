mod blake3_engine;
mod partial;

pub use blake3_engine::hash_file_full;
pub use partial::partial_fingerprint;

/// Digest size produced by BLAKE3 (and reused for our partial fingerprint too).
pub const DIGEST_LEN: usize = 32;

/// A cooperative cancellation flag backed by memory the caller owns.
///
/// The Dart side allocates a single byte via `calloc`, passes the pointer in,
/// and may write `1` to it from any isolate at any time to request
/// cancellation. We only ever read it, so plain (non-atomic) reads are
/// sufficient: at worst we observe the cancellation one chunk late, which is
/// an explicitly acceptable trade-off for the huge reduction in cross-FFI
/// complexity (no callbacks, no shared Rust-side job registry).
#[derive(Clone, Copy)]
pub struct CancelToken {
    ptr: Option<*const u8>,
}

// SAFETY: the pointer, when present, refers to a single byte owned by the
// Dart heap for the lifetime of the FFI call and is only ever read here.
unsafe impl Send for CancelToken {}
unsafe impl Sync for CancelToken {}

impl CancelToken {
    /// # Safety
    /// `ptr`, if `Some`, must be valid for reads for the lifetime of the call.
    pub unsafe fn new(ptr: Option<*const u8>) -> Self {
        Self { ptr }
    }

    pub fn none() -> Self {
        Self { ptr: None }
    }

    #[inline]
    pub fn is_cancelled(&self) -> bool {
        match self.ptr {
            Some(p) => unsafe { std::ptr::read_volatile(p) != 0 },
            None => false,
        }
    }
}

/// A progress counter backed by memory the caller owns (a single `u64`).
///
/// The coordinator isolate polls this from a different isolate/thread than
/// the one performing the blocking FFI call, which is safe because native
/// (non-Dart-heap) memory is shared across all isolates in a process.
#[derive(Clone, Copy)]
pub struct ProgressCounter {
    ptr: Option<*mut u64>,
}

unsafe impl Send for ProgressCounter {}
unsafe impl Sync for ProgressCounter {}

impl ProgressCounter {
    /// # Safety
    /// `ptr`, if `Some`, must be valid for reads/writes for the call's lifetime.
    pub unsafe fn new(ptr: Option<*mut u64>) -> Self {
        Self { ptr }
    }

    pub fn none() -> Self {
        Self { ptr: None }
    }

    #[inline]
    pub fn set(&self, processed_bytes: u64) {
        if let Some(p) = self.ptr {
            unsafe { std::ptr::write_volatile(p, processed_bytes) };
        }
    }
}
