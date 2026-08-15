import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'dupora_native_bindings.dart';
import 'status_code.dart';

/// Result of a native hashing call. [digest] is only meaningful when
/// [status] is [NativeStatus.ok].
class HashOutcome {
  const HashOutcome(this.status, this.digest);

  final NativeStatus status;
  final Uint8List digest;

  bool get isOk => status == NativeStatus.ok;
  bool get isCancelled => status == NativeStatus.cancelled;

  /// Lowercase hex digest, e.g. for cache keys / duplicate-group identity.
  String get hex =>
      digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// A cooperative cancellation flag backed by native memory, sendable across
/// isolates (see `CancelToken` in the Rust crate for the safety rationale).
///
/// One [CancelSignal] is typically shared by an entire scan; any isolate can
/// call [cancel] and every in-flight native hash call will observe it within
/// one chunk (a few MB) of I/O.
class CancelSignal {
  CancelSignal._(this._ptr);

  final ffi.Pointer<ffi.Uint8> _ptr;

  factory CancelSignal.create() {
    final ptr = calloc<ffi.Uint8>();
    ptr.value = 0;
    return CancelSignal._(ptr);
  }

  /// Reconstructs a handle from a pointer received over a [SendPort] from
  /// the isolate that created it. Native pointers are safe to send between
  /// isolates in the same process because they address shared, non-Dart-heap
  /// memory.
  CancelSignal.fromRawAddress(int address)
    : _ptr = ffi.Pointer.fromAddress(address);

  int get rawAddress => _ptr.address;

  ffi.Pointer<ffi.Uint8> get pointer => _ptr;

  bool get isCancelled => _ptr.value != 0;

  void cancel() => _ptr.value = 1;

  /// Must be called exactly once, by the isolate that created the signal,
  /// after every worker referencing it has finished.
  void dispose() => calloc.free(_ptr);
}

/// A native-memory byte counter a coordinator isolate polls from outside
/// the (blocked) worker isolate performing the hash. See `ProgressCounter`
/// in the Rust crate for the safety rationale.
class NativeProgressCounter {
  NativeProgressCounter._(this._ptr);

  final ffi.Pointer<ffi.Uint64> _ptr;

  factory NativeProgressCounter.create() {
    final ptr = calloc<ffi.Uint64>();
    ptr.value = 0;
    return NativeProgressCounter._(ptr);
  }

  NativeProgressCounter.fromRawAddress(int address)
    : _ptr = ffi.Pointer.fromAddress(address);

  int get rawAddress => _ptr.address;

  ffi.Pointer<ffi.Uint64> get pointer => _ptr;

  int get bytesProcessed => _ptr.value;

  void dispose() => calloc.free(_ptr);
}

/// Synchronous wrapper around the native engine. Intended to be called from
/// a background isolate (never the UI isolate) - blocking is the point:
/// it lets Rust stream the file without any cross-language callback
/// machinery, while progress/cancellation flow through the native-memory
/// primitives above, polled/written from other isolates.
class NativeHasher {
  NativeHasher() : _bindings = DuporaNativeBindings.instance();

  final DuporaNativeBindings _bindings;

  HashOutcome hashFileFull(
    String path, {
    NativeProgressCounter? progress,
    CancelSignal? cancel,
  }) {
    final pathBytes = utf8.encode(path);
    final pathPtr = calloc<ffi.Uint8>(pathBytes.isEmpty ? 1 : pathBytes.length);
    final outHash = calloc<ffi.Uint8>(kDigestLen);
    try {
      pathPtr.asTypedList(pathBytes.length).setAll(0, pathBytes);
      final code = _bindings.hashFileFull(
        pathPtr,
        pathBytes.length,
        progress?.pointer ?? ffi.nullptr,
        cancel?.pointer ?? ffi.nullptr,
        outHash,
      );
      final status = NativeStatus.fromCode(code);
      final digest = status == NativeStatus.ok
          ? Uint8List.fromList(outHash.asTypedList(kDigestLen))
          : Uint8List(0);
      return HashOutcome(status, digest);
    } finally {
      calloc.free(pathPtr);
      calloc.free(outHash);
    }
  }

  HashOutcome partialFingerprint(String path, int fileLen) {
    final pathBytes = utf8.encode(path);
    final pathPtr = calloc<ffi.Uint8>(pathBytes.isEmpty ? 1 : pathBytes.length);
    final outHash = calloc<ffi.Uint8>(kDigestLen);
    try {
      pathPtr.asTypedList(pathBytes.length).setAll(0, pathBytes);
      final code = _bindings.partialFingerprint(
        pathPtr,
        pathBytes.length,
        fileLen,
        outHash,
      );
      final status = NativeStatus.fromCode(code);
      final digest = status == NativeStatus.ok
          ? Uint8List.fromList(outHash.asTypedList(kDigestLen))
          : Uint8List(0);
      return HashOutcome(status, digest);
    } finally {
      calloc.free(pathPtr);
      calloc.free(outHash);
    }
  }

  int recommendedWorkerCount() {
    final cores = _bindings.logicalCpuCount();
    // Bounded: I/O-heavy work on spinning disks doesn't benefit from
    // matching logical core count, and unbounded isolate creation is
    // explicitly disallowed by the project's concurrency requirements.
    return cores.clamp(2, 16);
  }

  String engineVersion() => _bindings.engineVersion().toDartString();
}
