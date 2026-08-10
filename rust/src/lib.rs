//! Dupora native engine: streaming BLAKE3 hashing and duplicate-detection
//! primitives, exposed to Dart via a hand-written C ABI (see [`ffi`]).
//!
//! This crate intentionally contains no I/O beyond file reads for hashing —
//! file *discovery*, size grouping, the database, and orchestration all live
//! in Dart. Rust owns exactly the performance-critical, correctness-critical
//! hashing path.

pub mod error;
pub mod ffi;
pub mod hashing;

#[cfg(test)]
mod test_util;
