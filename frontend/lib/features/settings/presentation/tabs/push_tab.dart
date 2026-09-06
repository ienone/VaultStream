import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/setting_components.dart';
import '../../providers/settings_provider.dart';
import '../../providers/bot_config_actions.dart';
import '../../models/system_setting.dart';
import '../../utils/setting_value.dart';
import '../../../automation/providers/bot_chats_provider.dart';
import '../../../automation/models/bot_chat.dart';
import '../../../automation/widgets/bot_chat_dialog.dart';
import '../../../notifications/notification_provider.dart';
import '../../../../theme/design_tokens.dart';

class PushTab extends ConsumerStatefulWidget {
  const PushTab({super.key, this.targetsOnly = false});

  final bool targetsOnly;

  @override
  ConsumerState<PushTab> createState() => _PushTabState();
}

class _PushTabState extends ConsumerState<PushTab> {
  bool _isSaving = false;
  bool _isControllingTelegram = false;
  bool _isSyncingChats = false;
  bool _isGeneratingDigest = false;
  bool _pushConfigExpanded = false;
  String _botPlatform = 'telegram';

  final _tgTokenController = TextEditingController();
  final _qqUrlController = TextEditingController(text: 'http://127.0.0.1:3000');
  final _adminsCtrl = TextEditingController();
  final _whiteCtrl = TextEditingController();
  final _blackCtrl = TextEditingController();

  bool _initialized = false;

