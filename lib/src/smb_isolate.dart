import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import 'smb_platform.dart';
import 'smb_bindings_generated.dart';

extension StringToCharPointer on String {
  ffi.Pointer<ffi.Char> toCharPointer({required ffi.Allocator allocator}) {
    return toNativeUtf8(allocator: allocator).cast<ffi.Char>();
  }
}

extension CharPointerToString on ffi.Pointer<ffi.Char> {
  String toDartString() {
    return cast<Utf8>().toDartString();
  }
}

enum SmbCommand {
  connect,
  disconnect,
  disconnectAll,
  listDir,
  readFile,
  fileExists,
  directoryExists,
  createDirectory,
  deleteFile,
  uploadFile,
  statFile,
  echo,
}

class SmbRequest {
  SmbRequest({
    required this.id,
    required this.clientId,
    required this.command,
    this.connectionKey,
    this.host,
    this.port,
    this.share,
    this.username,
    this.password,
    this.domain,
    this.timeout,
    this.path,
    this.start,
    this.end,
    this.length,
    this.content,
    this.isHighPriority = false,
  });

  final int id;
  final String clientId;
  final String? connectionKey;
  final SmbCommand command;
  final String? host;
  final int? port;
  final String? share;
  final String? username;
  final String? password;
  final String? domain;
  final int? timeout;
  final String? path;
  final int? start;
  final int? end;
  final int? length;
  final List<int>? content;
  final bool isHighPriority;
}

class SmbResponse {
  SmbResponse({
    required this.id,
    required this.success,
    this.error,
    this.data,
    this.files,
    this.exists,
  });

  final int id;
  final bool success;
  final String? error;
  final Uint8List? data;
  final List<SmbFileInfo>? files;
  final bool? exists;
}

class SmbFileInfo {
  SmbFileInfo({
    required this.name,
    required this.path,
    required this.directoryPath,
    required this.size,
    required this.isDirectory,
    required this.lastModified,
    required this.created,
  });

  final String name;
  final String path;
  final String directoryPath;
  final int size;
  final bool isDirectory;
  final int lastModified;
  final int created;

  Map<String, dynamic> toMap() => {
        'name': name,
        'path': path,
        'directoryPath': directoryPath,
        'size': size,
        'isDirectory': isDirectory,
        'lastModified': lastModified,
        'created': created,
      };

  factory SmbFileInfo.fromMap(Map<String, dynamic> map) => SmbFileInfo(
        name: map['name'] as String,
        path: map['path'] as String,
        directoryPath: map['directoryPath'] as String,
        size: map['size'] as int,
        isDirectory: map['isDirectory'] as bool,
        lastModified: map['lastModified'] as int,
        created: map['created'] as int,
      );
}

class IsolateRunner {
  IsolateRunner({required this.hostKey});

  final String hostKey;
  Isolate? _isolate;
  SendPort? _sendPort;
  ReceivePort? _receivePort;
  ReceivePort? _exitPort;
  Completer<void>? _sendPortReady;
  int _requestId = 0;
  final Map<int, Completer<SmbResponse>> _pendingRequests = {};
  DateTime _lastUsedTime = DateTime.now();
  bool _isDead = false;

  bool get isRunning => _isolate != null && !_isDead;
  DateTime get lastUsedTime => _lastUsedTime;

  int get nextRequestId => ++_requestId;

  void _failAllPending(String error) {
    for (final entry in _pendingRequests.entries) {
      entry.value.complete(SmbResponse(id: entry.key, success: false, error: error));
    }
    _pendingRequests.clear();
  }

  void _resetState() {
    _isolate = null;
    _sendPort = null;
    _isDead = true;
    _receivePort?.close();
    _receivePort = null;
    _exitPort?.close();
    _exitPort = null;
    _sendPortReady = null;
  }

  Future<void> start() async {
    if (_isolate != null && !_isDead) return;

    if (_isDead) {
      _resetState();
    }

    _receivePort = ReceivePort();
    _exitPort = ReceivePort();
    _sendPortReady = Completer<void>();
    _isDead = false;

    _isolate = await Isolate.spawn(
      _isolateEntryPoint,
      _receivePort!.sendPort,
      debugName: 'SMB-Isolate-$hostKey',
      onError: _receivePort!.sendPort,
      onExit: _exitPort!.sendPort,
    );

    _exitPort!.listen((_) {
      debugPrint('SMB Isolate [$hostKey]: Isolate exited unexpectedly');
      _failAllPending('Isolate crashed or exited unexpectedly (possible C-layer Segfault)');
      _resetState();
    });

    _receivePort!.listen((message) {
      if (message is SendPort) {
        _sendPort = message;
        _sendPortReady?.complete();
        return;
      }
      if (message is SmbResponse) {
        final completer = _pendingRequests.remove(message.id);
        completer?.complete(message);
        return;
      }
      if (message is List && message.length == 2 && message[0] is SmbResponse && message[1] is TransferableTypedData) {
        final response = message[0] as SmbResponse;
        final transferable = message[1] as TransferableTypedData;
        final data = transferable.materialize().asUint8List();
        final completer = _pendingRequests.remove(response.id);
        completer?.complete(SmbResponse(
          id: response.id,
          success: response.success,
          error: response.error,
          data: data,
          files: response.files,
          exists: response.exists,
        ));
        return;
      }
      if (message is List && message.length == 2 && message[0] == null && message[1] is String) {
        _failAllPending(message[1] as String);
        return;
      }
    }, onError: (error) {
      debugPrint('SMB Isolate [$hostKey]: Unhandled isolate error: $error');
      _isDead = true;
      _failAllPending('Isolate uncaught error: $error');
      _resetState();
    });

    await _sendPortReady!.future;
  }

