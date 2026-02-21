import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class SafeUrlLauncher {
  static const Set<String> _allowedSchemes = {'http', 'https'};

  static Future<void> openExternal(
    BuildContext context,
    String? url,
  ) async {
    if (url == null || url.trim().isEmpty) {
      _show(context, '链接为空，无法打开');
      return;
    }

    final uri = Uri.tryParse(url.trim());
    if (uri == null || !_allowedSchemes.contains(uri.scheme.toLowerCase())) {
      // 只允许 http/https，避免 javascript:/data: 在 Web 端被执行。
      _show(context, '链接格式不安全或不受支持');
      return;
    }

    try {
      if (!await canLaunchUrl(uri)) {
        if (!context.mounted) return;
        _show(context, '当前设备无法打开该链接');
        return;
      }

      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        if (!context.mounted) return;
        _show(context, '打开链接失败');
      }
    } catch (_) {
      if (!context.mounted) return;
      _show(context, '打开链接失败');
    }
  }

  static void _show(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
