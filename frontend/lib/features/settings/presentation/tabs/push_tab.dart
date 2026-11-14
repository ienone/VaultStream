import 'package:flutter/foundation.dart' show listEquals;

import '../../../../core/layout/app_page_body.dart';
import '../../../../theme/design_tokens.dart';

import 'package:frontend/core/network/api_client.dart';
import 'package:material_ui/material_ui.dart';
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
import '../../../../core/widgets/app_filter_menu.dart';

class PushTab extends ConsumerStatefulWidget {
  const PushTab({
    super.key,
    this.targetsOnly = false,
    this.monitoringOnly = false,
    this.platform,
  });

  final String? platform;

  final bool targetsOnly;
  final bool monitoringOnly;

  @override
  ConsumerState<PushTab> createState() => _PushTabState();
}

class _PushTabState extends ConsumerState<PushTab> {
  bool _isSaving = false;
  bool _isControllingTelegram = false;
  bool _isSyncingChats = false;
  bool _isGeneratingDigest = false;
  String get _botPlatform => widget.platform ?? 'telegram';
  bool _qqAgentEnabled = false;
  Map<String, dynamic> _originalAccess = {};
  final _updatingChats = <int>{};
  final _chatErrors = <int, String>{};

  final _tgTokenController = TextEditingController();
  final _qqUrlController = TextEditingController();
  bool _loadedCredentials = false;
  final _adminsCtrl = TextEditingController();
  final _whiteCtrl = TextEditingController();
  final _blackCtrl = TextEditingController();

  bool _initialized = false;

