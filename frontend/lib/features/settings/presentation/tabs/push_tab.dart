import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/setting_components.dart';
import '../../providers/settings_provider.dart';
import '../../models/system_setting.dart';
import '../../../../core/network/api_client.dart';
import '../../../review/providers/bot_chats_provider.dart';
import '../../../review/models/bot_chat.dart';
import '../../../review/widgets/bot_chat_dialog.dart';

class PushTab extends ConsumerStatefulWidget {
  const PushTab({super.key});

  @override
  ConsumerState<PushTab> createState() => _PushTabState();
}

class _PushTabState extends ConsumerState<PushTab> {
  int _currentStep = 0;
  bool _isSaving = false;
  bool _isControllingTelegram = false;
  bool _isSyncingChats = false;
  bool _pushConfigExpanded = false;
  String _botPlatform = 'telegram';

  final _tgTokenController = TextEditingController();
  final _tgAdminIdController = TextEditingController();
  final _qqUrlController = TextEditingController(text: 'http://127.0.0.1:3000');
  final _adminsCtrl = TextEditingController();
  final _whiteCtrl = TextEditingController();
  final _blackCtrl = TextEditingController();

  bool _initialized = false;

  @override
  void dispose() {
    _tgTokenController.dispose();
    _tgAdminIdController.dispose();
    _qqUrlController.dispose();
    _adminsCtrl.dispose();
    _whiteCtrl.dispose();
    _blackCtrl.dispose();
    super.dispose();
  }

  /// 从设置中预填权限字段（只初始化一次）
  void _initFromSettings(List<SystemSetting> settings) {
    if (_initialized) return;
    _initialized = true;
    _adminsCtrl.text = _getSetting(settings, 'telegram_admin_ids');
    _whiteCtrl.text = _getSetting(settings, 'telegram_whitelist_ids');
    _blackCtrl.text = _getSetting(settings, 'telegram_blacklist_ids');
  }

  String _getSetting(List<SystemSetting> settings, String key) {
    return settings
                .firstWhere(
                  (s) => s.key == key,
                  orElse: () => const SystemSetting(key: '', value: ''),
                )
                .value
            as String? ??
        '';
  }

