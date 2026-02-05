import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_client_sse/flutter_client_sse.dart';
import 'package:flutter_client_sse/constants/sse_request_type_enum.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../providers/local_settings_provider.dart';

part 'sse_service.g.dart';

// SSE 配置常量
class _SseConfig {
  static const reconnectDelayOnError = Duration(seconds: 5);
  static const reconnectDelayOnClose = Duration(seconds: 2);
  static const maxReconnectDelay = Duration(seconds: 30);
  
  // 已知事件类型（仅内部使用的常量）
  static const eventConnected = 'connected';
}

/// SSE 连接状态
enum SseConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error,
}

/// SSE 事件类型
class SseEvent {
  final String type;
  final Map<String, dynamic> data;
  final DateTime timestamp;
  
  SseEvent({required this.type, required this.data})
      : timestamp = DateTime.now();
  
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

/// SSE 事件广播控制器（全局单例）
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
    if (!_eventController.isClosed) {
      _eventController.add(event);
    }
  }
  
  void updateState(SseConnectionState state) {
    if (_currentState != state) {
      _currentState = state;
      if (!_stateController.isClosed) {
        _stateController.add(state);
      }
    }
  }
  
  void dispose() {
    _eventController.close();
    _stateController.close();
  }
}

/// SSE 服务 - 连接后端实时事件流
@Riverpod(keepAlive: true)
class SseService extends _$SseService {
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  final _eventBus = SseEventBus();
  
  @override
  Stream<SseEvent> build() {
    _connect();
    
    ref.onDispose(() {
      _cleanup();
    });
    
    return _eventBus.eventStream;
  }
  
  void _cleanup() {
    _subscription?.cancel();
    _subscription = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _eventBus.updateState(SseConnectionState.disconnected);
  }
  
  void _connect() {
    // 取消之前的连接和重连定时器
    _subscription?.cancel();
    _reconnectTimer?.cancel();
    
    final settings = ref.read(localSettingsProvider);
    final url = '${settings.baseUrl}/events/subscribe';
    
    _eventBus.updateState(SseConnectionState.connecting);
    debugPrint('[SSE] Connecting to $url');
    
    try {
      _subscription = SSEClient.subscribeToSSE(
        method: SSERequestType.GET,
        url: url,
        header: {'X-API-Token': settings.apiToken},
      ).listen(
        _onData,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('[SSE] Connection failed: $e');
      _eventBus.updateState(SseConnectionState.error);
      _scheduleReconnect(isError: true);
    }
  }
  
  void _onData(dynamic event) {
    if (event.event == null || event.data == null) return;
    
    try {
      // 连接成功，重置重连计数
      if (event.event == _SseConfig.eventConnected) {
        _reconnectAttempts = 0;
        _eventBus.updateState(SseConnectionState.connected);
        debugPrint('[SSE] Connected successfully');
        return;
      }
      
      final data = jsonDecode(event.data!) as Map<String, dynamic>;
      final sseEvent = SseEvent(type: event.event!, data: data);
      
      if (kDebugMode) {
        debugPrint('[SSE] Event: ${event.event}');
      }
      
      _eventBus.addEvent(sseEvent);
    } catch (e, stack) {
      debugPrint('[SSE] Parse error: $e');
      if (kDebugMode) {
        debugPrint('[SSE] Stack trace: $stack');
      }
    }
  }
  
  void _onError(dynamic error) {
    debugPrint('[SSE] Stream error: $error');
    _eventBus.updateState(SseConnectionState.error);
    _scheduleReconnect(isError: true);
  }
  
  void _onDone() {
    debugPrint('[SSE] Connection closed');
    _eventBus.updateState(SseConnectionState.reconnecting);
    _scheduleReconnect(isError: false);
  }
  
  void _scheduleReconnect({required bool isError}) {
    // 取消之前的重连定时器
    _reconnectTimer?.cancel();
    
    // 指数退避策略
    Duration delay;
    if (isError) {
      _reconnectAttempts++;
      final exponentialDelay = Duration(
        seconds: _SseConfig.reconnectDelayOnError.inSeconds *
            (1 << (_reconnectAttempts - 1).clamp(0, 4)),
      );
      delay = exponentialDelay > _SseConfig.maxReconnectDelay
          ? _SseConfig.maxReconnectDelay
          : exponentialDelay;
      debugPrint('[SSE] Reconnecting in ${delay.inSeconds}s (attempt $_reconnectAttempts)');
    } else {
      delay = _SseConfig.reconnectDelayOnClose;
      debugPrint('[SSE] Reconnecting in ${delay.inSeconds}s');
    }
    
    _reconnectTimer = Timer(delay, _connect);
  }
  
  /// 手动触发重连
  void reconnect() {
    debugPrint('[SSE] Manual reconnect triggered');
    _reconnectAttempts = 0;
    _connect();
  }
  
  /// 获取当前连接状态
  SseConnectionState get connectionState => _eventBus.currentState;
  
  /// 获取连接状态流
  Stream<SseConnectionState> get connectionStateStream => _eventBus.stateStream;
}

/// 获取 SSE 事件流（直接返回 Stream）
@Riverpod(keepAlive: true)
Stream<SseEvent> sseEventStream(Ref ref) {
  // 触发 SSE 服务启动（通过 watch），但我们直接从 eventBus 获取流
  ref.watch(sseServiceProvider.notifier);
  return SseEventBus().eventStream;
}

/// 获取 SSE 连接状态流
@Riverpod(keepAlive: true)
Stream<SseConnectionState> sseConnectionStateStream(Ref ref) {
  // 触发 SSE 服务启动
  ref.watch(sseServiceProvider.notifier);
  return SseEventBus().stateStream;
}

/// 获取当前 SSE 连接状态
@riverpod
SseConnectionState sseConnectionState(Ref ref) {
  // 触发 SSE 服务启动
  ref.watch(sseServiceProvider.notifier);
  return SseEventBus().currentState;
}