  Future<void> stop() async {
    // 🎯 先立即终止 Isolate（含其阻塞在 libsmb2 C 层的 OS 线程），再清理 Dart 侧状态。
    // 不在终止前调用 cleanupWinsock()：WSACleanup 在其它线程仍有阻塞式 winsock 调用时
    // 可能挂起，导致 pool.releaseAll() 卡死、shutdown 命令超时；且 _wsaInitialized 为
    // 跨 Isolate 共享静态标志，单个 worker 退出即清零会让仍在用 winsock 的其它 worker
    // 失去初始化状态。进程级 winsock 清理交由 OS 在进程退出时处理。
    _isolate?.kill(priority: Isolate.immediate);
    _resetState();
    _failAllPending('Isolate stopped');
  }

  Future<void> disconnectAll({Duration timeout = const Duration(seconds: 5)}) async {
    if (_isDead || _sendPort == null) return;

    try {
      await sendRequest(SmbRequest(
        id: nextRequestId,
        clientId: hostKey,
        command: SmbCommand.disconnectAll,
      )).timeout(timeout);
    } catch (_) {}
  }

  Future<SmbResponse> sendRequest(SmbRequest request, {Duration? timeout}) async {
    if (_isDead || _sendPort == null) {
      await start();
    }

    if (_isDead || _sendPort == null) {
      return SmbResponse(id: request.id, success: false, error: 'Isolate is dead and cannot be restarted');
    }

    _lastUsedTime = DateTime.now();

    final completer = Completer<SmbResponse>();
    _pendingRequests[request.id] = completer;
    _sendPort!.send(request);

    final actualTimeout = timeout ?? const Duration(seconds: 15);
    return completer.future.timeout(
      actualTimeout,
      onTimeout: () {
        _pendingRequests.remove(request.id);
        return SmbResponse(id: request.id, success: false, error: 'Timeout');
      },
    );
  }

  Future<SmbResponse> sendHighPriorityRequest(SmbRequest request, {Duration? timeout}) async {
    final highPriorityRequest = SmbRequest(
      id: request.id,
      clientId: request.clientId,
      command: request.command,
      connectionKey: request.connectionKey,
      host: request.host,
      port: request.port,
      share: request.share,
      username: request.username,
      password: request.password,
      domain: request.domain,
      timeout: request.timeout,
      path: request.path,
      start: request.start,
      end: request.end,
      length: request.length,
      content: request.content,
      isHighPriority: true,
    );
    return sendRequest(highPriorityRequest, timeout: timeout);
  }
}

class SmbIsolatePool {
  static final SmbIsolatePool _instance = SmbIsolatePool._internal();
  factory SmbIsolatePool() => _instance;
  SmbIsolatePool._internal();

  final Map<String, IsolateRunner> _runners = {};
  final Map<String, String> _dnsCache = {};
  final Map<String, Completer<IsolateRunner>> _pendingRunners = {};
  Timer? _cleanupTimer;
  static const Duration _idleTimeout = Duration(minutes: 5);
  static const Duration _cleanupInterval = Duration(minutes: 1);

  // 🎯 runner 被释放前的回调，用于通知调用方清理引用该 runner 的 _ConnectionContext
  void Function(IsolateRunner runner)? onBeforeReleaseRunner;

  String _makeKey(String host, int port, [String? resolvedHost]) {
    if (resolvedHost != null && resolvedHost.isNotEmpty && resolvedHost != host) {
      return '$host:$port:$resolvedHost';
    }
    return '$host:$port';
  }

  Future<void> _handleDnsUpdate(String host, String resolvedHost, int port) async {
    if (resolvedHost.isEmpty) return;
    if (resolvedHost == host) return;

    final cachedIp = _dnsCache[host];

    if (cachedIp != null && cachedIp != resolvedHost) {
      debugPrint('SMB IsolatePool: IP address updated for $host: $cachedIp -> $resolvedHost');
      // 🎯 使用旧 IP 构造 key 来精确释放旧 Runner
      releaseRunner(host, port, cachedIp);
      debugPrint('SMB IsolatePool: Released isolate for old key ${_makeKey(host, port, cachedIp)} due to IP change');
    }

    _dnsCache[host] = resolvedHost;
    debugPrint('SMB IsolatePool: Cached DNS resolution for $host -> $resolvedHost');
  }

  Future<IsolateRunner>? _findExistingRunner(String key) {
    if (_pendingRunners.containsKey(key)) {
      debugPrint('SMB IsolatePool: Waiting for pending runner for $key');
      return _pendingRunners[key]!.future;
    }

    if (_runners.containsKey(key)) {
      debugPrint('SMB IsolatePool: Reusing existing isolate for $key');
      return Future.value(_runners[key]);
    }

    return null;
  }