  @override
  void dispose() {
    _tgTokenController.dispose();
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
    _adminsCtrl.text = _getSetting(settings, '${_botPlatform}_admin_ids');
    _whiteCtrl.text = _getSetting(settings, '${_botPlatform}_whitelist_ids');
    _blackCtrl.text = _getSetting(settings, '${_botPlatform}_blacklist_ids');
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

  void _reloadPermissionFields() {
    final settings = ref.read(systemSettingsProvider).value;
    if (settings == null) return;
    _adminsCtrl.text = _getSetting(settings, '${_botPlatform}_admin_ids');
    _whiteCtrl.text = _getSetting(settings, '${_botPlatform}_whitelist_ids');
    _blackCtrl.text = _getSetting(settings, '${_botPlatform}_blacklist_ids');
  }

  Future<void> _saveConfig() async {
    setState(() => _isSaving = true);
    try {
      final saveResult = await ref
          .read(botConfigActionsProvider)
          .saveCredentials(
            platform: _botPlatform,
            telegramToken: _tgTokenController.text,
            napcatHttpUrl: _qqUrlController.text,
          );
      if (!saveResult.saved) {
        throw StateError(
          _botPlatform == 'telegram'
              ? '请填写 Telegram Bot Token。'
              : '请填写 Napcat HTTP 地址。',
        );
      }
      // 保存权限配置
      final notifier = ref.read(systemSettingsProvider.notifier);
      await notifier.updateSetting(
        '${_botPlatform}_admin_ids',
        _adminsCtrl.text,
        category: 'bot',
      );
      await notifier.updateSetting(
        '${_botPlatform}_whitelist_ids',
        _whiteCtrl.text,
        category: 'bot',
      );
      await notifier.updateSetting(
        '${_botPlatform}_blacklist_ids',
        _blackCtrl.text,
        category: 'bot',
      );
      if (mounted) {
        final runId = saveResult.followUpRunId;
        final runSuffix = runId == null || runId.isEmpty
            ? ''
            : ' #${runId.length > 8 ? runId.substring(0, 8) : runId}';
        if (saveResult.followUpFailed) {
          showToast(context, '机器人配置已保存；运行时同步失败$runSuffix，请查看任务详情。');
        } else if (saveResult.followUpStatus == 'accepted') {
          showToast(context, '机器人配置已保存；群组同步已提交$runSuffix。');
        } else if (saveResult.followUpRunId != null) {
          showToast(context, '机器人配置已保存；运行时同步已完成$runSuffix。');
          await _pollBotStatus();
        } else {
          showToast(context, '机器人配置已保存。');
        }
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
      final typedAction = switch (action) {
        'start' => TelegramServiceAction.start,
        'stop' => TelegramServiceAction.stop,
        'restart' => TelegramServiceAction.restart,
        _ => throw ArgumentError.value(action, 'action'),
      };
      await ref.read(botConfigActionsProvider).controlTelegram(typedAction);

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

  Future<int> _resolveBotConfigId(String chatType) async {
    return ref.read(botConfigActionsProvider).resolveEnabledConfigId(chatType);
  }

  Future<void> _syncConfiguredChats() async {
    if (_isSyncingChats) return;
    setState(() => _isSyncingChats = true);

    try {
      final result = await ref
          .read(botConfigActionsProvider)
          .syncConfiguredChats();
      if (!result.configured) {
        if (mounted) {
          showToast(context, '请先配置并启用至少一个 Bot');
        }
        return;
      }

      if (mounted) {
        showToast(
          context,
          '同步完成：${result.updated} 更新，${result.created} 新增，'
          '${result.failed} 失败，${result.total} 总计',
        );
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

  Future<void> _updateDigestSetting(String key, Object value) async {
    try {
      await ref
          .read(systemSettingsProvider.notifier)
          .updateSetting(key, value, category: 'notifications');
    } catch (error) {
      if (mounted) showToast(context, '摘要设置保存失败: $error');
    }
  }

  Future<void> _generateDigestNow() async {
    if (_isGeneratingDigest) return;
    setState(() => _isGeneratingDigest = true);
    try {
      final result = await generateNotificationDigest(ref);
      if (!mounted) return;
      final created = result['created'] == true;
      final discoveryCount = (result['discovery_count'] as num?)?.toInt() ?? 0;
      final eventCount = (result['event_count'] as num?)?.toInt() ?? 0;
      showToast(
        context,
        created
            ? '摘要已生成：$discoveryCount 条动态，$eventCount 个事件更新'
            : '本周期没有新的动态或事件变化',
      );
    } catch (error) {
      if (mounted) showToast(context, '摘要生成失败: $error');
    } finally {
      if (mounted) setState(() => _isGeneratingDigest = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(systemSettingsProvider);
    final statusAsync = ref.watch(botStatusProvider);
    settingsAsync.whenData(_initFromSettings);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      children: widget.targetsOnly
          ? [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader(
                    title: '群组与频道管理',
                    icon: Icons.groups_rounded,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: _isSyncingChats
                              ? null
                              : _syncConfiguredChats,
                          icon: _isSyncingChats
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
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
            ]
          : [
              const SectionHeader(
                title: '应用内周期摘要',
                icon: Icons.summarize_rounded,
              ),
              const SizedBox(height: 8),
              settingsAsync.when(
                data: (settings) => _buildDigestSettings(settings),
                loading: () => const LinearProgressIndicator(),
                error: (_, _) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('摘要设置加载失败'),
                  trailing: TextButton(
                    onPressed: () => ref.invalidate(systemSettingsProvider),
                    child: const Text('重试'),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              statusAsync.when(
                data: _buildBotStatus,
                loading: () => const LinearProgressIndicator(),
                error: (_, _) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('机器人状态读取失败'),
                  trailing: TextButton(
                    onPressed: _refreshBotStatus,
                    child: const Text('重试'),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const SectionHeader(
                title: '机器人推送配置',
                icon: Icons.smart_toy_rounded,
              ),
              const SizedBox(height: 8),
              ExpansionTile(
                maintainState: true,
                initiallyExpanded: _pushConfigExpanded,
                onExpansionChanged: (expanded) =>
                    setState(() => _pushConfigExpanded = expanded),
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 16),
                title: const Text('凭证与权限'),
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _botPlatform,
                    decoration: const InputDecoration(labelText: '推送平台'),
                    items: const [
                      DropdownMenuItem(
                        value: 'telegram',
                        child: Text('Telegram'),
                      ),
                      DropdownMenuItem(value: 'qq', child: Text('QQ (Napcat)')),
                    ],
                    onChanged: _isSaving
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() => _botPlatform = value);
                            _reloadPermissionFields();
                          },
                  ),
                  const SizedBox(height: 20),
                  if (_botPlatform == 'telegram')
                    TextField(
                      controller: _tgTokenController,
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      decoration: const InputDecoration(labelText: 'Bot Token'),
                    )
                  else
                    TextField(
                      controller: _qqUrlController,
                      decoration: const InputDecoration(
                        labelText: 'Napcat HTTP API 地址',
                      ),
                    ),
                  const SizedBox(height: 20),
                  _buildPermissionField(
                    controller: _adminsCtrl,
                    label: '超级管理员 ID',
                    hint: '多个 ID 用逗号分隔',
                  ),
                  const SizedBox(height: 20),
                  _buildPermissionField(
                    controller: _whiteCtrl,
                    label: '白名单 ID',
                    hint: '多个 ID 用逗号分隔',
                  ),
                  const SizedBox(height: 20),
                  _buildPermissionField(
                    controller: _blackCtrl,
                    label: '黑名单 ID',
                    hint: '多个 ID 用逗号分隔',
                  ),
                  const SizedBox(height: 24),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: _isSaving ? null : _saveConfig,
                      child: Text(_isSaving ? '保存中…' : '保存配置'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              TextButton(
                onPressed: () => context.push('/settings?tab=targets'),
                child: const Text('管理推送目标'),
              ),
              const SizedBox(height: 40),
            ],
    );
  }

  Widget _buildDigestSettings(List<SystemSetting> settings) {
    final enabled = parseBoolSetting(
      getSettingValue(settings, 'enable_notification_digest', false),
      false,
    );
    final interval = parseIntSetting(
      getSettingValue(settings, 'notification_digest_interval_hours', 24),
      24,
    );
    const intervalOptions = <int>[6, 12, 24, 168];
    final selectedInterval = intervalOptions.contains(interval) ? interval : 24;

    return SettingGroup(
      children: [
        SettingTile(
          title: '周期摘要',
          subtitle: '定期汇总新动态和事件变化',
          icon: Icons.notifications_active_outlined,
          showArrow: false,
          trailing: Switch(
            key: const ValueKey('notification-digest-enabled'),
            value: enabled,
            onChanged: (value) =>
                _updateDigestSetting('enable_notification_digest', value),
          ),
        ),
        SettingTile(
          title: '摘要周期',
          subtitle: '只统计上次检查后新出现的动态和事件变化',
          icon: Icons.schedule_rounded,
          showArrow: false,
          trailing: DropdownButton<int>(
            value: selectedInterval,
            items: const [
              DropdownMenuItem(value: 6, child: Text('每 6 小时')),
              DropdownMenuItem(value: 12, child: Text('每 12 小时')),
              DropdownMenuItem(value: 24, child: Text('每天')),
              DropdownMenuItem(value: 168, child: Text('每周')),
            ],
            onChanged: (value) {
              if (value != null) {
                _updateDigestSetting(
                  'notification_digest_interval_hours',
                  value,
                );
              }
            },
          ),
        ),
        SettingTile(
          title: '立即检查',
          icon: Icons.refresh_rounded,
          showArrow: false,
          trailing: FilledButton.tonalIcon(
            onPressed: _isGeneratingDigest ? null : _generateDigestNow,
            icon: _isGeneratingDigest
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.summarize_rounded),
            label: Text(_isGeneratingDigest ? '检查中' : '生成摘要'),
          ),
        ),
      ],
    );
  }

  Widget _buildPermissionField({
    required TextEditingController controller,
    required String label,
    required String hint,
  }) => TextField(
    controller: controller,
    decoration: InputDecoration(labelText: label, hintText: hint),
  );

  Widget _buildGroupManagement(BuildContext context, WidgetRef ref) {
    final chatsAsync = ref.watch(botChatsProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return chatsAsync.when(
      data: (chats) {
        if (chats.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('暂无推送目标。同步已启用 Bot 的群组，或手动新增。'),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 12),
              child: Text(
                '${chats.length} 个推送目标',
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
      error: (_, _) => ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('推送目标加载失败'),
        trailing: TextButton(
          onPressed: () => ref.invalidate(botChatsProvider),
          child: const Text('重试'),
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
                  borderRadius: AppShape.cardMediaBorder,
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
                    .updateChatStatus(chat.id, enabled: val),
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
                    .updateChatStatus(chat.id, isMonitoring: val),
                Icons.radar_rounded,
              ),
              const SizedBox(width: 12),
              _buildCompactToggle(
                context,
                '分发推送',
                chat.isPushTarget,
                (val) => ref
                    .read(botChatsProvider.notifier)
                    .updateChatStatus(chat.id, isPushTarget: val),
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Expanded(
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: AppShape.cardMediaBorder,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: value
                ? colorScheme.primaryContainer.withValues(alpha: 0.2)
                : colorScheme.surfaceContainerHigh,
            borderRadius: AppShape.cardMediaBorder,
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
                style: theme.textTheme.labelMedium?.copyWith(
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

  Widget _buildBotStatus(BotStatus status) {
    final username = status.botUsername;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                status.isRunning
                    ? 'Telegram 运行中${username != null ? ' · @$username' : ''}'
                    : 'Telegram 未运行',
              ),
            ),
            IconButton(
              tooltip: '刷新机器人状态',
              onPressed: _isControllingTelegram ? null : _refreshBotStatus,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        if (status.isNapcatEnabled)
          Text(status.isNapcatOnline ? 'QQ 已连接' : 'QQ 未连接，请检查 Napcat 配置'),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: _isControllingTelegram
                  ? null
                  : () => _controlTelegramService(
                      status.isRunning ? 'stop' : 'start',
                    ),
              child: Text(
                _isControllingTelegram
                    ? '处理中…'
                    : status.isRunning
                    ? '停止 Telegram'
                    : '启动 Telegram',
              ),
            ),
            if (status.isRunning)
              TextButton(
                onPressed: _isControllingTelegram
                    ? null
                    : () => _controlTelegramService('restart'),
                child: const Text('重启 Telegram'),
              ),
          ],
        ),
      ],
    );
  }
}
