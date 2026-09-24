import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../core/network/api_client.dart';
import '../../core/widgets/adaptive_form_dialog.dart';

class TelegramLoginDialog extends StatefulWidget {
  const TelegramLoginDialog({super.key, required this.client});
  final Dio client;
  @override
  State<TelegramLoginDialog> createState() => _TelegramLoginDialogState();
}

class _TelegramLoginDialogState extends State<TelegramLoginDialog> {
  final _password = TextEditingController();
  String? _id, _qr, _message;
  String _state = 'waiting';
  Timer? _timer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _cancel(String id) async {
    try {
      await widget.client.delete('/telegram-account/login/$id');
    } catch (_) {
      // Server also expires abandoned logins after five minutes.
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    final id = _id;
    if (id != null && _state != 'authorized') unawaited(_cancel(id));
    _password.dispose();
    super.dispose();
  }

  void _apply(Map<String, dynamic> data) {
    _timer?.cancel();
    _id = data['login_id'] as String;
    _state = data['state'] as String;
    _qr = data['qrcode_b64'] as String?;
    _message = data['message'] as String?;
    if (_state == 'authorized') {
      Navigator.of(context).pop(true);
    } else {
      setState(() {});
      if (_state == 'qr' ||
          _state == 'waiting' ||
          _state == 'password_required') {
        _timer = Timer(const Duration(seconds: 2), _poll);
      }
    }
  }

  Future<void> _start() async {
    setState(() {
      _state = 'waiting';
      _message = null;
      _qr = null;
    });
    try {
      final response = await widget.client.post('/telegram-account/login');
      final data = response.data as Map<String, dynamic>;
      if (!mounted) {
        await _cancel(data['login_id'] as String);
        return;
      }
      _apply(data);
    } catch (error) {
      if (mounted) {
        setState(() {
          _state = 'failed';
          _message = formatApiErrorMessage(error);
        });
      }
    }
  }

  Future<void> _poll() async {
    try {
      final response = await widget.client.get('/telegram-account/login/$_id');
      if (mounted) _apply(response.data as Map<String, dynamic>);
    } catch (error) {
      if (!mounted) return;
      if (error is DioException && error.response?.statusCode == 404) {
        setState(() {
          _state = 'expired';
          _qr = null;
          _message = '登录已结束，请重新扫码';
        });
      } else {
        _timer = Timer(const Duration(seconds: 2), _poll);
      }
    }
  }

  Future<void> _submitPassword() async {
    if (_password.text.isEmpty) return;
    _timer?.cancel();
    setState(() => _busy = true);
    try {
      final response = await widget.client.post(
        '/telegram-account/login/$_id/password',
        data: {'password': _password.text},
      );
      _password.clear();
      if (mounted) _apply(response.data as Map<String, dynamic>);
    } catch (error) {
      if (mounted) {
        setState(() => _message = formatApiErrorMessage(error));
        _timer = Timer(const Duration(seconds: 2), _poll);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AdaptiveFormDialog(
    title: '连接 Telegram',
    contentBuilder: (context, width, short) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_qr != null) ...[
          const Text('在 Telegram 中打开「设置 → 设备 → 连接桌面设备」扫码。'),
          const SizedBox(height: 16),
          Center(
            child: Image.memory(
              base64Decode(_qr!),
              width: width.clamp(100, short ? 160 : 260).toDouble(),
            ),
          ),
        ],
        if (_state == 'waiting')
          const Center(child: CircularProgressIndicator()),
        if (_state == 'password_required')
          TextField(
            controller: _password,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(labelText: '两步验证密码'),
            onSubmitted: (_) => _busy ? null : _submitPassword(),
          ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_message!),
          ),
      ],
    ),
    actions: Wrap(
      spacing: 8,
      children: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        if (_state == 'password_required')
          FilledButton(
            onPressed: _busy ? null : _submitPassword,
            child: const Text('登录'),
          ),
        if (_state == 'expired' || _state == 'failed')
          FilledButton(onPressed: _start, child: const Text('重新扫码')),
      ],
    ),
  );
}
