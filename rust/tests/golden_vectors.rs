//! Verifies our engine against BLAKE3's own official published test
//! vectors, not merely "two runs agree with each other". Vectors were
//! downloaded and copied verbatim from the reference implementation's
//! `test_vectors.json`
//! (https://github.com/BLAKE3-team/BLAKE3/blob/master/test_vectors/test_vectors.json),
//! whose inputs are defined as `input[i] = i % 251`, truncated here to the
//! standard 32-byte digest length.

mod common;

use std::fs::File;
use std::io::Write;

use dupora_engine::hashing::{hash_file_full, CancelToken, ProgressCounter};

struct Vector {
    input_len: usize,
    hash_hex32: &'static str,
}

const VECTORS: &[Vector] = &[
    Vector {
        input_len: 0,
        hash_hex32: "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262",
    },
    Vector {
        input_len: 1,
        hash_hex32: "2d3adedff11b61f14c886e35afa036736dcd87a74d27b5c1510225d0f592e213",
    },
    Vector {
        input_len: 63,
        hash_hex32: "e9bc37a594daad83be9470df7f7b3798297c3d834ce80ba85d6e207627b7db7b",
    },
    Vector {
        input_len: 64,
        hash_hex32: "4eed7141ea4a5cd4b788606bd23f46e212af9cacebacdc7d1f4c6dc7f2511b98",
    },
    Vector {
        input_len: 65,
        hash_hex32: "de1e5fa0be70df6d2be8fffd0e99ceaa8eb6e8c93a63f2d8d1c30ecb6b263dee",
    },
    Vector {
        input_len: 1024,
        hash_hex32: "42214739f095a406f3fc83deb889744ac00df831c10daa55189b5d121c855af7",
    },
    Vector {
        input_len: 2048,
        hash_hex32: "e776b6028c7cd22a4d0ba182a8bf62205d2ef576467e838ed6f2529b85fba24a",
    },
];

fn make_input(len: usize) -> Vec<u8> {
    (0..len).map(|i| (i % 251) as u8).collect()
}

#[test]
fn file_hashes_match_official_blake3_test_vectors() {
    let dir = common::tempdir();
    for v in VECTORS {
        assert_eq!(
            v.hash_hex32.len(),
            64,
            "malformed vector for input_len={}",
            v.input_len
        );

        let data = make_input(v.input_len);
        let path = dir.path().join(format!("vec_{}.bin", v.input_len));
        File::create(&path).unwrap().write_all(&data).unwrap();

        let ours = hash_file_full(&path, unsafe { CancelToken::new(None) }, unsafe {
            ProgressCounter::new(None)
        })
        .unwrap();

        assert_eq!(
            hex::encode(ours.0),
            v.hash_hex32,
            "mismatch against official BLAKE3 vector for input_len={}",
            v.input_len
        );
    }
}
