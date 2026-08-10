import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../../../core/native/hash_engine.dart';
import '../../../core/native/status_code.dart';

enum HashJobKind { partial, full }

class HashJob {
  const HashJob({
    required this.id,
    required this.path,
    required this.kind,
    required this.fileSize,
    this.progressAddress = 0,
    this.cancelAddress = 0,
  });

  final int id;
  final String path;
  final HashJobKind kind;
  final int fileSize;
  final int progressAddress;
  final int cancelAddress;
}

class HashJobResult {
  const HashJobResult({required this.id, required this.status, required this.digest});
  final int id;
  final NativeStatus status;
  final Uint8List digest;

  bool get isOk => status == NativeStatus.ok;
}

/// Bounded pool of persistent worker isolates that perform Stage 2/3
/// hashing. Isolates are spawned once and reused for the whole scan -
/// "Do NOT create unlimited isolates/tasks" per the project spec.
class HashWorkerPool {
  HashWorkerPool(this.workerCount) : assert(workerCount > 0);

  final int workerCount;
  final List<_Worker> _workers = [];
  final List<HashJob> _queue = [];
  final Map<int, Completer<HashJobResult>> _pending = {};
  bool _started = false;
  bool _shuttingDown = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    for (var i = 0; i < workerCount; i++) {
      _workers.add(await _Worker.spawn(_onResult));
    }
  }

  Future<HashJobResult> submit(HashJob job) {
    if (_shuttingDown) {
      throw StateError('HashWorkerPool is shutting down');
    }
    final completer = Completer<HashJobResult>();
    _pending[job.id] = completer;

    _Worker? freeWorker;
    for (final w in _workers) {
      if (w.isFree) {
        freeWorker = w;
        break;
      }
    }
    if (freeWorker != null) {
      freeWorker.dispatch(job);
    } else {
      _queue.add(job);
    }
    return completer.future;
  }

  void _onResult(_Worker worker, HashJobResult result) {
    _pending.remove(result.id)?.complete(result);
    if (_queue.isNotEmpty) {
      worker.dispatch(_queue.removeAt(0));
    }
  }

  Future<void> shutdown() async {
    _shuttingDown = true;
    for (final worker in _workers) {
      worker.dispose();
    }
    _workers.clear();
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.complete(HashJobResult(id: -1, status: NativeStatus.cancelled, digest: Uint8List(0)));
      }
    }
    _pending.clear();
    _queue.clear();
  }
}

class _Worker {
  _Worker._(this._toWorker, this._isolate);

  final SendPort _toWorker;
  final Isolate _isolate;
  bool isFree = true;

  static Future<_Worker> spawn(void Function(_Worker, HashJobResult) onResult) async {
    final initPort = ReceivePort();
    final handshake = Completer<SendPort>();
    var gotHandshake = false;
    late final _Worker self;

    initPort.listen((event) {
      if (!gotHandshake) {
        gotHandshake = true;
        handshake.complete(event as SendPort);
        return;
      }
      self.isFree = true;
      onResult(self, event as HashJobResult);
    });

    final isolate = await Isolate.spawn(
      _workerMain,
      initPort.sendPort,
      debugName: 'dupora-hash-worker',
    );
    final toWorker = await handshake.future;
    self = _Worker._(toWorker, isolate);
    return self;
  }

  void dispatch(HashJob job) {
    isFree = false;
    _toWorker.send(job);
  }

  void dispose() {
    _isolate.kill(priority: Isolate.immediate);
  }
}

void _workerMain(SendPort mainSendPort) {
  final receivePort = ReceivePort();
  mainSendPort.send(receivePort.sendPort);

  final hasher = NativeHasher();

  receivePort.listen((message) {
    final job = message as HashJob;
    final progress =
        job.progressAddress == 0 ? null : NativeProgressCounter.fromRawAddress(job.progressAddress);
    final cancel = job.cancelAddress == 0 ? null : CancelSignal.fromRawAddress(job.cancelAddress);

    final outcome = job.kind == HashJobKind.partial
        ? hasher.partialFingerprint(job.path, job.fileSize)
        : hasher.hashFileFull(job.path, progress: progress, cancel: cancel);

    mainSendPort.send(HashJobResult(id: job.id, status: outcome.status, digest: outcome.digest));
  });
}