  Future<IsolateRunner> _createRunner(String key, String host, int port, String resolvedHost) async {
    final completer = Completer<IsolateRunner>();
    _pendingRunners[key] = completer;

    try {
      final resolvedHostKey = resolvedHost.isNotEmpty ? _makeKey(resolvedHost, port) : key;
      final runner = IsolateRunner(hostKey: resolvedHostKey);
      await runner.start();
      _runners[key] = runner;
      debugPrint('SMB IsolatePool: Created new isolate for $key (host: $host, resolvedHost: $resolvedHost), total runners=${_runners.length}');
      completer.complete(runner);
      return runner;
    } catch (e) {
      completer.completeError(e);
      rethrow;
    } finally {
      _pendingRunners.remove(key);
    }
  }

  Future<IsolateRunner> getRunner(String host, int port, String resolvedHost) async {
    final key = _makeKey(host, port, resolvedHost);

    debugPrint('SMB IsolatePool: getRunner called with host=$host, port=$port, resolvedHost=$resolvedHost, key=$key');

    await _handleDnsUpdate(host, resolvedHost, port);

    debugPrint('SMB IsolatePool: Getting runner for key=$key, current runners=${_runners.keys.toList()}');

    final existingResult = _findExistingRunner(key);
    if (existingResult != null) {
      _startCleanupTimerIfNeeded();
      return existingResult;
    }

    final runner = await _createRunner(key, host, port, resolvedHost);
    _startCleanupTimerIfNeeded();
    return runner;
  }

  // 🎯 按 key 释放 runner 的核心逻辑，供 releaseRunner 和 _cleanupIdleRunners 复用
  void _releaseRunnerByKey(String key) {
    final runner = _runners.remove(key);
    if (runner != null) {
      // 🎯 释放前通知调用方清理引用该 runner 的 _ConnectionContext
      onBeforeReleaseRunner?.call(runner);
      unawaited(
        runner.disconnectAll().whenComplete(() => runner.stop()),
      );
      debugPrint('SMB IsolatePool: Released isolate for $key');
    }
  }

  void releaseRunner(String host, int port, [String? resolvedHost]) {
    var key = _makeKey(host, port, resolvedHost);

    _releaseRunnerByKey(key);
  }

  String? getCachedDns(String host) {
    return _dnsCache[host];
  }

  void cacheDnsResolution(String host, int port, String resolvedIp) {
    final oldIp = _dnsCache[host];

    // 🎯 IP 变化时，释放旧 IP 对应的 runner，确保每个 host:port 最多一个 runner
    if (oldIp != null && oldIp != resolvedIp) {
      releaseRunner(host, port, oldIp);
      debugPrint('SMB IsolatePool: Released isolate for old key ${_makeKey(host, port, oldIp)} due to DNS cache update (IP changed: $oldIp -> $resolvedIp)');
    }

    _dnsCache[host] = resolvedIp;
    debugPrint('SMB IsolatePool: Cached DNS resolution for $host -> $resolvedIp');
  }

  void resetDnsCache(String host, int port, [String? newIp]) {
    final oldIp = _dnsCache[host];

    if (newIp != null && newIp.isNotEmpty) {
      _dnsCache[host] = newIp;
      debugPrint('SMB IsolatePool: Reset DNS cache for $host -> $newIp (was: $oldIp)');

      // 🎯 IP 变化时，释放旧 IP 对应的 runner，确保每个 host:port 最多一个 runner
      if (oldIp != null && oldIp != newIp) {
        releaseRunner(host, port, oldIp);
        debugPrint('SMB IsolatePool: Released isolate for old key ${_makeKey(host, port, oldIp)} due to DNS reset (IP changed: $oldIp -> $newIp)');
      }
    } else {
      _dnsCache.remove(host);
      debugPrint('SMB IsolatePool: Cleared DNS cache for $host (no new IP)');
    }
  }

  /// 🎯 释放池中全部资源（含卡死的 _pendingRunners），用于调度器整体重置
  /// 失败所有等待中的 pending completer 以解除挂起的 getRunner 调用，
  /// 断开并停止所有 runner Isolate（每个 disconnectAll 有 5s 上限，并行执行）。
  Future<void> releaseAll() async {
    debugPrint('SMB IsolatePool: releaseAll called, runners=${_runners.keys.toList()}, pending=${_pendingRunners.keys.toList()}');

    // 🎯 先失败 pending completer，解除挂起在 getRunner 上的调用方
    final pendingSnapshot = Map.of(_pendingRunners);
    _pendingRunners.clear();
    for (final completer in pendingSnapshot.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('SMB IsolatePool released'));
      }
    }

    // 🎯 释放前通知调用方清理引用（如调度器的 _ConnectionContext）
    final runnersSnapshot = List.of(_runners.values);
    _runners.clear();
    _dnsCache.clear();
    for (final runner in runnersSnapshot) {
      onBeforeReleaseRunner?.call(runner);
    }

    // 🎯 有界清理：disconnectAll 内部 5s 超时，并行执行避免串行累积
    await Future.wait(runnersSnapshot.map((runner) async {
      try {
        await runner.disconnectAll();
      } catch (_) {}
      await runner.stop();
    }));

    debugPrint('SMB IsolatePool: releaseAll complete (${runnersSnapshot.length} runners stopped)');
  }

  void _startCleanupTimerIfNeeded() {
    if (_cleanupTimer != null) return;

    _cleanupTimer = Timer.periodic(_cleanupInterval, (_) {
      _cleanupIdleRunners();
    });
  }

  void _cleanupIdleRunners() {
    final now = DateTime.now();
    final keysToRemove = <String>[];

    for (final entry in _runners.entries) {
      final idleTime = now.difference(entry.value.lastUsedTime);
      if (idleTime > _idleTimeout) {
        keysToRemove.add(entry.key);
      }
    }

    for (final key in keysToRemove) {
      _releaseRunnerByKey(key);
    }

    if (_runners.isEmpty && _cleanupTimer != null) {
      _cleanupTimer!.cancel();
      _cleanupTimer = null;
    }
  }
  int get activeIsolateCount => _runners.length;

  Set<String> get activeHosts => _runners.keys.toSet();
}

