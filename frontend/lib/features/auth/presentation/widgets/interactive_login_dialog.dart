import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/utils/safe_url_launcher.dart';
import 'package:frontend/core/widgets/adaptive_form_dialog.dart';
import 'package:frontend/theme/design_tokens.dart';

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
  String? _captchaUrl;
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
        _captchaUrl = response.data['captcha_url'];
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
        _message = formatApiErrorMessage(e, fallbackMessage: '初始化失败');
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
        final currentCaptchaUrl = statusRes.data['captcha_url'] as String?;

        // 终态：停止轮询
        if (currentStatus == 'success' ||
            currentStatus == 'timeout' ||
            currentStatus == 'failed') {
          timer.cancel();

          if (mounted) {
            setState(() {
              _status = currentStatus;
              if (currentMsg != null) _message = currentMsg;
              _captchaUrl = currentCaptchaUrl;
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
        if ((currentStatus == 'waiting_scan' ||
                currentStatus == 'needs_captcha') &&
            _qrcodeNotifier.value == null) {
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

        // 只在状态、消息或验证码链接变化时才 setState
        if (mounted &&
            (_status != currentStatus ||
                _message != (currentMsg ?? _message) ||
                _captchaUrl != currentCaptchaUrl)) {
          setState(() {
            _status = currentStatus;
            if (currentMsg != null) _message = currentMsg;
            _captchaUrl = currentCaptchaUrl;
          });
        }
      } catch (e) {
        // 网络抖动时跳过，不立即失败
      }
    });
  }

  Future<void> _launchCaptchaUrl() async {
    if (_captchaUrl != null) {
      await SafeUrlLauncher.openExternal(context, _captchaUrl);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final waiting = _status == 'waiting_scan' || _status == 'needs_captcha';
    final failed = _status == 'failed' || _status == 'timeout';
    return AdaptiveFormDialog(
      title: '连接到 ${widget.platformLabel}',
      maxWidth: waiting ? AppPane.formMaxWidth : 440,
      contentBuilder: (context, width, short) {
        final qrSize = (width - 16).clamp(0.0, short ? 144.0 : 200.0);
        final message = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_status == 'initializing') ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 16),
            ],
            Semantics(
              liveRegion: true,
              child: Text(
                _message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: failed
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (_status == 'needs_captcha') ...[
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: _captchaUrl == null ? null : _launchCaptchaUrl,
                icon: const Icon(Icons.open_in_new),
                label: const Text('前往验证'),
              ),
            ],
          ],
        );
        if (!waiting) return message;
        final qr = ValueListenableBuilder<String?>(
          valueListenable: _qrcodeNotifier,
          builder: (context, qrB64, _) => Container(
            width: qrSize + 16,
            height: qrSize + 16,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: AppShape.cardMediaBorder,
            ),
            child: qrB64 == null
                ? const Center(child: CircularProgressIndicator())
                : Image.memory(
                    base64Decode(qrB64),
                    key: const ValueKey('qr_image'),
                    semanticLabel: '${widget.platformLabel} 登录二维码',
                    fit: BoxFit.contain,
                  ),
          ),
        );
        final horizontal =
            width >= qrSize + 40 + MediaQuery.textScalerOf(context).scale(140);
        return horizontal
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  qr,
                  const SizedBox(width: 24),
                  Expanded(child: message),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: qr),
                  const SizedBox(height: 20),
                  message,
                ],
              );
      },
      actions: Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: () {
            _pollingTimer?.cancel();
            Navigator.of(context).pop(false);
          },
          child: Text(_status == 'success' ? '完成' : '取消'),
        ),
      ),
    );
  }
}
