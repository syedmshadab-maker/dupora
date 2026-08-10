/// Mirrors `rust/src/error.rs::StatusCode`. Keep in sync.
enum NativeStatus {
  ok(0),
  cancelled(1),
  notFound(2),
  permissionDenied(3),
  ioError(4),
  invalidArgument(5),
  unexpected(6);

  const NativeStatus(this.code);

  final int code;

  static NativeStatus fromCode(int code) {
    return NativeStatus.values.firstWhere(
      (s) => s.code == code,
      orElse: () => NativeStatus.unexpected,
    );
  }
}