class _SharedContext {
  _SharedContext(this.context);
  ffi.Pointer<smb2_context> context;
}

void _isolateEntryPoint(SendPort mainSendPort) {
  final receivePort = ReceivePort();
  mainSendPort.send(receivePort.sendPort);

  debugPrint('SMB Isolate: Starting initialization...');
  debugPrint('SMB Isolate: Platform: ${Platform.operatingSystem}');

  if (!LibSmb2.initWinsock()) {
    debugPrint('SMB Isolate: Winsock initialization FAILED');
    mainSendPort.send(SmbResponse(
      id: -1,
      success: false,
      error: 'Failed to initialize Winsock on Windows',
    ));
    return;
  }
  debugPrint('SMB Isolate: Winsock initialized successfully');

  final connections = <String, _SharedContext>{};
  final highPriorityQueue = <SmbRequest>[];
  final normalQueue = <SmbRequest>[];
  var isProcessing = false;

  void sendResponse(SmbRequest request, SmbResponse result) {
    try {
      if (request.command == SmbCommand.readFile &&
          result.success &&
          result.data != null &&
          result.data!.isNotEmpty) {
        final transferable = TransferableTypedData.fromList([result.data!]);
        mainSendPort.send([
          SmbResponse(id: result.id, success: true, files: result.files, exists: result.exists),
          transferable,
        ]);
      } else {
        mainSendPort.send(result);
      }
    } catch (e) {
      debugPrint('SMB Isolate: Failed to send response: $e');
      mainSendPort.send(SmbResponse(id: request.id, success: false, error: 'Failed to send response: $e'));
    }
  }

  void processNext() {
    if (isProcessing) return;
    if (highPriorityQueue.isEmpty && normalQueue.isEmpty) return;

    isProcessing = true;

    final request = highPriorityQueue.isNotEmpty
        ? highPriorityQueue.removeAt(0)
        : normalQueue.removeAt(0);

    SmbResponse result;
    try {
      result = _dispatchCommand(request, connections);
    } catch (e, stack) {
      debugPrint('SMB Isolate: Exception in ${request.command}: $e');
      debugPrint('Stack: $stack');
      result = SmbResponse(id: request.id, success: false, error: e.toString());
    }

    sendResponse(request, result);

    isProcessing = false;

    Future.delayed(Duration.zero, processNext);
  }

  receivePort.listen((message) {
    if (message is! SmbRequest) return;

    if (message.isHighPriority) {
      highPriorityQueue.add(message);
    } else {
      normalQueue.add(message);
    }

    processNext();
  });
}

SmbResponse _dispatchCommand(SmbRequest message, Map<String, _SharedContext> connections) {
  switch (message.command) {
    case SmbCommand.connect:
      return _handleConnect(message, connections);
    case SmbCommand.disconnect:
      return _handleDisconnect(message, connections);
    case SmbCommand.disconnectAll:
      return _handleDisconnectAll(message, connections);
    case SmbCommand.listDir:
      return _handleListDir(message, connections);
    case SmbCommand.readFile:
      return _handleReadFile(message, connections);
    case SmbCommand.fileExists:
      return _handleCheckExists(message, connections, checkIsDirectory: false);
    case SmbCommand.directoryExists:
      return _handleCheckExists(message, connections, checkIsDirectory: true);
    case SmbCommand.createDirectory:
      return _handleCreateDirectory(message, connections);
    case SmbCommand.deleteFile:
      return _handleDeleteFile(message, connections);
    case SmbCommand.uploadFile:
      return _handleUploadFile(message, connections);
    case SmbCommand.statFile:
      return _handleStatFile(message, connections);
    case SmbCommand.echo:
      return _handleEcho(message, connections);
  }
}

_SharedContext? _getConnection(SmbRequest message, Map<String, _SharedContext> connections) {
  final key = message.connectionKey ?? message.clientId;
  return connections[key];
}

SmbResponse _notConnectedResponse(SmbRequest message) {
  return SmbResponse(id: message.id, success: false, error: 'Not connected');
}

bool _isRetryableConnectError(String error) {
  final lowerError = error.toLowerCase();
  return lowerError.contains('poll failed') ||
      lowerError.contains('invalid file descriptor') ||
      lowerError.contains('read from socket failed') ||
      lowerError.contains('errno:9') ||
      lowerError.contains('bad file descriptor') ||
      lowerError.contains('pollhup') ||
      lowerError.contains('socket error');
}

bool _isConnectionError(String error) {
  final lower = error.toLowerCase();
  return lower.contains('not connected') ||
      lower.contains('pollhup') ||
      lower.contains('socket error') ||
      lower.contains('connection reset') ||
      lower.contains('broken pipe');
}

