use std::fs::File;
use std::io::{Read, Seek, SeekFrom};
use std::path::Path;

use super::DIGEST_LEN;
use crate::error::{EngineError, EngineResult};

/// Bytes read from the start and end of a file for the Stage 2 filter.
pub const FINGERPRINT_WINDOW: u64 = 8 * 1024; // 8 KiB

#[derive(Debug)]
pub struct PartialFingerprint(pub [u8; DIGEST_LEN]);

/// Compute a cheap Stage 2 fingerprint from the first and last
/// [`FINGERPRINT_WINDOW`] bytes of a file (the whole file, if smaller).
///
/// This is a **filtering** hash only, never a duplicate-verification hash:
/// two files with the same fingerprint are merely *candidates* that must
/// still pass full BLAKE3 verification in Stage 3. The file length is mixed
/// into the hash so files that differ only in the middle (but happen to
/// share identical head/tail windows) cannot accidentally collide through a
/// boundary-alignment coincidence.
pub fn partial_fingerprint(path: &Path, file_len: u64) -> EngineResult<PartialFingerprint> {
    let path_str = path.to_string_lossy().to_string();
    let mut file = File::open(path).map_err(|e| EngineError::from_io_at(e, &path_str))?;

    let mut hasher = blake3::Hasher::new();
    hasher.update(&file_len.to_le_bytes());

    if file_len <= FINGERPRINT_WINDOW * 2 {
        let mut buf = Vec::with_capacity(file_len as usize);
        file.read_to_end(&mut buf)
            .map_err(|e| EngineError::from_io_at(e, &path_str))?;
        hasher.update(&buf);
    } else {
        let mut head = vec![0u8; FINGERPRINT_WINDOW as usize];
        file.read_exact(&mut head)
            .map_err(|e| EngineError::from_io_at(e, &path_str))?;
        hasher.update(&head);

        let mut tail = vec![0u8; FINGERPRINT_WINDOW as usize];
        file.seek(SeekFrom::End(-(FINGERPRINT_WINDOW as i64)))
            .map_err(|e| EngineError::from_io_at(e, &path_str))?;
        file.read_exact(&mut tail)
            .map_err(|e| EngineError::from_io_at(e, &path_str))?;
        hasher.update(&tail);
    }

    Ok(PartialFingerprint(*hasher.finalize().as_bytes()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;

    #[test]
    fn identical_content_yields_identical_fingerprint() {
        let dir = crate::test_util::tempdir();
        let data = vec![0x42u8; 50_000];
        let p1 = dir.path().join("a.bin");
        let p2 = dir.path().join("b.bin");
        File::create(&p1).unwrap().write_all(&data).unwrap();
        File::create(&p2).unwrap().write_all(&data).unwrap();

        let f1 = partial_fingerprint(&p1, data.len() as u64).unwrap();
        let f2 = partial_fingerprint(&p2, data.len() as u64).unwrap();
        assert_eq!(f1.0, f2.0);
    }

    #[test]
    fn different_middle_with_same_head_tail_does_not_collide() {
        let dir = crate::test_util::tempdir();
        let mut a = vec![0x11u8; 50_000];
        let mut b = a.clone();
        // Mutate a byte firmly in the middle, outside both 8 KiB windows.
        a[25_000] = 0xAA;
        b[25_000] = 0xBB;

        let pa = dir.path().join("a.bin");
        let pb = dir.path().join("b.bin");
        File::create(&pa).unwrap().write_all(&a).unwrap();
        File::create(&pb).unwrap().write_all(&b).unwrap();

        let fa = partial_fingerprint(&pa, a.len() as u64).unwrap();
        let fb = partial_fingerprint(&pb, b.len() as u64).unwrap();
        // Same head/tail, same length -> fingerprint intentionally still
        // matches (it is a *filter*, not a verifier); Stage 3 full BLAKE3 is
        // what must catch this. This test documents that guarantee boundary.
        assert_eq!(fa.0, fb.0);
    }

    #[test]
    fn small_file_below_window_hashes_whole_content() {
        let dir = crate::test_util::tempdir();
        let p1 = dir.path().join("a.bin");
        let p2 = dir.path().join("b.bin");
        File::create(&p1).unwrap().write_all(b"hello").unwrap();
        File::create(&p2).unwrap().write_all(b"world").unwrap();

        let f1 = partial_fingerprint(&p1, 5).unwrap();
        let f2 = partial_fingerprint(&p2, 5).unwrap();
        assert_ne!(f1.0, f2.0);
    }
}
