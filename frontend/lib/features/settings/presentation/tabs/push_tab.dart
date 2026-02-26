import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/setting_components.dart';
import '../../providers/settings_provider.dart';
import '../../models/system_setting.dart';
import '../../../../core/network/api_client.dart';
import '../../../review/providers/bot_chats_provider.dart';

class PushTab extends ConsumerStatefulWidget {
  const PushTab({super.key});

  @override
  ConsumerState<PushTab> createState() => _PushTabState();
}

class _PushTabState extends ConsumerState<PushTab> {
  int _currentStep = 0;
  bool _isSaving = false;
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
          data: (s) => _buildStatusBanner(s, colorScheme, theme),
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
        ),
        const SizedBox(height: 24),
        const SectionHeader(title: '机器人推送配置', icon: Icons.smart_toy_rounded),
        const SizedBox(height: 16),
        // ── Stepper 卡片 ──
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Theme(
            // 让 Stepper 使用 primary 颜色高亮
            data: theme.copyWith(
              colorScheme: colorScheme.copyWith(secondary: colorScheme.primary),
            ),
            child: Stepper(
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
                        onPressed: _isSaving ? null : details.onStepContinue,
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
                          onPressed: _isSaving ? null : details.onStepCancel,
                          child: const Text('上一步'),
                        ),
                      ],
                    ],
                  ),
                );
              },
              steps: [
                // ── 步骤1: 选择平台 ──
                Step(
                  title: const Text('选择推送平台'),
                  subtitle: Text(
                    _botPlatform == 'telegram' ? 'Telegram Bot' : 'QQ Napcat',
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

                // ── 步骤2: 填写凭证 ──
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

                // ── 步骤3: 权限配置 ──
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
                      TextField(
                        controller: _adminsCtrl,
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: '超级管理员 ID（逗号分隔）',
                          hintText: '123456, 789012',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          prefixIcon: const Icon(
                            Icons.admin_panel_settings_rounded,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _whiteCtrl,
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: '白名单 ID（逗号分隔）',
                          hintText: '允许使用 Bot 的用户 ID',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          prefixIcon: const Icon(Icons.check_circle_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _blackCtrl,
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: '黑名单 ID（逗号分隔）',
                          hintText: '禁止使用 Bot 的用户 ID',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          prefixIcon: const Icon(Icons.block_rounded),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 40),
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
                '尚未配置推送机器人，请完成下方配置',
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
