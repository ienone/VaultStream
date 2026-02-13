import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/sse_service.dart';

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
          _syncProgressText = '同步中... $updated 更新 / $created 新增 / $failed 失败 / $total 总数';
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('加载失败: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bot 管理')),
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
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(_syncProgressText!),
                    ),
                  FilledButton.icon(
                    onPressed: _showAddBotWizard,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('添加 Bot'),
                  ),
                  const SizedBox(height: 16),
                  if (_configs.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: Text('暂无 Bot 配置')),
                    )
                  else
                    ..._configs.map(_buildConfigCard),
                ],
              ),
            ),
    );
  }

  Widget _buildConfigCard(Map<String, dynamic> cfg) {
    final isPrimary = cfg['is_primary'] == true;
    final platform = (cfg['platform'] ?? '').toString();
    final subtitle = [
      '平台: $platform',
      '群组数: ${cfg['chat_count'] ?? 0}',
      if (cfg['bot_username'] != null) '@${cfg['bot_username']}',
    ].join('  ·  ');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text('${cfg['name'] ?? 'Bot'}${isPrimary ? '（主）' : ''}'),
        subtitle: Text(subtitle),
        trailing: PopupMenuButton<String>(
          onSelected: (value) async {
            switch (value) {
              case 'activate':
                await _activate(cfg);
              case 'sync':
                await _sync(cfg);
              case 'qr':
                await _showQr(cfg);
              case 'edit':
                await _showEditDialog(cfg);
              case 'delete':
                await _delete(cfg);
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'activate', child: Text('设为主 Bot')),
            const PopupMenuItem(value: 'sync', child: Text('同步群组')),
            if (platform == 'qq') const PopupMenuItem(value: 'qr', child: Text('获取登录二维码')),
            const PopupMenuItem(value: 'edit', child: Text('编辑')),
            const PopupMenuItem(value: 'delete', child: Text('删除')),
          ],
        ),
      ),
    );
  }

  Future<void> _activate(Map<String, dynamic> cfg) async {
    final dio = ref.read(apiClientProvider);
    await dio.post('/bot-config/${cfg['id']}/activate');
    await _loadConfigs();
  }

  Future<void> _sync(Map<String, dynamic> cfg) async {
    final dio = ref.read(apiClientProvider);
    final response = await dio.post('/bot-config/${cfg['id']}/sync-chats');
    final data = (response.data as Map).cast<String, dynamic>();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('同步完成: updated=${data['updated']} created=${data['created']} failed=${data['failed']}')),
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
        content: SelectableText(data['qr_code']?.toString() ?? data['message']?.toString() ?? '暂无二维码'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('关闭')),
        ],
      ),
    );
  }

  Future<void> _delete(Map<String, dynamic> cfg) async {
    final dio = ref.read(apiClientProvider);
    await dio.delete('/bot-config/${cfg['id']}');
    await _loadConfigs();
  }

  Future<void> _showEditDialog(Map<String, dynamic> cfg) async {
    final nameController = TextEditingController(text: (cfg['name'] ?? '').toString());
    final tokenController = TextEditingController();
    final httpController = TextEditingController(text: (cfg['napcat_http_url'] ?? '').toString());
    final wsController = TextEditingController(text: (cfg['napcat_ws_url'] ?? '').toString());
    final enabled = ValueNotifier<bool>(cfg['enabled'] == true);

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑 Bot 配置'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameController, decoration: const InputDecoration(labelText: '名称')),
              if (cfg['platform'] == 'telegram')
                TextField(controller: tokenController, decoration: const InputDecoration(labelText: '新 Token（可留空）')),
              if (cfg['platform'] == 'qq') ...[
                TextField(controller: httpController, decoration: const InputDecoration(labelText: 'Napcat HTTP URL')),
                TextField(controller: wsController, decoration: const InputDecoration(labelText: 'Napcat WS URL')),
              ],
              ValueListenableBuilder<bool>(
                valueListenable: enabled,
                builder: (context, value, _) => SwitchListTile(
                  value: value,
                  onChanged: (v) => enabled.value = v,
                  title: const Text('启用'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              final dio = ref.read(apiClientProvider);
              final payload = <String, dynamic>{
                'name': nameController.text.trim(),
                'enabled': enabled.value,
              };
              if (cfg['platform'] == 'telegram' && tokenController.text.trim().isNotEmpty) {
                payload['bot_token'] = tokenController.text.trim();
              }
              if (cfg['platform'] == 'qq') {
                payload['napcat_http_url'] = httpController.text.trim();
                payload['napcat_ws_url'] = wsController.text.trim();
              }
              await dio.patch('/bot-config/${cfg['id']}', data: payload);
              if (ctx.mounted) Navigator.of(ctx).pop();
              await _loadConfigs();
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddBotWizard() async {
    String platform = 'telegram';
    final nameController = TextEditingController();
    final tokenController = TextEditingController();
    final httpController = TextEditingController();
    final wsController = TextEditingController();

    int step = 0;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text('添加 Bot'),
          content: SizedBox(
            width: 460,
            child: Stepper(
              currentStep: step,
              controlsBuilder: (context, details) => const SizedBox.shrink(),
              steps: [
                Step(
                  title: const Text('选择平台'),
                  isActive: step >= 0,
                  content: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'telegram', label: Text('Telegram')),
                      ButtonSegment(value: 'qq', label: Text('QQ/Napcat')),
                    ],
                    selected: {platform},
                    onSelectionChanged: (s) => setStateDialog(() => platform = s.first),
                  ),
                ),
                Step(
                  title: const Text('输入凭证'),
                  isActive: step >= 1,
                  content: Column(
                    children: [
                      TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Bot 名称')),
                      if (platform == 'telegram')
                        TextField(controller: tokenController, decoration: const InputDecoration(labelText: 'Bot Token')),
                      if (platform == 'qq') ...[
                        TextField(controller: httpController, decoration: const InputDecoration(labelText: 'Napcat HTTP URL')),
                        TextField(controller: wsController, decoration: const InputDecoration(labelText: 'Napcat WS URL')),
                      ],
                    ],
                  ),
                ),
                Step(
                  title: const Text('创建并同步'),
                  isActive: step >= 2,
                  content: const Text('保存配置后自动触发一次同步。'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (step == 0) {
                  Navigator.of(ctx).pop();
                } else {
                  setStateDialog(() => step -= 1);
                }
              },
              child: Text(step == 0 ? '取消' : '上一步'),
            ),
            FilledButton(
              onPressed: () async {
                if (step < 2) {
                  setStateDialog(() => step += 1);
                  return;
                }
                final dio = ref.read(apiClientProvider);
                final payload = <String, dynamic>{
                  'platform': platform,
                  'name': nameController.text.trim().isEmpty ? '$platform-bot' : nameController.text.trim(),
                  'enabled': true,
                };
                if (platform == 'telegram') {
                  payload['bot_token'] = tokenController.text.trim();
                } else {
                  payload['napcat_http_url'] = httpController.text.trim();
                  payload['napcat_ws_url'] = wsController.text.trim();
                }
                final createResp = await dio.post('/bot-config', data: payload);
                final cfg = (createResp.data as Map).cast<String, dynamic>();
                await dio.post('/bot-config/${cfg['id']}/sync-chats');
                if (ctx.mounted) Navigator.of(ctx).pop();
                await _loadConfigs();
              },
              child: Text(step < 2 ? '下一步' : '完成'),
            ),
          ],
        ),
      ),
    );
  }
}