  @override
  void didUpdateWidget(PushTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.platform != widget.platform) {
      _initialized = false;
      _loadedCredentials = false;
      _tgTokenController.clear();
    }
  }

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
    final values = {for (final row in settings) row.key: row.value};
    if (_botPlatform == 'qq') {
      final policy = values['qq_bot_agent'] as Map? ?? const {};
      _adminsCtrl.text = (policy['admin_qq'] as List? ?? const []).join(', ');
      _whiteCtrl.text = (policy['group_ids'] as List? ?? const []).join(', ');
      _qqAgentEnabled = policy['enabled'] == true;
    } else {
      _adminsCtrl.text = (values['telegram_admin_ids'] ?? '').toString();
      _whiteCtrl.text = (values['telegram_whitelist_ids'] ?? '').toString();
      _blackCtrl.text = (values['telegram_blacklist_ids'] ?? '').toString();
    }
    _originalAccess = _access();
  }

  Map<String, dynamic> _access() {
    List<String> ids(TextEditingController field) =>
        field.text
            .split(RegExp(r'[,，\s]+'))
            .where((part) => part.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return {
      'admins': ids(_adminsCtrl),
      if (_botPlatform == 'qq') ...{
        'groups': ids(_whiteCtrl),
        'agent_enabled': _qqAgentEnabled,
      } else ...{
        'allowed_users': ids(_whiteCtrl),
        'blocked_users': ids(_blackCtrl),
      },
    };
  }

  BotConfigRecord? _platformConfig(List<BotConfigRecord> configs) {
    final matches = configs.where((row) => row.platform == _botPlatform);
    return matches.where((row) => row.primary).firstOrNull ??
        matches.where((row) => row.enabled).firstOrNull ??
        matches.firstOrNull;
  }

  Future<void> _saveConfig() async {
    final configs = ref.read(botConfigsProvider).requireValue;
    final platform = _botPlatform;
    final access = _access();
    final changed = Map.of(access)
      ..removeWhere(
        (k, value) => value is List<String>
            ? listEquals(value, _originalAccess[k] as List<String>?)
            : value == _originalAccess[k],
      );
    setState(() => _isSaving = true);
    try {
      final saveResult = await ref
          .read(botConfigActionsProvider)
          .saveConfig(
            platform: platform,
            existing: _platformConfig(configs),
            access: changed,
            telegramToken: _tgTokenController.text,
            napcatHttpUrl: _qqUrlController.text,
          );
      if (!mounted) return;
      _tgTokenController.clear();
      _originalAccess = access;
      if (changed.isNotEmpty) ref.invalidate(systemSettingsProvider);
      if (mounted) {
        if (saveResult?.followUpFailed == true) {
          showToast(context, '配置已保存，但机器人同步失败，请查看任务详情。');
        } else if (saveResult?.followUpStatus == 'accepted') {
          showToast(context, '配置已保存，正在同步群组。');
        } else if (saveResult?.followUpRunId != null) {
          showToast(context, '机器人配置已保存并应用。');
        } else {
          showToast(context, '机器人配置已保存。');
        }
      }
    } catch (e) {
      if (mounted) {
        showToast(context, formatApiErrorMessage(e, fallbackMessage: '保存失败'));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _refreshBotStatus({bool showMessage = true}) async {
    ref.invalidate(botStatusProvider);
    ref.invalidate(botChatsProvider);
    try {
      await ref.read(botStatusProvider.future);
      if (showMessage && mounted) {
        showToast(context, 'Bot 状态已刷新');
      }
    } catch (e) {
      if (showMessage && mounted) {
        showToast(context, formatApiErrorMessage(e, fallbackMessage: '刷新失败'));
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

      if (mounted) {
        showToast(context, 'Telegram Bot 已$actionLabel');
      }
    } catch (e) {
      if (mounted) {
        showToast(
          context,
          formatApiErrorMessage(e, fallbackMessage: '$actionLabel失败'),
        );
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
          .syncConfiguredChats(platform: widget.platform);
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
        showToast(context, formatApiErrorMessage(e, fallbackMessage: '同步失败'));
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncingChats = false);
      }
    }
  }

  String get _addChatLabel => widget.monitoringOnly
      ? '添加监听来源'
      : widget.targetsOnly
      ? '添加推送目标'
      : '添加群组或频道';

  Future<void> _showAddChatDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => BotChatDialog(
        createTitle: _addChatLabel,
        monitoringOnly: widget.monitoringOnly,
        platform: widget.platform,
        resolveBotConfigId: _resolveBotConfigId,
        onCreate: (chat) async {
          try {
            await ref
                .read(botChatsProvider.notifier)
                .createChat(
                  chat.copyWith(
                    isMonitoring: widget.monitoringOnly,
                    isPushTarget: widget.targetsOnly,
                  ),
                );
            ref.invalidate(botChatsProvider);
            if (mounted) {
              showToast(context, '群组或频道已添加');
            }
          } catch (e) {
            if (mounted) {
              showToast(
                context,
                formatApiErrorMessage(e, fallbackMessage: '添加失败'),
              );
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
      if (mounted) {
        showToast(
          context,
          formatApiErrorMessage(error, fallbackMessage: '摘要设置保存失败'),
        );
      }
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
      if (mounted) {
        showToast(
          context,
          formatApiErrorMessage(error, fallbackMessage: '摘要生成失败'),
        );
      }
    } finally {
      if (mounted) setState(() => _isGeneratingDigest = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = widget.targetsOnly || widget.monitoringOnly
        ? null
        : ref.watch(systemSettingsProvider);
    final statusAsync = widget.platform == null
        ? null
        : ref.watch(botStatusProvider);
    settingsAsync?.whenData(_initFromSettings);
    final configs =
        widget.platform != null && !widget.targetsOnly && !widget.monitoringOnly
        ? ref.watch(botConfigsProvider)
        : null;
    if (!_loadedCredentials && configs?.hasValue == true) {
      _qqUrlController.text =
          _platformConfig(configs!.requireValue)?.napcatHttpUrl ?? '';
      _loadedCredentials = true;
    }

    final embedded =
        widget.platform != null &&
        !widget.targetsOnly &&
        !widget.monitoringOnly;
    final content = ListView(
      shrinkWrap: embedded,
      physics: embedded ? const NeverScrollableScrollPhysics() : null,
      padding: embedded
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      children: widget.targetsOnly || widget.monitoringOnly
          ? [
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
                      label: Text(_isSyncingChats ? '同步中…' : '同步群组与频道'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _showAddChatDialog,
                      icon: const Icon(Icons.add_rounded),
                      label: Text(_addChatLabel),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _buildGroupManagement(context, ref),
            ]
          : [
              if (widget.platform == null) ...[
                const SectionHeader(title: '应用内摘要'),
                settingsAsync!.when(
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
              ] else ...[
                SectionHeader(
                  title: '机器人服务',
                  padding: const EdgeInsets.only(bottom: 12),
                  action: IconButton(
                    tooltip: '刷新机器人状态',
                    onPressed: _isControllingTelegram
                        ? null
                        : _refreshBotStatus,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ),
                statusAsync!.when(
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
                ExpansionTile(
                  key: PageStorageKey('bot-access-$_botPlatform'),
                  leading: const Icon(Icons.manage_accounts_outlined),
                  title: const Text('连接与权限'),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (configs?.hasError == true)
                      SettingLoadFailure(
                        onRetry: () => ref.invalidate(botConfigsProvider),
                      ),
                    if (settingsAsync?.hasError == true)
                      SettingLoadFailure(
                        onRetry: () => ref.invalidate(systemSettingsProvider),
                      ),
                    const SizedBox(height: 20),
                    if (_botPlatform == 'telegram')
                      TextField(
                        controller: _tgTokenController,
                        obscureText: true,
                        enableSuggestions: false,
                        autocorrect: false,
                        decoration: InputDecoration(
                          hintText:
                              configs?.value != null &&
                                  _platformConfig(configs!.requireValue)
                                          ?.botTokenConfigured ==
                                      true
                              ? '已配置，留空保留'
                              : null,
                          labelText: 'Bot Token',
                        ),
                      )
                    else
                      TextField(
                        controller: _qqUrlController,
                        decoration: const InputDecoration(
                          labelText: 'Napcat HTTP API 地址',
                          hintText: 'http://127.0.0.1:3000',
                        ),
                      ),
                    const SizedBox(height: 20),
                    if (_botPlatform == 'qq')
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('启用 QQ 助手'),
                        value: _qqAgentEnabled,
                        onChanged: _isSaving
                            ? null
                            : (v) => setState(() => _qqAgentEnabled = v),
                      ),
                    _buildPermissionField(
                      controller: _adminsCtrl,
                      label: _botPlatform == 'qq' ? '管理员 QQ 号' : '管理员用户 ID',
                      hint: '多个 ID 用逗号分隔',
                    ),
                    const SizedBox(height: 20),
                    _buildPermissionField(
                      controller: _whiteCtrl,
                      label: _botPlatform == 'qq' ? '允许使用助手的群号' : '允许使用的用户 ID',
                      hint: '多个 ID 用逗号分隔',
                    ),
                    if (_botPlatform == 'telegram') ...[
                      const SizedBox(height: 20),
                      _buildPermissionField(
                        controller: _blackCtrl,
                        label: '禁止访问的用户 ID',
                        hint: '多个 ID 用逗号分隔',
                      ),
                    ],
                    const SizedBox(height: 24),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed:
                            _isSaving ||
                                configs?.hasValue != true ||
                                settingsAsync?.hasValue != true
                            ? null
                            : _saveConfig,
                        child: Text(_isSaving ? '保存中…' : '保存配置'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => context.go('/sources/chats'),
                      child: const Text('管理聊天来源'),
                    ),
                    TextButton(
                      onPressed: () =>
                          context.go('/automation/distribution/targets'),
                      child: const Text('推送目标'),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 40),
            ],
    );
    return AppPageBody(
      maxWidth: widget.targetsOnly || widget.monitoringOnly
          ? AppPane.readableMaxWidth
          : AppPane.workspaceMaxWidth,
      child: content,
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
        SwitchListTile(
          key: const ValueKey('notification-digest-enabled'),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 8,
          ),
          shape: const RoundedRectangleBorder(),
          title: const Text('定期生成摘要'),
          value: enabled,
          onChanged: (value) =>
              _updateDigestSetting('enable_notification_digest', value),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
              final inline = constraints.maxWidth >= 400 * scale;
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: inline ? 200 * scale : constraints.maxWidth,
                    child: AppFilterMenu(
                      label: enabled ? '定时周期' : '定时周期（定时已关闭）',
                      value: selectedInterval.toString(),
                      options: const {
                        '6': '每 6 小时',
                        '12': '每 12 小时',
                        '24': '每天',
                        '168': '每周',
                      },
                      onOpened: () =>
                          FocusManager.instance.primaryFocus?.unfocus(),
                      onSelected: (value) => _updateDigestSetting(
                        'notification_digest_interval_hours',
                        int.parse(value),
                      ),
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _isGeneratingDigest ? null : _generateDigestNow,
                    icon: _isGeneratingDigest
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.summarize_rounded),
                    label: Text(_isGeneratingDigest ? '生成中' : '立即生成摘要'),
                  ),
                ],
              );
            },
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
      data: (allChats) {
        final chats = allChats
            .where(
              (chat) =>
                  widget.platform == null ||
                  (widget.platform == 'qq' ? chat.isQQ : chat.isTelegram),
            )
            .toList();
        if (chats.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              widget.monitoringOnly
                  ? '尚未添加监听来源'
                  : widget.targetsOnly
                  ? '尚未添加推送目标'
                  : '暂无群组或频道',
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 12),
              child: Text(
                '${chats.length} 个群组或频道',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            SettingGroup(
              children: chats
                  .map(
                    (chat) => _buildChatTile(
                      context,
                      ref,
                      chat,
                      disambiguate:
                          chats
                              .where(
                                (other) =>
                                    other.displayName == chat.displayName,
                              )
                              .length >
                          1,
                    ),
                  )
                  .toList(),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('群组与频道加载失败'),
        trailing: TextButton(
          onPressed: () => ref.invalidate(botChatsProvider),
          child: const Text('重试'),
        ),
      ),
    );
  }

  Future<void> _updateChat(
    int id, {
    bool? enabled,
    bool? isMonitoring,
    bool? isPushTarget,
  }) async {
    setState(() {
      _updatingChats.add(id);
      _chatErrors.remove(id);
    });
    try {
      await ref
          .read(botChatsProvider.notifier)
          .updateChatStatus(
            id,
            enabled: enabled,
            isMonitoring: isMonitoring,
            isPushTarget: isPushTarget,
          );
      await ref.read(botChatsProvider.future);
    } catch (error) {
      if (mounted) {
        setState(
          () => _chatErrors[id] = formatApiErrorMessage(
            error,
            fallbackMessage: '保存失败，请重试',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _updatingChats.remove(id));
    }
  }

  Widget _buildChatTile(
    BuildContext context,
    WidgetRef ref,
    BotChat chat, {
    required bool disambiguate,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_updatingChats.contains(chat.id)) const LinearProgressIndicator(),
          if (_chatErrors[chat.id] case final error?)
            Text(error, style: TextStyle(color: theme.colorScheme.error)),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            shape: const RoundedRectangleBorder(),
            title: Text(
              chat.displayName,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              [
                chat.chatTypeLabel,
                if (disambiguate)
                  chat.username == null ? chat.chatId : '@${chat.username}',
                if (widget.targetsOnly && chat.enabled)
                  chat.isPushTarget ? '允许推送' : '不推送',
                if (widget.monitoringOnly && chat.enabled)
                  chat.isMonitoring ? '接收动态' : '不接收动态',
                if (!chat.isAccessible) '无法访问',
              ].join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            value: widget.targetsOnly
                ? chat.enabled && chat.isPushTarget
                : widget.monitoringOnly
                ? chat.enabled && chat.isMonitoring
                : chat.enabled,
            onChanged:
                _updatingChats.contains(chat.id) ||
                    ((widget.targetsOnly || widget.monitoringOnly) &&
                        !chat.enabled)
                ? null
                : (value) => _updateChat(
                    chat.id,
                    enabled: !widget.targetsOnly && !widget.monitoringOnly
                        ? value
                        : null,
                    isMonitoring: widget.monitoringOnly ? value : null,
                    isPushTarget: widget.targetsOnly ? value : null,
                  ),
          ),
          if ((widget.targetsOnly || widget.monitoringOnly) && !chat.enabled)
            TextButton(
              onPressed: () =>
                  context.go('/accounts/${chat.isQQ ? 'qq' : 'telegram'}'),
              child: const Text('会话已停用 · 管理连接'),
            ),
        ],
      ),
    );
  }

  Widget _buildBotStatus(BotStatus status) {
    final username = status.botUsername;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.platform != 'qq')
            Text(
              status.isRunning ? 'Telegram 运行中' : 'Telegram 未运行',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          if (widget.platform != 'qq' &&
              status.isRunning &&
              username != null) ...[
            const SizedBox(height: 4),
            Text('@$username', style: Theme.of(context).textTheme.bodyMedium),
          ],
          if (widget.platform == 'qq') ...[
            const SizedBox(height: 12),
            Text(status.isNapcatOnline ? 'QQ 已连接' : 'QQ 未连接'),
          ],
          const SizedBox(height: 8),
          if (widget.platform != 'qq')
            Wrap(
              spacing: 8,
              runSpacing: 8,
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
      ),
    );
  }
}