  Future<void> _saveConfig() async {
    setState(() => _isSaving = true);
    try {
      final dio = ref.read(apiClientProvider);

      // 查询是否已有同平台配置，有则 PATCH，无则 POST
      final existingResp = await dio.get('/bot-config');
      final existingConfigs = (existingResp.data as List?) ?? [];
      final existing = existingConfigs.cast<Map<String, dynamic>>().where(
        (c) => c['platform'] == _botPlatform,
      );
      final existingConfig = existing.isNotEmpty ? existing.first : null;

      if (_botPlatform == 'telegram' &&
          _tgTokenController.text.trim().isNotEmpty) {
        if (existingConfig != null) {
          await dio.patch(
            '/bot-config/${existingConfig['id']}',
            data: {
              'bot_token': _tgTokenController.text.trim(),
              'enabled': true,
              'is_primary': true,
            },
          );
        } else {
          await dio.post(
            '/bot-config',
            data: {
              'platform': 'telegram',
              'name': 'Main Telegram Bot',
              'bot_token': _tgTokenController.text.trim(),
              'enabled': true,
              'is_primary': true,
            },
          );
        }
      } else if (_botPlatform == 'qq' &&
          _qqUrlController.text.trim().isNotEmpty) {
        if (existingConfig != null) {
          await dio.patch(
            '/bot-config/${existingConfig['id']}',
            data: {
              'napcat_http_url': _qqUrlController.text.trim(),
              'enabled': true,
              'is_primary': true,
            },
          );
        } else {
          await dio.post(
            '/bot-config',
            data: {
              'platform': 'qq',
              'name': 'Main QQ Bot',
              'napcat_http_url': _qqUrlController.text.trim(),
              'enabled': true,
              'is_primary': true,
            },
          );
        }
      }
      // 保存权限配置
      final notifier = ref.read(systemSettingsProvider.notifier);
      await notifier.updateSetting(
        'telegram_admin_ids',
        _adminsCtrl.text,
        category: 'bot',
      );
      await notifier.updateSetting(
        'telegram_whitelist_ids',
        _whiteCtrl.text,
        category: 'bot',
      );
      await notifier.updateSetting(
        'telegram_blacklist_ids',
        _blackCtrl.text,
        category: 'bot',
      );
      // 也保存Telegram管理员ID到token配置中
      if (_tgAdminIdController.text.trim().isNotEmpty) {
        await notifier.updateSetting(
          'telegram_admin_ids',
          _tgAdminIdController.text.trim(),
          category: 'bot',
        );
      }
      if (mounted) {
        showToast(context, '机器人配置已保存，正在启动 Bot…');
        // 等待 Bot 进程启动并发送心跳后再刷新状态
        await _pollBotStatus();
      }
    } catch (e) {
      if (mounted) showToast(context, '保存失败: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// 轮询 bot 状态，最多等待 ~8 秒，等 bot 心跳上线后再刷新 UI
  Future<void> _pollBotStatus() async {
    for (int i = 0; i < 4; i++) {
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      ref.invalidate(botStatusProvider);
      // 等待 provider 完成获取
      try {
        final status = await ref.read(botStatusProvider.future);
        if (status.isRunning || status.isNapcatEnabled) return;
      } catch (_) {}
    }
  }

  Future<void> _refreshBotStatus({bool showMessage = true}) async {
    ref.invalidate(botStatusProvider);
    ref.invalidate(botRuntimeProvider);
    ref.invalidate(botChatsProvider);
    try {
      await ref.read(botStatusProvider.future);
      if (showMessage && mounted) {
        showToast(context, 'Bot 状态已刷新');
      }
    } catch (e) {
      if (showMessage && mounted) {
        showToast(context, '刷新失败: $e');
      }
    }
  }

  Future<void> _controlTelegramService(String action) async {
    if (_isControllingTelegram) return;
    setState(() => _isControllingTelegram = true);

    final actionLabel = switch (action) {
      'start' => '启动',
      'stop' => '停止',
      'restart' => '重启',
      _ => '操作',
    };

    try {
      final dio = ref.read(apiClientProvider);
      await dio.post('/bot-config/service/telegram/$action');

      if (action == 'start' || action == 'restart') {
        await _pollBotStatus();
      } else {
        await _refreshBotStatus(showMessage: false);
      }

      if (mounted) {
        showToast(context, 'Telegram Bot $actionLabel指令已发送');
      }
    } catch (e) {
      if (mounted) {
        showToast(context, '$actionLabel失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isControllingTelegram = false);
      }
    }
  }

  Future<List<Map<String, dynamic>>> _fetchBotConfigs() async {
    final dio = ref.read(apiClientProvider);
    final response = await dio.get('/bot-config');
    final configs = (response.data as List?) ?? const [];
    return configs
        .map((item) => (item as Map).cast<String, dynamic>())
        .toList();
  }

  Future<int> _resolveBotConfigId(String chatType) async {
    final platform = chatType.startsWith('qq_') ? 'qq' : 'telegram';
    final configs = await _fetchBotConfigs();
    final candidates = configs.where((config) {
      return config['platform'] == platform && config['enabled'] == true;
    }).toList();

    if (candidates.isEmpty) {
      throw StateError(
        platform == 'telegram'
            ? '请先在上方配置并启用 Telegram Bot。'
            : '请先在上方配置并启用 QQ Bot。',
      );
    }

    final primary = candidates.where((config) => config['is_primary'] == true);
    final chosen = primary.isNotEmpty ? primary.first : candidates.first;
    return (chosen['id'] as num).toInt();
  }

  Future<void> _syncConfiguredChats() async {
    if (_isSyncingChats) return;
    setState(() => _isSyncingChats = true);

    try {
      final dio = ref.read(apiClientProvider);
      final configs = await _fetchBotConfigs();
      final activeConfigs = configs.where((config) {
        if (config['enabled'] != true) {
          return false;
        }

        final platform = (config['platform'] ?? '').toString();
        if (platform == 'telegram') {
          return (config['bot_token_masked'] ?? '').toString().isNotEmpty;
        }
        if (platform == 'qq') {
          return (config['napcat_http_url'] ?? '').toString().isNotEmpty;
        }
        return false;
      }).toList();

      if (activeConfigs.isEmpty) {
        if (mounted) {
          showToast(context, '请先配置并启用至少一个 Bot');
        }
        return;
      }

      int total = 0;
      int updated = 0;
      int created = 0;
      int failed = 0;

      for (final config in activeConfigs) {
        final response = await dio.post(
          '/bot-config/${config['id']}/sync-chats',
        );
        final data = (response.data as Map).cast<String, dynamic>();
        total += (data['total'] as num?)?.toInt() ?? 0;
        updated += (data['updated'] as num?)?.toInt() ?? 0;
        created += (data['created'] as num?)?.toInt() ?? 0;
        failed += (data['failed'] as num?)?.toInt() ?? 0;
      }

      ref.invalidate(botChatsProvider);
      ref.invalidate(botStatusProvider);
      await ref.read(botChatsProvider.future);

      if (mounted) {
        showToast(context, '同步完成：$updated 更新，$created 新增，$failed 失败，$total 总计');
      }
    } catch (e) {
      if (mounted) {
        showToast(context, '同步失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncingChats = false);
      }
    }
  }

  Future<void> _showAddChatDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => BotChatDialog(
        resolveBotConfigId: _resolveBotConfigId,
        onCreate: (chat) async {
          try {
            await ref.read(botChatsProvider.notifier).createChat(chat);
            ref.invalidate(botChatsProvider);
            if (mounted) {
              showToast(context, '群组或频道已添加');
            }
          } catch (e) {
            if (mounted) {
              showToast(context, '添加失败: $e');
            }
            rethrow;
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(systemSettingsProvider);
    final statusAsync = ref.watch(botStatusProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    settingsAsync.whenData(_initFromSettings);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      children: [
        // ── 当前状态横幅 ──
        statusAsync.when(
          data: (s) => Column(
            children: [
              _buildStatusBanner(s, colorScheme, theme),
              const SizedBox(height: 12),
              _buildBotControlActions(context, s),
            ],
          ),
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
        ),
        const SizedBox(height: 24),
        const SectionHeader(title: '机器人推送配置', icon: Icons.smart_toy_rounded),
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Theme(
            data: theme.copyWith(
              dividerColor: Colors.transparent,
              colorScheme: colorScheme.copyWith(secondary: colorScheme.primary),
            ),
            child: ExpansionTile(
              maintainState: true,
              initiallyExpanded: _pushConfigExpanded,
              onExpansionChanged: (expanded) {
                setState(() => _pushConfigExpanded = expanded);
              },
              tilePadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 6,
              ),
              childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.tune_rounded, color: colorScheme.primary),
              ),
              title: const Text('凭证与权限配置'),
              subtitle: Text(
                _pushConfigExpanded
                    ? '展开中，可编辑 Bot 凭证、管理员与访问控制'
                    : '默认收起，按需展开编辑 Bot 凭证与访问权限',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              children: [
                Stepper(
                  type: StepperType.vertical,
                  currentStep: _currentStep,
                  physics: const NeverScrollableScrollPhysics(),
                  onStepTapped: (i) => setState(() => _currentStep = i),
                  onStepContinue: () {
                    if (_currentStep < 2) {
                      setState(() => _currentStep++);
                    } else {
                      _saveConfig();
                    }
                  },
                  onStepCancel: () {
                    if (_currentStep > 0) setState(() => _currentStep--);
                  },
                  controlsBuilder: (context, details) {
                    final isLast = _currentStep == 2;
                    return Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: Row(
                        children: [
                          FilledButton.icon(
                            onPressed: _isSaving
                                ? null
                                : details.onStepContinue,
                            icon: _isSaving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(
                                    isLast
                                        ? Icons.save_rounded
                                        : Icons.arrow_forward,
                                    size: 18,
                                  ),
                            label: Text(isLast ? '保存配置' : '下一步'),
                          ),
                          if (_currentStep > 0) ...[
                            const SizedBox(width: 12),
                            OutlinedButton(
                              onPressed: _isSaving
                                  ? null
                                  : details.onStepCancel,
                              child: const Text('上一步'),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                  steps: [
                    Step(
                      title: const Text('选择推送平台'),
                      subtitle: Text(
                        _botPlatform == 'telegram'
                            ? 'Telegram Bot'
                            : 'QQ Napcat',
                      ),
                      isActive: _currentStep >= 0,
                      state: _currentStep > 0
                          ? StepState.complete
                          : StepState.indexed,
                      content: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('选择您要配置的推送平台：'),
                          const SizedBox(height: 16),
                          SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(
                                value: 'telegram',
                                label: Text('Telegram'),
                                icon: Icon(Icons.send),
                              ),
                              ButtonSegment(
                                value: 'qq',
                                label: Text('QQ (Napcat)'),
                                icon: Icon(Icons.alternate_email),
                              ),
                            ],
                            selected: {_botPlatform},
                            onSelectionChanged: (s) =>
                                setState(() => _botPlatform = s.first),
                          ),
                        ],
                      ),
                    ),
                    Step(
                      title: const Text('填写凭证'),
                      subtitle: Text(
                        _botPlatform == 'telegram'
                            ? 'Bot Token 与管理员 ID'
                            : 'Napcat HTTP 地址',
                      ),
                      isActive: _currentStep >= 1,
                      state: _currentStep > 1
                          ? StepState.complete
                          : StepState.indexed,
                      content: Column(
                        children: [
                          if (_botPlatform == 'telegram') ...[
                            TextField(
                              controller: _tgTokenController,
                              decoration: const InputDecoration(
                                labelText: 'Bot Token',
                                hintText: '12345678:ABC-DEF...',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.key_rounded),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _tgAdminIdController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: '管理员 Telegram ID',
                                hintText: '123456789',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.person_rounded),
                                helperText:
                                    '您的 Telegram 用户 ID（可通过 @userinfobot 获取）',
                              ),
                            ),
                          ] else ...[
                            TextField(
                              controller: _qqUrlController,
                              decoration: const InputDecoration(
                                labelText: 'Napcat HTTP API 地址',
                                hintText: 'http://127.0.0.1:3000',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.link_rounded),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Step(
                      title: const Text('权限与访问控制'),
                      subtitle: const Text('管理员、白名单与黑名单'),
                      isActive: _currentStep >= 2,
                      state: _currentStep == 2
                          ? StepState.editing
                          : StepState.indexed,
                      content: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '配置可使用 Bot 的用户 ID。留空则不限制。',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.outline,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _buildPermissionField(
                            controller: _adminsCtrl,
                            label: '超级管理员 ID（逗号分隔）',
                            hint: '123456, 789012',
                            icon: Icons.admin_panel_settings_rounded,
                          ),
                          const SizedBox(height: 12),
                          _buildPermissionField(
                            controller: _whiteCtrl,
                            label: '白名单 ID（逗号分隔）',
                            hint: '允许使用 Bot 的用户 ID',
                            icon: Icons.check_circle_rounded,
                          ),
                          const SizedBox(height: 12),
                          _buildPermissionField(
                            controller: _blackCtrl,
                            label: '黑名单 ID（逗号分隔）',
                            hint: '禁止使用 Bot 的用户 ID',
                            icon: Icons.block_rounded,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 32),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(title: '群组与频道管理', icon: Icons.groups_rounded),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _isSyncingChats ? null : _syncConfiguredChats,
                    icon: _isSyncingChats
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync_rounded),
                    label: Text(_isSyncingChats ? '同步中...' : '同步群组'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _showAddChatDialog,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('手动新增'),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildGroupManagement(context, ref),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildPermissionField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        TextField(
          controller: controller,
          minLines: 2,
          maxLines: 2,
          textAlignVertical: TextAlignVertical.top,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: colorScheme.surfaceContainerHigh,
            prefixIcon: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Icon(icon),
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 48),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: colorScheme.primary.withValues(alpha: 0.6),
                width: 1.5,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGroupManagement(BuildContext context, WidgetRef ref) {
    final chatsAsync = ref.watch(botChatsProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return chatsAsync.when(
      data: (chats) {
        if (chats.isEmpty) {
          return Card(
            elevation: 0,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                children: [
                  Icon(
                    Icons.speaker_notes_off_rounded,
                    size: 48,
                    color: colorScheme.outline.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '尚未发现任何群组或频道',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '先点击“同步群组”从已启用 Bot 拉取会话，或点击“手动新增”直接补录目标。',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 12),
              child: Text(
                '当前共 ${chats.length} 个目标，可分别控制启用、巡逻监听与分发推送。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            SettingGroup(
              children: chats
                  .map((chat) => _buildChatTile(context, ref, chat))
                  .toList(),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(Icons.error_outline_rounded, color: colorScheme.error),
              const SizedBox(width: 12),
              Expanded(child: Text('群组列表加载失败: $e')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatTile(BuildContext context, WidgetRef ref, BotChat chat) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  chat.isTelegram
                      ? Icons.telegram_rounded
                      : Icons.alternate_email_rounded,
                  size: 20,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      chat.displayName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      chat.chatTypeLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: chat.enabled,
                onChanged: (val) => ref
                    .read(botChatsProvider.notifier)
                    .updateChatStatus(chat.chatId, enabled: val),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildCompactToggle(
                context,
                '巡逻监听',
                chat.isMonitoring,
                (val) => ref
                    .read(botChatsProvider.notifier)
                    .updateChatStatus(chat.chatId, isMonitoring: val),
                Icons.radar_rounded,
              ),
              const SizedBox(width: 12),
              _buildCompactToggle(
                context,
                '分发推送',
                chat.isPushTarget,
                (val) => ref
                    .read(botChatsProvider.notifier)
                    .updateChatStatus(chat.chatId, isPushTarget: val),
                Icons.auto_awesome_motion_rounded,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompactToggle(
    BuildContext context,
    String label,
    bool value,
    Function(bool) onChanged,
    IconData icon,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return Expanded(
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: value
                ? colorScheme.primaryContainer.withValues(alpha: 0.2)
                : colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: value
                  ? colorScheme.primary.withValues(alpha: 0.3)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: value ? colorScheme.primary : colorScheme.outline,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: value ? FontWeight.bold : FontWeight.normal,
                  color: value ? colorScheme.primary : colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              SizedBox(
                height: 20,
                width: 32,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: Switch(
                    value: value,
                    onChanged: onChanged,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBotControlActions(BuildContext context, dynamic status) {
    final bool isRunning = status.isRunning == true;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.tonalIcon(
          onPressed: _isControllingTelegram ? null : () => _refreshBotStatus(),
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('刷新状态'),
        ),
        FilledButton.tonalIcon(
          onPressed: (_isControllingTelegram || isRunning)
              ? null
              : () => _controlTelegramService('start'),
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('启动 Bot'),
        ),
        FilledButton.tonalIcon(
          onPressed: (_isControllingTelegram || !isRunning)
              ? null
              : () => _controlTelegramService('stop'),
          icon: const Icon(Icons.stop_rounded),
          label: const Text('停止 Bot'),
        ),
        FilledButton.tonalIcon(
          onPressed: _isControllingTelegram
              ? null
              : () => _controlTelegramService('restart'),
          icon: _isControllingTelegram
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.restart_alt_rounded),
          label: Text(_isControllingTelegram ? '处理中...' : '重启 Bot'),
        ),
      ],
    );
  }

  /// 顶部状态横幅：显示当前Bot运行状态
  Widget _buildStatusBanner(
    dynamic status,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    final bool isRunning = status.isRunning == true;
    final bool hasNapcat = status.isNapcatEnabled == true;
    final String? username = status.botUsername as String?;

    if (!isRunning && !hasNapcat) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: colorScheme.errorContainer.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorScheme.error.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: colorScheme.error,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '推送机器人未运行或未配置，请检查下方配置并可手动启动',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.error,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: Colors.green, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isRunning
                      ? 'Telegram Bot 运行中${username != null ? ' (@$username)' : ''}'
                      : 'QQ Bot (Napcat) 已配置',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.green.shade700,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (hasNapcat && isRunning)
                  Text(
                    'QQ Napcat 同步已启用',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.green.shade600,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
