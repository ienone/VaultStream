import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../providers/local_settings_provider.dart';

part 'sse_service.g.dart';

// ─── 重连策略常量 ───────────────────────────────────────────────────────────────
class _SseConfig {
  /// 出错时首次重连延迟（之后按 2^n 指数增长）
  static const initialRetryDelay = Duration(seconds: 3);

  /// 正常关闭时（后端主动断开）的重连延迟
  static const closeRetryDelay = Duration(seconds: 2);

  /// 指数退避上限
  static const maxRetryDelay = Duration(seconds: 60);

  /// keepAlive 心跳超时：超过这么久没收到任何数据则视为连接卡死
  static const idleTimeout = Duration(seconds: 90);

  // 内部事件名
  static const eventConnected = 'connected';
}

// ─── 连接状态 ─────────────────────────────────────────────────────────────────
enum SseConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error,
}

// ─── 事件模型 ─────────────────────────────────────────────────────────────────
class SseEvent {
  final String type;
  final Map<String, dynamic> data;
  final DateTime timestamp;

  SseEvent({required this.type, required this.data}) : timestamp = DateTime.now();

  @override
  String toString() => 'SseEvent($type, $data)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SseEvent &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          data.toString() == other.data.toString();

  @override
  int get hashCode => type.hashCode ^ data.toString().hashCode;
}

// ─── 事件总线（全局单例） ──────────────────────────────────────────────────────
class SseEventBus {
  static final SseEventBus _instance = SseEventBus._internal();
  factory SseEventBus() => _instance;
  SseEventBus._internal();

  final _eventController = StreamController<SseEvent>.broadcast();
  final _stateController = StreamController<SseConnectionState>.broadcast();

  Stream<SseEvent> get eventStream => _eventController.stream;
  Stream<SseConnectionState> get stateStream => _stateController.stream;

  SseConnectionState _currentState = SseConnectionState.disconnected;
  SseConnectionState get currentState => _currentState;

  void addEvent(SseEvent event) {
    if (!_eventController.isClosed) _eventController.add(event);
  }

  void updateState(SseConnectionState state) {
    if (_currentState != state) {
      _currentState = state;
      if (!_stateController.isClosed) _stateController.add(state);
    }
  }

  void dispose() {
    _eventController.close();
    _stateController.close();
  }
}

// ─── SSE 服务 ─────────────────────────────────────────────────────────────────
/// 自研 SSE 客户端，完全掌控重连退避逻辑，不依赖第三方库的内部重试行为。
@Riverpod(keepAlive: true)
class SseService extends _$SseService {
  http.Client? _httpClient;
  Timer? _reconnectTimer;
  Timer? _idleTimer;

  int _reconnectAttempts = 0;
  String? _lastEventId;
  bool _disposed = false;

  final _eventBus = SseEventBus();

  @override
  Stream<SseEvent> build() {
    // 监听配置变化：token / baseUrl 更新时重置并立即重连
    ref.listen(localSettingsProvider, (previous, next) {
      if (previous?.apiToken != next.apiToken || previous?.baseUrl != next.baseUrl) {
        debugPrint('[SSE] 配置变化，重置重连计数并重新连接');
        _reconnectAttempts = 0;
        _connect();
      }
    });

    _connect();

    ref.onDispose(() {
      _disposed = true;
      _cleanup();
    });

    return _eventBus.eventStream;
  }

  // ── 公共 API ────────────────────────────────────────────────────────────────

  /// 手动触发重连（例如从 UI 按钮调用）
  void reconnect() {
    _reconnectAttempts = 0;
    _connect();
  }

  SseConnectionState get connectionState => _eventBus.currentState;
  Stream<SseConnectionState> get connectionStateStream => _eventBus.stateStream;

  // ── 内部逻辑 ────────────────────────────────────────────────────────────────

