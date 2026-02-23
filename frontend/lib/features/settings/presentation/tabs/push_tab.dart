import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../bot/bot_management_page.dart';
import '../widgets/setting_components.dart';
import '../../providers/settings_provider.dart';
import '../../models/system_setting.dart';

class PushTab extends ConsumerWidget {
  const PushTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      children: [
        const SectionHeader(title: '机器人推送设置'),
        SettingGroup(
          children: [
            SettingTile(
              title: 'Bot 管理与多端同步',
              subtitle: '配置 Telegram / QQ Bot，并同步群组',
              icon: Icons.smart_toy_rounded,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const BotManagementPage()),
                );
              },
            ),
            ExpandableSettingTile(
              title: 'Telegram Bot 权限控制',
              subtitle: '配置管理员、白名单与黑名单',
              icon: Icons.security_rounded,
              expandedContent: _buildBotPermissionsEditor(context, ref),
            ),
          ],
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildBotPermissionsEditor(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(systemSettingsProvider);
    return settingsAsync.when(
      data: (settings) {
        final admins = settings.firstWhere((s) => s.key == 'telegram_admin_ids', orElse: () => const SystemSetting(key: '', value: '')).value as String? ?? '';
        final whitelist = settings.firstWhere((s) => s.key == 'telegram_whitelist_ids', orElse: () => const SystemSetting(key: '', value: '')).value as String? ?? '';
        final blacklist = settings.firstWhere((s) => s.key == 'telegram_blacklist_ids', orElse: () => const SystemSetting(key: '', value: '')).value as String? ?? '';

        final adminsCtrl = TextEditingController(text: admins);
        final whiteCtrl = TextEditingController(text: whitelist);
        final blackCtrl = TextEditingController(text: blacklist);

        return Column(
          children: [
            TextField(
              controller: adminsCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: '超级管理员 ID (逗号分隔)',
                hintText: '123456, 789012',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: whiteCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: '白名单 ID (逗号分隔)',
                hintText: '允许使用 Bot 的用户 ID',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: blackCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: '黑名单 ID (逗号分隔)',
                hintText: '禁止使用 Bot 的用户 ID',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(
                onPressed: () async {
                  final notifier = ref.read(systemSettingsProvider.notifier);
                  await notifier.updateSetting('telegram_admin_ids', adminsCtrl.text, category: 'bot');
                  await notifier.updateSetting('telegram_whitelist_ids', whiteCtrl.text, category: 'bot');
                  await notifier.updateSetting('telegram_blacklist_ids', blackCtrl.text, category: 'bot');
                  if (context.mounted) showToast(context, '权限配置已保存');
                },
                child: const Text('保存配置'),
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}
