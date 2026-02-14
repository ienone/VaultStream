import 'dart:async';

import 'package:dio/dio.dart';
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('加载失败: $e')));
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
            if (platform == 'qq')
              const PopupMenuItem(value: 'qr', child: Text('获取登录二维码')),
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
      SnackBar(
        content: Text(
          '同步完成: updated=${data['updated']} created=${data['created']} failed=${data['failed']}',
        ),
      ),
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

  Future<void> _delete(Map<String, dynamic> cfg) async {
    final dio = ref.read(apiClientProvider);
    await dio.delete('/bot-config/${cfg['id']}');
    await _loadConfigs();
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
                } on DioException catch (e) {
                  final detail = e.response?.data is Map
                      ? (e.response?.data['detail']?.toString() ??
                            e.message ??
                            '请求失败')
                      : (e.message ?? '请求失败');
                  if (!mounted) return;
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('保存失败: $detail')));
                }
              },
              child: const Text('保存'),
            ),
          ],
        ),
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
    String? nameError;
    String? tokenError;
    String? httpUrlError;
    const stepTitles = ['选择平台', '输入凭证', '创建并同步'];
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text('添加 Bot'),
          content: SizedBox(
            width: 560,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 460),
              child: SingleChildScrollView(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildWizardTimeline(currentStep: step),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${step + 1}  ${stepTitles[step]}',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 14),
                          if (step == 0)
                            SegmentedButton<String>(
                              segments: const [
                                ButtonSegment(
                                  value: 'telegram',
                                  label: Text('Telegram'),
                                ),
                                ButtonSegment(
                                  value: 'qq',
                                  label: Text('QQ/Napcat'),
                                ),
                              ],
                              selected: {platform},
                              onSelectionChanged: (s) =>
                                  setStateDialog(() => platform = s.first),
                            ),
                          if (step == 1)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildDialogTextField(
                                  controller: nameController,
                                  labelText: 'Bot 名称',
                                  errorText: nameError,
                                ),
                                if (platform == 'telegram') ...[
                                  const SizedBox(height: 12),
                                  _buildDialogTextField(
                                    controller: tokenController,
                                    labelText: 'Bot Token',
                                    errorText: tokenError,
                                  ),
                                ],
                                if (platform == 'qq') ...[
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
                              ],
                            ),
                          if (step == 2) const Text('保存配置后自动触发一次同步。'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
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
                setStateDialog(() {
                  nameError = null;
                  tokenError = null;
                  httpUrlError = null;
                });

                if (step < 2) {
                  if (step == 1) {
                    final trimmedName = nameController.text.trim();
                    final trimmedToken = tokenController.text.trim();
                    final trimmedHttp = httpController.text.trim();

                    if (trimmedName.isEmpty) {
                      setStateDialog(() => nameError = 'Bot 名称为必填项');
                      return;
                    }
                    if (platform == 'telegram' && trimmedToken.isEmpty) {
                      setStateDialog(
                        () => tokenError = 'Telegram Bot Token 为必填项',
                      );
                      return;
                    }
                    if (platform == 'qq' && trimmedHttp.isEmpty) {
                      setStateDialog(
                        () => httpUrlError = 'QQ/Napcat 至少需要填写 HTTP URL',
                      );
                      return;
                    }
                  }
                  setStateDialog(() => step += 1);
                  return;
                }
                final dio = ref.read(apiClientProvider);
                final trimmedName = nameController.text.trim();
                final trimmedToken = tokenController.text.trim();
                final trimmedHttp = httpController.text.trim();
                final payload = <String, dynamic>{
                  'platform': platform,
                  'name': trimmedName,
                  'enabled': true,
                };
                if (platform == 'telegram') {
                  payload['bot_token'] = trimmedToken;
                } else {
                  payload['napcat_http_url'] = trimmedHttp;
                  payload['napcat_ws_url'] = wsController.text.trim();
                }
                try {
                  final createResp = await dio.post(
                    '/bot-config',
                    data: payload,
                  );
                  final cfg = (createResp.data as Map).cast<String, dynamic>();
                  await dio.post('/bot-config/${cfg['id']}/sync-chats');
                  if (ctx.mounted) Navigator.of(ctx).pop();
                  await _loadConfigs();
                } on DioException catch (e) {
                  final detail = e.response?.data is Map
                      ? (e.response?.data['detail']?.toString() ??
                            e.message ??
                            '请求失败')
                      : (e.message ?? '请求失败');
                  if (!mounted) return;
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('创建失败: $detail')));
                }
              },
              child: Text(step < 2 ? '下一步' : '完成'),
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

  Widget _buildWizardTimeline({required int currentStep}) {
    const circleSize = 34.0;
    final scheme = Theme.of(context).colorScheme;

    Widget buildCircle(int index) {
      final isActive = currentStep == index;
      final isComplete = currentStep > index;
      final bgColor = (isActive || isComplete)
          ? scheme.primaryContainer
          : scheme.surfaceContainerHighest;
      final fgColor = (isActive || isComplete)
          ? scheme.onPrimaryContainer
          : scheme.onSurfaceVariant;

      return Container(
        width: circleSize,
        height: circleSize,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bgColor,
          shape: BoxShape.circle,
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Text(
          '${index + 1}',
          style: TextStyle(fontWeight: FontWeight.w700, color: fgColor),
        ),
      );
    }

    Widget buildLine(bool active) {
      return Container(
        width: 2,
        height: 38,
        margin: const EdgeInsets.symmetric(vertical: 6),
        color: active
            ? scheme.primaryContainer
            : scheme.outlineVariant.withValues(alpha: 0.7),
      );
    }

    return SizedBox(
      width: circleSize,
      child: Column(
        children: [
          buildCircle(0),
          buildLine(currentStep > 0),
          buildCircle(1),
          buildLine(currentStep > 1),
          buildCircle(2),
        ],
      ),
    );
  }
}
