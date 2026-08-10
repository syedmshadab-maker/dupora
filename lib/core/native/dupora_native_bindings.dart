import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Raw `dart:ffi` signatures for the Rust `dupora_engine` C ABI defined in
/// `rust/src/ffi/mod.rs`. Nothing in this file does I/O beyond loading the
/// shared library; the ergonomic/async-friendly wrapper lives in
/// `hash_engine.dart`.
typedef _HashFileFullNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Uint8> pathPtr,
      ffi.Size pathLen,
      ffi.Pointer<ffi.Uint64> progressPtr,
      ffi.Pointer<ffi.Uint8> cancelPtr,
      ffi.Pointer<ffi.Uint8> outHash,
    );
typedef HashFileFullDart =
    int Function(
      ffi.Pointer<ffi.Uint8> pathPtr,
      int pathLen,
      ffi.Pointer<ffi.Uint64> progressPtr,
      ffi.Pointer<ffi.Uint8> cancelPtr,
      ffi.Pointer<ffi.Uint8> outHash,
    );

typedef _PartialFingerprintNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Uint8> pathPtr,
      ffi.Size pathLen,
      ffi.Uint64 fileLen,
      ffi.Pointer<ffi.Uint8> outHash,
    );
typedef PartialFingerprintDart =
    int Function(
      ffi.Pointer<ffi.Uint8> pathPtr,
      int pathLen,
      int fileLen,
      ffi.Pointer<ffi.Uint8> outHash,
    );

typedef _LogicalCpuCountNative = ffi.Size Function();
typedef LogicalCpuCountDart = int Function();

typedef _EngineVersionNative = ffi.Pointer<Utf8> Function();
typedef EngineVersionDart = ffi.Pointer<Utf8> Function();

typedef _StreamHasherNewNative = ffi.Uint64 Function();
typedef StreamHasherNewDart = int Function();

typedef _StreamHasherUpdateNative =
    ffi.Int32 Function(
      ffi.Uint64 handle,
      ffi.Pointer<ffi.Uint8> ptr,
      ffi.Size len,
    );
typedef StreamHasherUpdateDart =
    int Function(int handle, ffi.Pointer<ffi.Uint8> ptr, int len);

typedef _StreamHasherFinalizeNative =
    ffi.Int32 Function(ffi.Uint64 handle, ffi.Pointer<ffi.Uint8> outHash);
typedef StreamHasherFinalizeDart =
    int Function(int handle, ffi.Pointer<ffi.Uint8> outHash);

typedef _StreamHasherAbortNative = ffi.Int32 Function(ffi.Uint64 handle);
typedef StreamHasherAbortDart = int Function(int handle);

/// Digest length produced by BLAKE3 and by our partial fingerprint. Mirrors
/// `rust/src/hashing/mod.rs::DIGEST_LEN`.
const int kDigestLen = 32;

class DuporaNativeBindings {
  DuporaNativeBindings._(ffi.DynamicLibrary lib)
    : hashFileFull = lib
          .lookup<ffi.NativeFunction<_HashFileFullNative>>(
            'dupora_hash_file_full',
          )
          .asFunction(),
      partialFingerprint = lib
          .lookup<ffi.NativeFunction<_PartialFingerprintNative>>(
            'dupora_partial_fingerprint',
          )
          .asFunction(),
      logicalCpuCount = lib
          .lookup<ffi.NativeFunction<_LogicalCpuCountNative>>(
            'dupora_logical_cpu_count',
          )
          .asFunction(),
      engineVersion = lib
          .lookup<ffi.NativeFunction<_EngineVersionNative>>(
            'dupora_engine_version',
          )
          .asFunction(),
      streamHasherNew = lib
          .lookup<ffi.NativeFunction<_StreamHasherNewNative>>(
            'dupora_stream_hasher_new',
          )
          .asFunction(),
      streamHasherUpdate = lib
          .lookup<ffi.NativeFunction<_StreamHasherUpdateNative>>(
            'dupora_stream_hasher_update',
          )
          .asFunction(),
      streamHasherFinalize = lib
          .lookup<ffi.NativeFunction<_StreamHasherFinalizeNative>>(
            'dupora_stream_hasher_finalize',
          )
          .asFunction(),
      streamHasherAbort = lib
          .lookup<ffi.NativeFunction<_StreamHasherAbortNative>>(
            'dupora_stream_hasher_abort',
          )
          .asFunction();

  final HashFileFullDart hashFileFull;
  final PartialFingerprintDart partialFingerprint;
  final LogicalCpuCountDart logicalCpuCount;
  final EngineVersionDart engineVersion;
  final StreamHasherNewDart streamHasherNew;
  final StreamHasherUpdateDart streamHasherUpdate;
  final StreamHasherFinalizeDart streamHasherFinalize;
  final StreamHasherAbortDart streamHasherAbort;

  static DuporaNativeBindings? _instance;

  /// Loads (once per isolate) and returns the native engine bindings.
  ///
  /// Each Dart isolate that touches FFI must load the library itself; this
  /// is cached per-isolate via a plain static so repeated calls from the
  /// same isolate are free.
  factory DuporaNativeBindings.instance() {
    return _instance ??= DuporaNativeBindings._(_openLibrary());
  }

  static ffi.DynamicLibrary _openLibrary() {
    const libraryBaseName = 'dupora_engine';
    final candidates = <String>[];

    if (Platform.isWindows) {
      candidates.add('$libraryBaseName.dll');
    } else if (Platform.isMacOS) {
      candidates.add('lib$libraryBaseName.dylib');
    } else if (Platform.isLinux || Platform.isAndroid) {
      candidates.add('lib$libraryBaseName.so');
    } else {
      throw UnsupportedError(
        'Dupora native engine has no build for platform: ${Platform.operatingSystem}',
      );
    }

    // On desktop, also probe common development-tree locations so `flutter
    // run` / `flutter test` work straight from a source checkout without
    // needing the library pre-copied next to the Flutter build output.
    if (!Platform.isAndroid) {
      final fileName = candidates.first;
      final devSubpath = Platform.isWindows
          ? 'rust\\target\\release\\$fileName'
          : 'rust/target/release/$fileName';
      candidates.addAll([devSubpath, '../$devSubpath', '../../$devSubpath']);
    }

    Object? lastError;
    for (final candidate in candidates) {
      try {
        return ffi.DynamicLibrary.open(candidate);
      } catch (e) {
        lastError = e;
      }
    }

    throw StateError(
      'Failed to load the Dupora native engine library. Tried: '
      '${candidates.join(', ')}. Build it first with `cargo build --release` '
      'inside the rust/ directory. Last error: $lastError',
    );
  }
}