  void _cleanup() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _idleTimer?.cancel();
    _idleTimer = null;
    _httpClient?.close();
    _httpClient = null;
    _eventBus.updateState(SseConnectionState.disconnected);
  }

  void _connect() {
    if (_disposed) return;

    // 关闭旧连接和定时器
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _idleTimer?.cancel();
    _idleTimer = null;
    _httpClient?.close();
    _httpClient = null;

    final settings = ref.read(localSettingsProvider);

    // token 为空时不建立连接
    if (settings.apiToken.isEmpty) {
      _eventBus.updateState(SseConnectionState.disconnected);
      return;
    }

    _eventBus.updateState(SseConnectionState.connecting);
    _doConnect(settings.baseUrl, settings.apiToken);
  }

  Future<void> _doConnect(String baseUrl, String apiToken) async {
    if (_disposed) return;

    final url = Uri.parse('$baseUrl/events/subscribe');
    final headers = <String, String>{
      'Accept': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'X-API-Token': apiToken,
      if (_lastEventId != null) 'Last-Event-ID': _lastEventId!,
    };

    final client = http.Client();
    _httpClient = client;

    try {
      final request = http.Request('GET', url)..headers.addAll(headers);
      final response = await client.send(request);

      if (response.statusCode != 200) {
        debugPrint('[SSE] 连接失败，HTTP ${response.statusCode}');
        _handleError(isServerError: response.statusCode >= 500);
        return;
      }

      // 重置退避（成功建立 TCP 连接后）
      _eventBus.updateState(SseConnectionState.connecting);
      _resetIdleTimer();

      // ── 解析 SSE 文本流 ──────────────────────────────────────────────────────
      // 每个 SSE 事件由若干 "field: value\n" 行组成，以空行结尾
      String pendingEvent = '';
      String pendingData = '';
      String pendingId = '';

      // UTF-8 解码 → 按行拆分
      final textStream = response.stream
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter());

      await for (final line in textStream) {
        if (_disposed) break;

        // 重置 idle 超时计时器（每收到任意数据都刷新）
        _resetIdleTimer();

        if (line.isEmpty) {
          // 空行：提交当前累积的事件
          if (pendingEvent.isNotEmpty || pendingData.isNotEmpty) {
            _dispatchEvent(
              eventType: pendingEvent.isEmpty ? 'message' : pendingEvent,
              data: pendingData,
              id: pendingId.isNotEmpty ? pendingId : null,
            );
          }
          pendingEvent = '';
          pendingData = '';
          pendingId = '';
          continue;
        }

        // 注释行（以 ':' 开头），包括心跳 ": keepalive"
        if (line.startsWith(':')) continue;

        final colonIdx = line.indexOf(':');
        final String field;
        final String value;
        if (colonIdx < 0) {
          field = line;
          value = '';
        } else {
          field = line.substring(0, colonIdx);
          // 若冒号后紧跟空格则跳过它
          final raw = line.substring(colonIdx + 1);
          value = raw.startsWith(' ') ? raw.substring(1) : raw;
        }

        switch (field) {
          case 'event':
            pendingEvent = value;
            break;
          case 'data':
            pendingData = pendingData.isEmpty ? value : '$pendingData\n$value';
            break;
          case 'id':
            if (value.isNotEmpty) pendingId = value;
            break;
          case 'retry':
            // 服务端建议的重试间隔（毫秒），可选择忽略或使用
            break;
        }
      }

      // 流正常结束（后端主动关闭）
      if (!_disposed) {
        debugPrint('[SSE] 流正常结束，将按关闭策略重连');
        _handleClose();
      }
    } on http.ClientException catch (e) {
      if (!_disposed) {
        debugPrint('[SSE] ClientException: $e');
        _handleError();
      }
    } catch (e) {
      if (!_disposed) {
        debugPrint('[SSE] 连接异常: $e');
        _handleError();
      }
    }
  }

  void _dispatchEvent({
    required String eventType,
    required String data,
    String? id,
  }) {
    // 追踪 Last-Event-ID
    if (id != null) _lastEventId = id;

    // 连接确认事件：重置退避计数
    if (eventType == _SseConfig.eventConnected) {
      _reconnectAttempts = 0;
      _eventBus.updateState(SseConnectionState.connected);
      return;
    }

    if (data.isEmpty) return;
    try {
      final decoded = jsonDecode(data);
      if (decoded is Map<String, dynamic>) {
        _eventBus.addEvent(SseEvent(type: eventType, data: decoded));
      }
    } catch (e) {
      debugPrint('[SSE] JSON 解析失败 ($eventType): $e');
    }
  }

  /// 处理正常关闭（后端主动断开，例如重启）
  void _handleClose() {
    _eventBus.updateState(SseConnectionState.reconnecting);
    _scheduleReconnect(delay: _SseConfig.closeRetryDelay, countAsError: false);
  }

  /// 处理错误关闭（网络错误、服务器 5xx 等），使用指数退避
  void _handleError({bool isServerError = false}) {
    _eventBus.updateState(SseConnectionState.error);
    _reconnectAttempts++;

    // 2^(n-1) 指数增长，上限 maxRetryDelay
    final base = _SseConfig.initialRetryDelay.inMilliseconds;
    final factor = 1 << (_reconnectAttempts - 1).clamp(0, 6); // 最大 2^6=64x
    final ms = (base * factor).clamp(0, _SseConfig.maxRetryDelay.inMilliseconds);
    final delay = Duration(milliseconds: ms);

    debugPrint('[SSE] 将在 ${delay.inSeconds}s 后重连（第 $_reconnectAttempts 次）');
    _scheduleReconnect(delay: delay, countAsError: true);
  }

  void _scheduleReconnect({required Duration delay, required bool countAsError}) {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, _connect);
  }

  /// Idle 超时：超过设定时间没有收到任何数据则主动断开重连
  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_SseConfig.idleTimeout, () {
      if (!_disposed) {
        debugPrint('[SSE] Idle 超时，主动重连');
        _handleClose();
      }
    });
  }
}

// ─── 便捷 Provider ────────────────────────────────────────────────────────────

@Riverpod(keepAlive: true)
Stream<SseEvent> sseEventStream(Ref ref) {
  ref.watch(sseServiceProvider.notifier);
  return SseEventBus().eventStream;
}

@Riverpod(keepAlive: true)
Stream<SseConnectionState> sseConnectionStateStream(Ref ref) {
  ref.watch(sseServiceProvider.notifier);
  return SseEventBus().stateStream;
}

@riverpod
SseConnectionState sseConnectionState(Ref ref) {
  ref.watch(sseServiceProvider.notifier);
  return SseEventBus().currentState;
}