const _errorPatterns = [
  _ErrorPattern('status_logon_failure', '认证失败：用户名或密码错误'),
  _ErrorPattern('logon failure', '认证失败：用户名或密码错误'),
  _ErrorPattern('status_bad_network_name', '共享名称不存在'),
  _ErrorPattern('bad network name', '共享名称不存在'),
  _ErrorPattern('status_network_unreachable', '网络不可达：无法解析主机名，请尝试使用IP地址'),
  _ErrorPattern('can not resolve', '网络不可达：无法解析主机名，请尝试使用IP地址'),
  _ErrorPattern('no route to host', '网络不可达：无法解析主机名，请尝试使用IP地址'),
  _ErrorPattern('name or service not known', '网络不可达：无法解析主机名，请尝试使用IP地址'),
  _ErrorPattern('temporary failure in name resolution', '网络不可达：无法解析主机名，请尝试使用IP地址'),
  _ErrorPattern('status_connection_refused', '连接被拒绝：请检查端口号'),
  _ErrorPattern('connection refused', '连接被拒绝：请检查端口号'),
  _ErrorPattern('status_access_denied', '访问被拒绝：请检查用户权限'),
  _ErrorPattern('access denied', '访问被拒绝：请检查用户权限'),
  _ErrorPattern('status_invalid_parameter', '参数错误：请检查输入信息'),
  _ErrorPattern('status_unsupported', '不支持的操作：服务器可能不支持此SMB版本'),
];

class _ErrorPattern {
  const _ErrorPattern(this.pattern, this.message);
  final String pattern;
  final String message;
}

String _translateSmbError(String error) {
  final lower = error.toLowerCase();

  for (final entry in _errorPatterns) {
    if (lower.contains(entry.pattern)) return entry.message;
  }

  if (lower.contains('timeout') || lower.contains('timed out')) {
    return '连接超时：请检查网络连接';
  }

  if (lower.contains('poll failed')) {
    final errnoMatch = RegExp(r'\((\d+)\)').firstMatch(error);
    if (errnoMatch != null) {
      final errno = int.tryParse(errnoMatch.group(1) ?? '');
      if (errno != null) {
        return 'Poll系统调用失败(errno=$errno): ${_getErrnoDescription(errno)}';
      }
    }
    return 'Poll系统调用失败：可能是Android Isolate环境限制，请尝试使用IP地址';
  }

  if (lower.contains('invalid file descriptor')) {
    return '无效的文件描述符：连接建立失败，请检查网络和服务器状态';
  }

  if (lower.contains('read from socket failed')) {
    final errnoMatch = RegExp(r'errno:(\d+)').firstMatch(error);
    if (errnoMatch != null) {
      final errno = int.tryParse(errnoMatch.group(1) ?? '');
      if (errno != null) {
        return 'Socket读取失败(errno=$errno): ${_getErrnoDescription(errno)}，请检查网络连接或尝试使用IP地址';
      }
    }
    return 'Socket读取失败：连接异常断开，请检查网络连接或尝试使用IP地址';
  }

  if (lower.contains('write to socket failed')) {
    return 'Socket写入失败：连接异常断开，请检查网络连接';
  }

  return error;
}

String _getErrnoDescription(int errno) {
  switch (errno) {
    case 4: return 'Interrupted system call (EINTR) - 系统调用被中断';
    case 9: return 'Bad file descriptor (EBADF) - 文件描述符无效';
    case 11: return 'Resource temporarily unavailable (EAGAIN) - 资源暂时不可用';
    case 13: return 'Permission denied (EACCES) - 权限被拒绝';
    case 22: return 'Invalid argument (EINVAL) - 无效参数';
    case 88: return 'Socket operation on non-socket (ENOTSOCK) - 非socket操作';
    case 104: return 'Connection reset by peer (ECONNRESET) - 连接被重置';
    case 110: return 'Connection timed out (ETIMEDOUT) - 连接超时';
    case 111: return 'Connection refused (ECONNREFUSED) - 连接被拒绝';
    case 113: return 'No route to host (EHOSTUNREACH) - 没有到主机的路由';
    case 115: return 'Operation now in progress (EINPROGRESS) - 操作正在进行中';
    default: return '未知错误码 ($errno)';
  }
}

