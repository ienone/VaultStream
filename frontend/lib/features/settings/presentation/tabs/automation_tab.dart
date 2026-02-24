import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/settings_provider.dart';
import '../../models/system_setting.dart';
import '../widgets/setting_components.dart';

class AutomationTab extends ConsumerWidget {
  const AutomationTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(systemSettingsProvider);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      children: [
        const SectionHeader(title: 'AI 发现', icon: Icons.auto_awesome_rounded),
        _buildAiSettings(context, ref, settingsAsync),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildAiSettings(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<SystemSetting>> settingsAsync,
  ) {
    return settingsAsync.when(
      data: (settings) {
        bool parseBool(dynamic val) {
          if (val == null) return false;
          if (val is bool) return val;
          if (val is String) return val.toLowerCase() == 'true';
          return false;
        }

        final enableAi = parseBool(
          settings
              .firstWhere(
                (s) => s.key == 'enable_ai_discovery',
                orElse: () => const SystemSetting(key: '', value: false),
              )
              .value,
        );

        final enableAutoSummary = parseBool(
          settings
              .firstWhere(
                (s) => s.key == 'enable_auto_summary',
                orElse: () => const SystemSetting(key: '', value: false),
              )
              .value,
        );

        final topics = settings
            .firstWhere(
              (s) => s.key == 'discovery_topics',
              orElse: () => const SystemSetting(key: '', value: []),
            )
            .value;

        List<String> topicList = [];
        if (topics is List) {
          topicList = topics.map((e) => e.toString()).toList();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingGroup(
              children: [
                Opacity(
                  opacity: 0.5,
                  child: SettingTile(
                    title: '启用 AI 自动发现 (开发中)',
                    subtitle: '根据订阅主题自动抓取相关内容',
                    icon: Icons.auto_awesome_rounded,
                    trailing: Switch(value: enableAi, onChanged: null),
                    onTap: null,
                  ),
                ),
                SettingTile(
                  title: '启用 AI 自动生成摘要',
                  subtitle: '解析完成后自动调用大模型生成摘要',
                  icon: Icons.summarize_rounded,
                  trailing: Switch(
                    value: enableAutoSummary,
                    onChanged: (val) => ref
                        .read(systemSettingsProvider.notifier)
                        .updateSetting(
                          'enable_auto_summary',
                          val,
                          category: 'llm',
                        ),
                  ),
                  onTap: () => ref
                      .read(systemSettingsProvider.notifier)
                      .updateSetting(
                        'enable_auto_summary',
                        !enableAutoSummary,
                        category: 'llm',
                      ),
                ),
                Opacity(
                  opacity: 0.5,
                  child: SettingTile(
                    title: '订阅主题管理 (开发中)',
                    subtitle: '${topicList.length} 个关注主题',
                    icon: Icons.topic_rounded,
                    onTap: null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            const SectionHeader(
              title: '大模型引擎 (LLM)',
              icon: Icons.psychology_rounded,
            ),
            SettingGroup(
              children: [
                ExpandableSettingTile(
                  title: '文本大模型 (Text LLM)',
                  subtitle: _getLlmSubtitle(settings, 'text'),
                  icon: Icons.text_fields_rounded,
                  expandedContent: _buildLlmConfigEditor(context, ref, 'text'),
                ),
                ExpandableSettingTile(
                  title: '视觉大模型 (Vision LLM)',
                  subtitle: _getLlmSubtitle(settings, 'vision'),
                  icon: Icons.image_search_rounded,
                  expandedContent: _buildLlmConfigEditor(
                    context,
                    ref,
                    'vision',
                  ),
                ),
              ],
            ),
          ],
        );
      },
      loading: () => const LoadingGroup(),
      error: (error, stackTrace) => const SizedBox.shrink(),
    );
  }

  String _maskKey(String key) {
    if (key.isEmpty) return '未配置';
    if (key.length <= 8) return '********';
    return '${key.substring(0, 4)}****${key.substring(key.length - 4)}';
  }

  bool _isEnvConfigured(String value) => value.startsWith('***');

  String _getLlmSubtitle(List<SystemSetting> settings, String type) {
    final prefix = type == 'text' ? 'text_llm' : 'vision_llm';
    final model =
        settings
                .firstWhere(
                  (s) => s.key == '${prefix}_model',
                  orElse: () => const SystemSetting(key: '', value: ''),
                )
                .value
            as String? ??
        '';
    final apiKey =
        settings
                .firstWhere(
                  (s) => s.key == '${prefix}_api_key',
                  orElse: () => const SystemSetting(key: '', value: ''),
                )
                .value
            as String? ??
        '';

    if (model.isEmpty && apiKey.isEmpty) return '未配置';
    final keyLabel = _isEnvConfigured(apiKey) ? '密钥已配置' : _maskKey(apiKey);
    if (model.isEmpty) return keyLabel;
    return '$model • $keyLabel';
  }

  Widget _buildLlmConfigEditor(
    BuildContext context,
    WidgetRef ref,
    String type,
  ) {
    // type: 'text' or 'vision'
    final settingsAsync = ref.watch(systemSettingsProvider);
    return settingsAsync.when(
      data: (settings) {
        final prefix = type == 'text' ? 'text_llm' : 'vision_llm';
        final baseUrl =
            settings
                    .firstWhere(
                      (s) => s.key == '${prefix}_api_base',
                      orElse: () => const SystemSetting(key: '', value: ''),
                    )
                    .value
                as String? ??
            '';
        final apiKey =
            settings
                    .firstWhere(
                      (s) => s.key == '${prefix}_api_key',
                      orElse: () => const SystemSetting(key: '', value: ''),
                    )
                    .value
                as String? ??
            '';
        final model =
            settings
                    .firstWhere(
                      (s) => s.key == '${prefix}_model',
                      orElse: () => const SystemSetting(key: '', value: ''),
                    )
                    .value
                as String? ??
            '';

        final isKeyFromEnv = _isEnvConfigured(apiKey);

        final baseController = TextEditingController(text: baseUrl);
        // 环境变量配置的密钥不填入编辑框，仅提示已配置
        final keyController = TextEditingController(
          text: isKeyFromEnv ? '' : apiKey,
        );
        final modelController = TextEditingController(text: model);

        return Column(
          children: [
            TextField(
              controller: baseController,
              decoration: InputDecoration(
                labelText: 'API Base URL',
                hintText: 'e.g. https://api.openai.com/v1',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: keyController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'API Key',
                hintText: isKeyFromEnv ? '已通过环境变量配置，输入新值可覆盖' : 'sk-...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: modelController,
              decoration: InputDecoration(
                labelText: 'Model Name',
                hintText: 'e.g. gpt-4o',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(
                onPressed: () async {
                  final notifier = ref.read(systemSettingsProvider.notifier);
                  await notifier.updateSetting(
                    '${prefix}_api_base',
                    baseController.text,
                    category: 'llm',
                  );
                  // 仅在用户实际输入了新密钥时才更新
                  if (keyController.text.isNotEmpty) {
                    await notifier.updateSetting(
                      '${prefix}_api_key',
                      keyController.text,
                      category: 'llm',
                    );
                  }
                  await notifier.updateSetting(
                    '${prefix}_model',
                    modelController.text,
                    category: 'llm',
                  );
                  if (context.mounted) showToast(context, 'LLM 配置已保存');
                },
                child: const Text('保存配置'),
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => const Text('加载失败'),
    );
  }
}
