import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/sse_service.dart';
import '../../core/utils/toast.dart';

class BotManagementPage extends ConsumerStatefulWidget {
  const BotManagementPage({super.key});

  @override
  ConsumerState<BotManagementPage> createState() => _BotManagementPageState();
}

class _BotManagementPageState extends ConsumerState<BotManagementPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _configs = const [];
  StreamSubscription<SseEvent>? _sseSub;
  String? _syncProgressText;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadConfigs);
    _bindRealtimeEvents();
  }

  @override
  void dispose() {
    _sseSub?.cancel();
    super.dispose();
  }

  void _bindRealtimeEvents() {
    ref.read(sseServiceProvider.notifier);
    _sseSub?.cancel();
    _sseSub = SseEventBus().eventStream.listen((event) {
      if (!mounted) return;
      if (event.type == 'bot_sync_progress') {
        final data = event.data;
        final updated = data['updated'] ?? 0;
        final created = data['created'] ?? 0;
        final failed = data['failed'] ?? 0;
        final total = data['total'] ?? 0;
        setState(() {
          _syncProgressText =
              '同步中... $updated 更新 / $created 新增 / $failed 失败 / $total 总数';
        });
      } else if (event.type == 'bot_sync_completed') {
        setState(() {
          _syncProgressText = null;
        });
        _loadConfigs();
      }
    });
  }

  Future<void> _loadConfigs() async {
    setState(() => _loading = true);
    try {
      final dio = ref.read(apiClientProvider);
      final response = await dio.get('/bot-config');
      final data = (response.data as List<dynamic>)
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
      if (mounted) {
        setState(() {
          _configs = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        Toast.show(context, '加载失败: $e', isError: true);
      }
    }
  }

  Map<String, dynamic>? _configFor(String platform) {
    for (final config in _configs) {
      if ((config['platform'] ?? '').toString() == platform) {
        return config;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('推送渠道管理')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadConfigs,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_syncProgressText != null)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(_syncProgressText!),
                    ),
                  const SizedBox(height: 16),
                  _buildPlatformCard('telegram'),
                  const SizedBox(height: 12),
                  _buildPlatformCard('qq'),
                ],
              ),
            ),
    );
  }

  Widget _buildPlatformCard(String platform) {
    final cfg = _configFor(platform);
    final title = platform == 'telegram' ? 'Telegram Bot' : 'QQ / Napcat';
    final subtitle = cfg == null
        ? '尚未配置'
        : [
            '状态: ${cfg['enabled'] == true ? '启用' : '禁用'}',
            '群组数: ${cfg['chat_count'] ?? 0}',
            if (cfg['bot_username'] != null) '@${cfg['bot_username']}',
          ].join('  ·  ');

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        title: Text(cfg == null ? title : (cfg['name'] ?? title).toString()),
        subtitle: Text(subtitle),
        trailing: cfg == null
            ? const Icon(Icons.chevron_right_rounded)
            : PopupMenuButton<String>(
                onSelected: (value) async {
                  switch (value) {
                    case 'sync':
                      await _sync(cfg);
                    case 'qr':
                      await _showQr(cfg);
                    case 'edit':
                      await _showEditDialog(cfg);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'sync', child: Text('同步群组')),
                  if (platform == 'qq')
                    const PopupMenuItem(value: 'qr', child: Text('获取登录二维码')),
                  const PopupMenuItem(value: 'edit', child: Text('编辑')),
                ],
              ),
      ),
    );
  }

  Future<void> _sync(Map<String, dynamic> cfg) async {
    final dio = ref.read(apiClientProvider);
    final response = await dio.post('/bot-config/${cfg['id']}/sync-chats');
    final data = (response.data as Map).cast<String, dynamic>();
    if (!mounted) return;
    Toast.show(
      context,
      '同步完成: 更新=${data['updated']} 新增=${data['created']} 失败=${data['failed']}',
    );
    await _loadConfigs();
  }

  Future<void> _showQr(Map<String, dynamic> cfg) async {
    final dio = ref.read(apiClientProvider);
    final response = await dio.get('/bot-config/${cfg['id']}/qr-code');
    final data = (response.data as Map).cast<String, dynamic>();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Napcat 登录二维码'),
        content: SelectableText(
          data['qr_code']?.toString() ?? data['message']?.toString() ?? '暂无二维码',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditDialog(Map<String, dynamic> cfg) async {
    final nameController = TextEditingController(
      text: (cfg['name'] ?? '').toString(),
    );
    final tokenController = TextEditingController();
    final httpController = TextEditingController(
      text: (cfg['napcat_http_url'] ?? '').toString(),
    );
    final wsController = TextEditingController(
      text: (cfg['napcat_ws_url'] ?? '').toString(),
    );
    final enabled = ValueNotifier<bool>(cfg['enabled'] == true);
    String? nameError;
    String? httpUrlError;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text('编辑 Bot 配置'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildDialogTextField(
                    controller: nameController,
                    labelText: '名称',
                    errorText: nameError,
                  ),
                  if (cfg['platform'] == 'telegram') ...[
                    const SizedBox(height: 12),
                    _buildDialogTextField(
                      controller: tokenController,
                      labelText: '新 Token（可留空）',
                    ),
                  ],
                  if (cfg['platform'] == 'qq') ...[
                    const SizedBox(height: 12),
                    _buildDialogTextField(
                      controller: httpController,
                      labelText: 'Napcat HTTP URL',
                      errorText: httpUrlError,
                    ),
                    const SizedBox(height: 12),
                    _buildDialogTextField(
                      controller: wsController,
                      labelText: 'Napcat WS URL',
                    ),
                  ],
                  const SizedBox(height: 8),
                  ValueListenableBuilder<bool>(
                    valueListenable: enabled,
                    builder: (context, value, _) => SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: value,
                      onChanged: (v) => enabled.value = v,
                      title: const Text('启用'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                setStateDialog(() {
                  nameError = null;
                  httpUrlError = null;
                });

                final trimmedName = nameController.text.trim();
                final trimmedHttp = httpController.text.trim();
                if (trimmedName.isEmpty) {
                  setStateDialog(() => nameError = '名称为必填项');
                  return;
                }
                if (cfg['platform'] == 'qq' && trimmedHttp.isEmpty) {
                  setStateDialog(
                    () => httpUrlError = 'QQ/Napcat 至少需要填写 HTTP URL',
                  );
                  return;
                }

                final dio = ref.read(apiClientProvider);
                final payload = <String, dynamic>{
                  'name': trimmedName,
                  'enabled': enabled.value,
                };
                if (cfg['platform'] == 'telegram' &&
                    tokenController.text.trim().isNotEmpty) {
                  payload['bot_token'] = tokenController.text.trim();
                }
                if (cfg['platform'] == 'qq') {
                  payload['napcat_http_url'] = trimmedHttp;
                  payload['napcat_ws_url'] = wsController.text.trim();
                }
                try {
                  await dio.patch('/bot-config/${cfg['id']}', data: payload);
                  if (ctx.mounted) Navigator.of(ctx).pop();
                  await _loadConfigs();
                  if (!mounted) return;
                  final isTelegram = cfg['platform'] == 'telegram';
                  final enabledNow = enabled.value;
                  final tokenUpdated = tokenController.text.trim().isNotEmpty;
                  if (isTelegram && (enabledNow || tokenUpdated)) {
                    Toast.show(
                      context,
                      'Telegram 配置已保存。若状态仍未运行，请检查 Token 后重启后端或手动启动 app.bot.main',
                    );
                  }
                } on DioException catch (e) {
                  final detail = e.response?.data is Map
                      ? (e.response?.data['detail']?.toString() ??
                            e.message ??
                            '请求失败')
                      : (e.message ?? '请求失败');
                  if (!mounted) return;
                  Toast.show(context, '保存失败: $detail', isError: true);
                }
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDialogTextField({
    required TextEditingController controller,
    required String labelText,
    String? errorText,
  }) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: labelText,
        errorText: errorText,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }
}