SmbResponse _handleConnect(
  SmbRequest message,
  Map<String, _SharedContext> connections,
) {
  final clientId = message.clientId;
  final connectionKey = message.connectionKey ?? clientId;
  debugPrint('SMB Connect: === Starting connection ===');
  debugPrint('SMB Connect: Platform: ${Platform.operatingSystem}');
  debugPrint('SMB Connect: Client ID: $clientId');
  debugPrint('SMB Connect: Connection Key: $connectionKey');
  debugPrint('SMB Connect: Host: ${message.host}:${message.port}');
  debugPrint('SMB Connect: Share: ${message.share}');
  debugPrint('SMB Connect: User: ${message.username}');
  debugPrint('SMB Connect: Domain: ${message.domain}');
  debugPrint('SMB Connect: Timeout: ${message.timeout}s');

  final existing = connections[connectionKey];
  if (existing != null && existing.context.address != 0) {
    debugPrint('SMB Connect: Reusing existing context for key $connectionKey');
    return SmbResponse(id: message.id, success: true);
  }

  const maxRetries = 2;
  ffi.Pointer<smb2_context> ctx = ffi.nullptr;

  for (var attempt = 1; attempt <= maxRetries; attempt++) {
    debugPrint('SMB Connect: --- Attempt $attempt/$maxRetries ---');

    if (ctx.address != 0) {
      debugPrint('SMB Connect: Destroying previous context before retry');
      try { LibSmb2.bindings.smb2_disconnect_share(ctx); } catch (_) {}
      LibSmb2.bindings.smb2_destroy_context(ctx);
    }

    ctx = LibSmb2.bindings.smb2_init_context();
    if (ctx.address == 0) {
      debugPrint('SMB Connect: Failed to init context on attempt $attempt');
      return SmbResponse(id: message.id, success: false, error: 'Failed to init context after $attempt attempts');
    }
    debugPrint('SMB Connect: Context created at ${ctx.address.toRadixString(16)}');

    final timeout = message.timeout ?? 30;
    LibSmb2.bindings.smb2_set_timeout(ctx, timeout);

    using((arena) {
      final domainStr = message.domain ?? '';
      LibSmb2.bindings.smb2_set_domain(ctx, domainStr.toCharPointer(allocator: arena));

      final usernameStr = message.username ?? '';
      if (usernameStr.isNotEmpty) {
        LibSmb2.bindings.smb2_set_user(ctx, usernameStr.toCharPointer(allocator: arena));
      }

      final passwordStr = message.password ?? '';
      LibSmb2.bindings.smb2_set_password(ctx, passwordStr.toCharPointer(allocator: arena));

      final workstationName = Platform.localHostname.toUpperCase();
      LibSmb2.bindings.smb2_set_workstation(ctx, workstationName.toCharPointer(allocator: arena));
    });

    final result = using((arena) {
      final serverPtr = message.host!.toCharPointer(allocator: arena);
      final sharePtr = message.share!.toCharPointer(allocator: arena);
      final userPtr = (message.username ?? '').toCharPointer(allocator: arena);
      return LibSmb2.bindings.smb2_connect_share(ctx, serverPtr, sharePtr, userPtr);
    });

    debugPrint('SMB Connect: Attempt $attempt result: $result');

    if (result == 0) {
      debugPrint('SMB Connect: ✅ Connection SUCCESS after $attempt attempts');
      connections[connectionKey] = _SharedContext(ctx);
      return SmbResponse(id: message.id, success: true);
    }

    final error = LibSmb2.bindings.smb2_get_error(ctx).toDartString();
    debugPrint('SMB Connect: ❌ Attempt $attempt failed: $error');

    if (_isRetryableConnectError(error) && attempt < maxRetries) {
      final lowerError = error.toLowerCase();
      final delayMs = lowerError.contains('pollhup') ? 1000 * attempt : 300 * attempt;

      debugPrint('SMB Connect: ⏳ Retrying in ${delayMs}ms...');
      sleep(Duration(milliseconds: delayMs));
      continue;
    }

    final userMessage = _translateSmbError(error);
    try { LibSmb2.bindings.smb2_disconnect_share(ctx); } catch (_) {}
    LibSmb2.bindings.smb2_destroy_context(ctx);
    return SmbResponse(id: message.id, success: false, error: userMessage);
  }

  if (ctx.address != 0) {
    try { LibSmb2.bindings.smb2_disconnect_share(ctx); } catch (_) {}
    LibSmb2.bindings.smb2_destroy_context(ctx);
  }
  return SmbResponse(id: message.id, success: false, error: 'Connection failed after $maxRetries attempts');
}

SmbResponse _handleDisconnect(
  SmbRequest message,
  Map<String, _SharedContext> connections,
) {
  final connectionKey = message.connectionKey ?? message.clientId;

  final shared = connections.remove(connectionKey);
  if (shared == null) {
    return SmbResponse(id: message.id, success: true);
  }

  final ctx = shared.context;
  if (ctx.address == 0) {
    return SmbResponse(id: message.id, success: true);
  }

  try {
    LibSmb2.bindings.smb2_disconnect_share(ctx);
    LibSmb2.bindings.smb2_destroy_context(ctx);
  } catch (_) {}

  debugPrint('SMB Disconnect: Destroyed context for key $connectionKey');

  return SmbResponse(id: message.id, success: true);
}

SmbResponse _handleDisconnectAll(
  SmbRequest message,
  Map<String, _SharedContext> connections,
) {
  if (connections.isEmpty) {
    return SmbResponse(id: message.id, success: true);
  }

  debugPrint('SMB DisconnectAll: Disconnecting ${connections.length} connection(s)');

  for (final entry in connections.entries) {
    final ctx = entry.value.context;
    if (ctx.address != 0) {
      try {
        LibSmb2.bindings.smb2_disconnect_share(ctx);
        LibSmb2.bindings.smb2_destroy_context(ctx);
      } catch (_) {}
      debugPrint('SMB DisconnectAll: Destroyed context for key ${entry.key}');
    }
  }

  connections.clear();
  return SmbResponse(id: message.id, success: true);
}

