import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:frontend/core/network/api_client.dart';

class InteractiveLoginDialog extends ConsumerStatefulWidget {
  final String platform;
  final String platformLabel;

  const InteractiveLoginDialog({
    super.key,
    required this.platform,
    required this.platformLabel,
  });

  @override
  ConsumerState<InteractiveLoginDialog> createState() =>
      _InteractiveLoginDialogState();
}

class _InteractiveLoginDialogState
    extends ConsumerState<InteractiveLoginDialog> {
  String _status = 'initializing';
  String? _sessionId;
  // 使用 ValueNotifier 避免 setState 重建整个 Widget 导致闪烁
  final ValueNotifier<String?> _qrcodeNotifier = ValueNotifier(null);
  String _message = '正在初始化登录环境...';
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _startSession();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _qrcodeNotifier.dispose();
    super.dispose();
  }

  Future<void> _startSession() async {
    try {
      final dio = ref.read(apiClientProvider);
      final response = await dio.post(
        '/browser-auth/session/${widget.platform}',
      );

      if (!mounted) return;

      setState(() {
        _sessionId = response.data['session_id'];
        _status = response.data['status'];
        _message = response.data['message'] ?? '会话已创建，等待加载二维码...';
      });

      _startPolling();
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'failed';
        _message = '初始化失败: ${e.response?.data['detail'] ?? e.message}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'failed';
        _message = '初始化失败: $e';
      });
    }
  }

  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!mounted || _sessionId == null) {
        timer.cancel();
        return;
      }

      try {
        final dio = ref.read(apiClientProvider);

        // 轮询状态
        final statusRes = await dio.get(
          '/browser-auth/session/$_sessionId/status',
        );
        final currentStatus = statusRes.data['status'] as String;
        final currentMsg = statusRes.data['message'] as String?;

        // 终态：停止轮询
        if (currentStatus == 'success' ||
            currentStatus == 'timeout' ||
            currentStatus == 'failed') {
          timer.cancel();

          if (mounted) {
            setState(() {
              _status = currentStatus;
              if (currentMsg != null) _message = currentMsg;
            });

            if (currentStatus == 'success') {
              Future.delayed(const Duration(seconds: 1), () {
                if (mounted) {
                  Navigator.of(context).pop(true);
                }
              });
            }
          }
          return;
        }

        // 等待扫码中：尝试获取二维码（只在尚未获取时才获取，不清空已有的）
        if (currentStatus == 'waiting_scan' && _qrcodeNotifier.value == null) {
          try {
            final qrRes = await dio.get(
              '/browser-auth/session/$_sessionId/qrcode',
            );
            if (qrRes.statusCode == 200 && qrRes.data['qrcode_b64'] != null) {
              // 只写入，不 setState，ValueNotifier 自行通知 ValueListenableBuilder
              _qrcodeNotifier.value = qrRes.data['qrcode_b64'];
            }
          } catch (_) {
            // 忽略 404（二维码还未就绪）
          }
        }

        // 只在状态或消息变化时才 setState
        if (mounted &&
            (_status != currentStatus ||
                _message != (currentMsg ?? _message))) {
          setState(() {
            _status = currentStatus;
            if (currentMsg != null) _message = currentMsg;
          });
        }
      } catch (e) {
        // 网络抖动时跳过，不立即失败
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('连接到 ${widget.platformLabel}'),
      content: SizedBox(
        width: 300,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_status == 'initializing')
                const CircularProgressIndicator()
              else if (_status == 'waiting_scan') ...[
                // 使用 ValueListenableBuilder 单独监听二维码变化，不引发整棵树重建
                ValueListenableBuilder<String?>(
                  valueListenable: _qrcodeNotifier,
                  builder: (context, qrB64, _) {
                    if (qrB64 == null) return const CircularProgressIndicator();
                    return Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Image.memory(
                        base64Decode(qrB64),
                        width: 200,
                        height: 200,
                        fit: BoxFit.contain,
                        // 明确 key，防止 Flutter 以为是同一个 Widget 而触发无意义重建
                        key: const ValueKey('qr_image'),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
                const Text(
                  '请使用手机 APP 扫描二维码\n扫码后在手机端稍等片刻以完成授权',
                  textAlign: TextAlign.center,
                ),
              ] else if (_status == 'success') ...[
                const Icon(Icons.check_circle, color: Colors.green, size: 64),
                const SizedBox(height: 16),
                const Text(
                  '登录成功！',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ] else ...[
                const Icon(Icons.error_outline, color: Colors.red, size: 64),
                const SizedBox(height: 16),
                Text(
                  _message,
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ],

              if (_status != 'failed' && _status != 'timeout') ...[
                const SizedBox(height: 24),
                Text(_message, style: const TextStyle(color: Colors.grey)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            _pollingTimer?.cancel();
            Navigator.of(context).pop(false);
          },
          child: Text(_status == 'success' ? '完成' : '取消'),
        ),
      ],
    );
  }
}
