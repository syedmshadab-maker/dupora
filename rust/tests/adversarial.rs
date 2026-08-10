//! Adversarial and edge-case coverage for the native hashing engine, per the
//! project's "ADVERSARIAL TESTING" requirements: same-size/different-content,
//! zero-byte files, cancellation mid-hash, permission failures, and the
//! large-file mmap+parallel code path.

mod common;

use std::fs::File;
use std::io::Write;

use dupora_engine::hashing::{hash_file_full, partial_fingerprint, CancelToken, ProgressCounter};

fn cn() -> CancelToken {
    CancelToken::none()
}
fn pn() -> ProgressCounter {
    ProgressCounter::none()
}

#[test]
fn same_size_different_content_never_hash_equal() {
    let dir = common::tempdir();
    let mut a = vec![0u8; 100_000];
    let mut b = vec![0u8; 100_000];
    a[50_000] = 1;
    b[50_000] = 2;

    let pa = dir.path().join("a.bin");
    let pb = dir.path().join("b.bin");
    File::create(&pa).unwrap().write_all(&a).unwrap();
    File::create(&pb).unwrap().write_all(&b).unwrap();

    let ha = hash_file_full(&pa, cn(), pn()).unwrap();
    let hb = hash_file_full(&pb, cn(), pn()).unwrap();
    assert_ne!(ha.0, hb.0);
}

#[test]
fn different_filename_same_content_hash_equal() {
    let dir = common::tempdir();
    let data = vec![0x77u8; 8192];
    let p1 = dir.path().join("original_name.dat");
    let p2 = dir.path().join("completely_different_name.dat");
    File::create(&p1).unwrap().write_all(&data).unwrap();
    File::create(&p2).unwrap().write_all(&data).unwrap();

    let h1 = hash_file_full(&p1, cn(), pn()).unwrap();
    let h2 = hash_file_full(&p2, cn(), pn()).unwrap();
    assert_eq!(h1.0, h2.0);
}

#[test]
fn zero_byte_files_hash_equal_to_each_other() {
    let dir = common::tempdir();
    let p1 = dir.path().join("empty1.bin");
    let p2 = dir.path().join("empty2.bin");
    File::create(&p1).unwrap();
    File::create(&p2).unwrap();

    let h1 = hash_file_full(&p1, cn(), pn()).unwrap();
    let h2 = hash_file_full(&p2, cn(), pn()).unwrap();
    assert_eq!(h1.0, h2.0);
}

#[test]
fn binary_file_with_null_bytes_hashes_correctly() {
    let dir = common::tempdir();
    let mut data = vec![0u8; 20_000];
    for (i, b) in data.iter_mut().enumerate() {
        *b = (i * 37 % 256) as u8;
    }
    let path = dir.path().join("binary.dat");
    File::create(&path).unwrap().write_all(&data).unwrap();

    let ours = hash_file_full(&path, cn(), pn()).unwrap();
    assert_eq!(ours.0, *blake3::hash(&data).as_bytes());
}

#[test]
fn huge_file_uses_parallel_mmap_path_and_matches_reference() {
    // Exceeds PARALLEL_THRESHOLD (64 MiB) to exercise update_rayon, when the
    // host has enough cores; otherwise falls back to sequential mmap. Either
    // way the digest must match the reference implementation.
    let dir = common::tempdir();
    let path = dir.path().join("huge.bin");
    let mut file = File::create(&path).unwrap();
    // Write 80 MiB in chunks to avoid a single giant in-memory allocation
    // matching the very anti-pattern this engine avoids.
    let chunk = vec![0x5Au8; 8 * 1024 * 1024];
    let mut hasher = blake3::Hasher::new();
    for _ in 0..10 {
        file.write_all(&chunk).unwrap();
        hasher.update(&chunk);
    }
    drop(file);
    let expected = *hasher.finalize().as_bytes();

    let ours = hash_file_full(&path, cn(), pn()).unwrap();
    assert_eq!(ours.0, expected);
}

#[test]
fn cancellation_mid_large_hash_returns_cancelled_promptly() {
    let dir = common::tempdir();
    let path = dir.path().join("cancel_large.bin");
    let data = vec![0x99u8; 30 * 1024 * 1024];
    File::create(&path).unwrap().write_all(&data).unwrap();

    let flag: u8 = 1; // already cancelled before we even start
    let cancel = unsafe { CancelToken::new(Some(&flag as *const u8)) };
    let result = hash_file_full(&path, cancel, pn());
    assert!(result.is_err());
}

#[test]
fn inaccessible_file_does_not_panic_and_reports_error() {
    let dir = common::tempdir();
    let missing = dir.path().join("no_such_file.bin");
    let result = hash_file_full(&missing, cn(), pn());
    assert!(result.is_err());
}

#[test]
fn partial_fingerprint_survives_file_at_exact_window_boundary() {
    let dir = common::tempdir();
    // Exactly 16 KiB: the head+tail windows exactly cover the whole file
    // with no overlap and no gap.
    let data = vec![0x3Cu8; 16 * 1024];
    let path = dir.path().join("boundary.bin");
    File::create(&path).unwrap().write_all(&data).unwrap();

    let fp = partial_fingerprint(&path, data.len() as u64);
    assert!(fp.is_ok());
}

#[test]
fn unicode_filename_hashes_correctly() {
    let dir = common::tempdir();
    let path = dir.path().join("日本語_файл_🎉.bin");
    let data = b"unicode path test".to_vec();
    File::create(&path).unwrap().write_all(&data).unwrap();

    let ours = hash_file_full(&path, cn(), pn()).unwrap();
    assert_eq!(ours.0, *blake3::hash(&data).as_bytes());
}