SmbResponse _handleListDir(
  SmbRequest message,
  Map<String, _SharedContext> connections,
) {
  final shared = _getConnection(message, connections);
  if (shared == null) return _notConnectedResponse(message);
  final ctx = shared.context;

  final dirPtr = using((arena) {
    final pathPtr = message.path!.toCharPointer(allocator: arena);
    return LibSmb2.bindings.smb2_opendir(ctx, pathPtr);
  });

  if (dirPtr.address == 0) {
    final error = LibSmb2.bindings.smb2_get_error(ctx).toDartString();
    return SmbResponse(id: message.id, success: false, error: 'Failed to open directory: $error');
  }

  final files = <SmbFileInfo>[];

  try {
    while (true) {
      final dirent = LibSmb2.bindings.smb2_readdir(ctx, dirPtr);
      if (dirent.address == 0) break;

      final name = dirent.ref.name.toDartString();
      if (name == '.' || name == '..') continue;

      final fullPath = message.path!.endsWith('/')
          ? '${message.path!}$name'
          : '${message.path!}/$name';

      files.add(SmbFileInfo(
        name: name,
        path: fullPath,
        directoryPath: message.path!,
        size: dirent.ref.st.smb2_size,
        isDirectory: dirent.ref.st.smb2_type == 1,
        lastModified: dirent.ref.st.smb2_mtime,
        created: dirent.ref.st.smb2_ctime,
      ));
    }
  } finally {
    LibSmb2.bindings.smb2_closedir(ctx, dirPtr);
  }

  return SmbResponse(id: message.id, success: true, files: files);
}

SmbResponse _handleStatFile(
  SmbRequest message,
  Map<String, _SharedContext> connections,
) {
  final shared = _getConnection(message, connections);
  if (shared == null) return _notConnectedResponse(message);
  final ctx = shared.context;

  final stat = calloc<smb2_stat_64>();
  try {
    final result = using((arena) {
      final pathPtr = message.path!.toCharPointer(allocator: arena);
      return LibSmb2.bindings.smb2_stat(ctx, pathPtr, stat);
    });

    if (result != 0) {
      final error = LibSmb2.bindings.smb2_get_error(ctx).toDartString();
      if (_isConnectionError(error)) {
        return SmbResponse(id: message.id, success: false, error: error);
      }
      return SmbResponse(id: message.id, success: false, error: 'File not found: $error');
    }

    final files = <SmbFileInfo>[
      SmbFileInfo(
        name: message.path!.split('/').last,
        path: message.path!,
        directoryPath: message.path!.substring(0, message.path!.lastIndexOf('/')),
        size: stat.ref.smb2_size,
        isDirectory: stat.ref.smb2_type == 1,
        lastModified: stat.ref.smb2_mtime,
        created: stat.ref.smb2_ctime,
      ),
    ];

    return SmbResponse(id: message.id, success: true, files: files);
  } finally {
    calloc.free(stat);
  }
}

SmbResponse _handleReadFile(
  SmbRequest message,
  Map<String, _SharedContext> connections,
) {
  final shared = _getConnection(message, connections);
  if (shared == null) return _notConnectedResponse(message);
  final ctx = shared.context;

  ffi.Pointer<smb2fh> fh;
  try {
    fh = using((arena) {
      final pathPtr = message.path!.toCharPointer(allocator: arena);
      return LibSmb2.bindings.smb2_open(ctx, pathPtr, O_RDONLY);
    });
  } catch (e) {
    return SmbResponse(id: message.id, success: false, error: 'Failed to open file: $e');
  }

  if (fh.address == 0) {
    final error = LibSmb2.bindings.smb2_get_error(ctx).toDartString();
    return SmbResponse(id: message.id, success: false, error: 'Failed to open file: $error');
  }

  try {
    final stat = calloc<smb2_stat_64>();
    try {
      final fstatResult = LibSmb2.bindings.smb2_fstat(ctx, fh, stat);
      if (fstatResult != 0) {
        final error = LibSmb2.bindings.smb2_get_error(ctx).toDartString();
        return SmbResponse(id: message.id, success: false, error: 'fstat failed: $error');
      }
      final fileSize = stat.ref.smb2_size;

      if (fileSize == 0) {
        return SmbResponse(id: message.id, success: true, data: Uint8List(0));
      }

      final readStart = message.start ?? 0;
      final readEnd = message.end ?? (message.length != null ? readStart + message.length! : fileSize);
      final readSize = readEnd - readStart;

      if (readSize <= 0 || readStart >= fileSize) {
        return SmbResponse(id: message.id, success: true, data: Uint8List(0));
      }

      final actualReadSize = readStart + readSize > fileSize ? fileSize - readStart : readSize;

      final buffer = calloc<ffi.Uint8>(actualReadSize);
      try {
        var offset = readStart;
        var remaining = actualReadSize;
        var bufferOffset = 0;
        final maxRead = LibSmb2.bindings.smb2_get_max_read_size(ctx);
        var consecutiveZeroReads = 0;

        while (remaining > 0) {
          final toRead = remaining > maxRead ? maxRead : remaining;
          final bytesRead = LibSmb2.bindings.smb2_pread(ctx, fh, buffer + bufferOffset, toRead, offset);
          if (bytesRead < 0) {
            final error = LibSmb2.bindings.smb2_get_error(ctx).toDartString();
            return SmbResponse(id: message.id, success: false, error: 'Read failed at offset $offset: $error');
          }
          if (bytesRead == 0) {
            consecutiveZeroReads++;
            if (consecutiveZeroReads > 3) {
              break;
            }
            continue;
          }
          consecutiveZeroReads = 0;
          offset += bytesRead;
          bufferOffset += bytesRead;
          remaining -= bytesRead;
        }

        final result = Uint8List.fromList(buffer.asTypedList(bufferOffset));
        return SmbResponse(id: message.id, success: true, data: result);
      } finally {
        calloc.free(buffer);
      }
    } finally {
      calloc.free(stat);
    }
  } catch (e) {
    return SmbResponse(id: message.id, success: false, error: 'Exception: $e');
  } finally {
    try {
      LibSmb2.bindings.smb2_close(ctx, fh);
    } catch (_) {}
  }
}

SmbResponse _handleCheckExists(
  SmbRequest message,
  Map<String, _SharedContext> connections, {
  required bool checkIsDirectory,
}) {
  final shared = _getConnection(message, connections);
  if (shared == null) return _notConnectedResponse(message);
  final ctx = shared.context;

  final stat = calloc<smb2_stat_64>();
  try {
    final result = using((arena) {
      final pathPtr = message.path!.toCharPointer(allocator: arena);
      return LibSmb2.bindings.smb2_stat(ctx, pathPtr, stat);
    });

    if (result != 0) {
      final error = LibSmb2.bindings.smb2_get_error(ctx).toDartString();
      if (_isConnectionError(error)) {
        return SmbResponse(id: message.id, success: false, error: error);
      }
      return SmbResponse(id: message.id, success: true, exists: false);
    }

    final isDir = stat.ref.smb2_type == 1;
    return SmbResponse(id: message.id, success: true, exists: checkIsDirectory ? isDir : !isDir);
  } finally {
    calloc.free(stat);
  }
}

SmbResponse _handleCreateDirectory(
  SmbRequest message,
  Map<String, _SharedContext> connections,
) {
  final shared = _getConnection(message, connections);
  if (shared == null) return _notConnectedResponse(message);
  final ctx = shared.context;

  final result = using((arena) {
    final pathPtr = message.path!.toCharPointer(allocator: arena);
    return LibSmb2.bindings.smb2_mkdir(ctx, pathPtr);
  });

  return SmbResponse(id: message.id, success: result == 0, error: result != 0 ? 'Failed to create directory: ${LibSmb2.bindings.smb2_get_error(ctx).toDartString()}' : null);
}

SmbResponse _handleDeleteFile(
  SmbRequest message,
  Map<String, _SharedContext> connections,
) {
  final shared = _getConnection(message, connections);
  if (shared == null) return _notConnectedResponse(message);
  final ctx = shared.context;

  final result = using((arena) {
    final pathPtr = message.path!.toCharPointer(allocator: arena);
    return LibSmb2.bindings.smb2_unlink(ctx, pathPtr);
  });

  return SmbResponse(id: message.id, success: result == 0, error: result != 0 ? 'Failed to delete file: ${LibSmb2.bindings.smb2_get_error(ctx).toDartString()}' : null);
}

SmbResponse _handleUploadFile(
  SmbRequest message,
  Map<String, _SharedContext> connections,
) {
  final shared = _getConnection(message, connections);
  if (shared == null) return _notConnectedResponse(message);
  final ctx = shared.context;

  final content = message.content;
  if (content == null || content.isEmpty) {
    return SmbResponse(id: message.id, success: false, error: 'No content to upload');
  }

  final fh = using((arena) {
    final pathPtr = message.path!.toCharPointer(allocator: arena);
    // 必须用与 C 编译头文件一致的 O_TRUNC，否则会退化成 FILE_OPEN_IF（不截断）。
    return LibSmb2.bindings.smb2_open(ctx, pathPtr, smbWriteOpenFlags);
  });

  if (fh.address == 0) {
    final error = LibSmb2.bindings.smb2_get_error(ctx).toDartString();
    return SmbResponse(id: message.id, success: false, error: 'Failed to open file for writing: $error');
  }

  try {
    final maxWrite = LibSmb2.bindings.smb2_get_max_write_size(ctx);
    var offset = 0;

    while (offset < content.length) {
      final toWrite = content.length - offset > maxWrite ? maxWrite : content.length - offset;
      final buffer = calloc<ffi.Uint8>(toWrite);

      try {
        for (var i = 0; i < toWrite; i++) {
          buffer[i] = content[offset + i];
        }

        final bytesWritten = LibSmb2.bindings.smb2_pwrite(ctx, fh, buffer.cast(), toWrite, offset);
        if (bytesWritten < 0) {
          final error = LibSmb2.bindings.smb2_get_error(ctx).toDartString();
          return SmbResponse(id: message.id, success: false, error: 'Write failed: $error');
        }
        offset += bytesWritten;
      } finally {
        calloc.free(buffer);
      }
    }

    return SmbResponse(id: message.id, success: true);
  } finally {
    LibSmb2.bindings.smb2_close(ctx, fh);
  }
}

SmbResponse _handleEcho(
  SmbRequest message,
  Map<String, _SharedContext> connections,
) {
  final shared = _getConnection(message, connections);
  if (shared == null) return _notConnectedResponse(message);
  final ctx = shared.context;

  try {
    final result = LibSmb2.bindings.smb2_echo(ctx);

    if (result == 0) {
      return SmbResponse(id: message.id, success: true);
    } else {
      final error = LibSmb2.bindings.smb2_get_error(ctx).toDartString();
      return SmbResponse(
        id: message.id,
        success: false,
        error: 'Echo failed: $error (code: $result)',
      );
    }
  } catch (e) {
    return SmbResponse(
      id: message.id,
      success: false,
      error: 'Echo exception: $e',
    );
  }
}
