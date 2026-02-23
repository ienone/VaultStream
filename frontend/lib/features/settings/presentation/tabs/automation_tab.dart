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
        const SectionHeader(title: 'AI 发现与分析'),
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
        final enableAi = settings.firstWhere(
              (s) => s.key == 'enable_ai_discovery',
              orElse: () => const SystemSetting(key: '', value: false),
            ).value as bool? ?? false;

        final enableAutoSummary = settings.firstWhere(
              (s) => s.key == 'enable_auto_summary',
              orElse: () => const SystemSetting(key: '', value: false),
            ).value as bool? ?? false;
            
        final prompt = settings.firstWhere(
              (s) => s.key == 'universal_adapter_prompt',
              orElse: () => const SystemSetting(key: '', value: ''),
            ).value as String? ?? '';
            
        final topics = settings.firstWhere(
              (s) => s.key == 'discovery_topics',
              orElse: () => const SystemSetting(key: '', value: []),
            ).value;

        List<String> topicList = [];
        if (topics is List) {
          topicList = topics.map((e) => e.toString()).toList();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingGroup(
              children: [
                SettingTile(
                  title: '启用 AI 自动发现',
                  subtitle: '根据订阅主题自动抓取相关内容',
                  icon: Icons.auto_awesome_rounded,
                  trailing: Switch(
                    value: enableAi,
                    thumbIcon: WidgetStateProperty.resolveWith<Icon?>((states) {
                      if (states.contains(WidgetState.selected)) {
                        return const Icon(Icons.check);
                      }
                      return null;
                    }),
                    onChanged: (val) => ref
                        .read(systemSettingsProvider.notifier)
                        .updateSetting('enable_ai_discovery', val, category: 'ai'),
                  ),
                  onTap: () => ref
                      .read(systemSettingsProvider.notifier)
                      .updateSetting('enable_ai_discovery', !enableAi, category: 'ai'),
                ),
                SettingTile(
                  title: '启用 AI 自动生成摘要',
                  subtitle: '解析完成后自动调用大模型生成摘要',
                  icon: Icons.summarize_rounded,
                  trailing: Switch(
                    value: enableAutoSummary,
                    onChanged: (val) => ref
                        .read(systemSettingsProvider.notifier)
                        .updateSetting('enable_auto_summary', val, category: 'llm'),
                  ),
                  onTap: () => ref
                      .read(systemSettingsProvider.notifier)
                      .updateSetting('enable_auto_summary', !enableAutoSummary, category: 'llm'),
                ),
                ExpandableSettingTile(
                  title: '订阅主题管理',
                  subtitle: '${topicList.length} 个关注主题',
                  icon: Icons.topic_rounded,
                  expandedContent: _buildTopicsEditor(context, ref, topicList),
                ),
                ExpandableSettingTile(
                  title: '通用解析 Prompt',
                  subtitle: '自定义 LLM 解析指令',
                  icon: Icons.psychology_rounded,
                  expandedContent: _buildPromptEditor(context, ref, prompt),
                ),
              ],
            ),
            const SizedBox(height: 32),
            const SectionHeader(title: '大模型引擎 (LLM)'),
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
                  expandedContent: _buildLlmConfigEditor(context, ref, 'vision'),
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
    final model = settings.firstWhere((s) => s.key == '${prefix}_model', orElse: () => const SystemSetting(key: '', value: '')).value as String? ?? '';
    final apiKey = settings.firstWhere((s) => s.key == '${prefix}_api_key', orElse: () => const SystemSetting(key: '', value: '')).value as String? ?? '';
    
    if (model.isEmpty && apiKey.isEmpty) return '未配置';
    final keyLabel = _isEnvConfigured(apiKey) ? '密钥已配置' : _maskKey(apiKey);
    if (model.isEmpty) return keyLabel;
    return '$model • $keyLabel';
  }

  Widget _buildLlmConfigEditor(BuildContext context, WidgetRef ref, String type) {
    // type: 'text' or 'vision'
    final settingsAsync = ref.watch(systemSettingsProvider);
    return settingsAsync.when(
      data: (settings) {
        final prefix = type == 'text' ? 'text_llm' : 'vision_llm';
        final baseUrl = settings.firstWhere((s) => s.key == '${prefix}_api_base', orElse: () => const SystemSetting(key: '', value: '')).value as String? ?? '';
        final apiKey = settings.firstWhere((s) => s.key == '${prefix}_api_key', orElse: () => const SystemSetting(key: '', value: '')).value as String? ?? '';
        final model = settings.firstWhere((s) => s.key == '${prefix}_model', orElse: () => const SystemSetting(key: '', value: '')).value as String? ?? '';

        final isKeyFromEnv = _isEnvConfigured(apiKey);

        final baseController = TextEditingController(text: baseUrl);
        // 环境变量配置的密钥不填入编辑框，仅提示已配置
        final keyController = TextEditingController(text: isKeyFromEnv ? '' : apiKey);
        final modelController = TextEditingController(text: model);

        return Column(
          children: [
            TextField(
              controller: baseController,
              decoration: InputDecoration(
                labelText: 'API Base URL',
                hintText: 'e.g. https://api.openai.com/v1',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: keyController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'API Key',
                hintText: isKeyFromEnv ? '已通过环境变量配置，输入新值可覆盖' : 'sk-...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: modelController,
              decoration: InputDecoration(
                labelText: 'Model Name',
                hintText: 'e.g. gpt-4o',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(
                onPressed: () async {
                  final notifier = ref.read(systemSettingsProvider.notifier);
                  await notifier.updateSetting('${prefix}_api_base', baseController.text, category: 'llm');
                  // 仅在用户实际输入了新密钥时才更新
                  if (keyController.text.isNotEmpty) {
                    await notifier.updateSetting('${prefix}_api_key', keyController.text, category: 'llm');
                  }
                  await notifier.updateSetting('${prefix}_model', modelController.text, category: 'llm');
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

  Widget _buildTopicsEditor(BuildContext context, WidgetRef ref, List<String> currentTopics) {
    final controller = TextEditingController();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: currentTopics.map((t) => Chip(
            label: Text(t),
            onDeleted: () {
              final newTopics = List<String>.from(currentTopics)..remove(t);
              ref.read(systemSettingsProvider.notifier).updateSetting('discovery_topics', newTopics, category: 'ai');
            },
          )).toList(),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: '添加新主题...',
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onSubmitted: (val) {
                  if (val.trim().isNotEmpty && !currentTopics.contains(val.trim())) {
                    final newTopics = List<String>.from(currentTopics)..add(val.trim());
                    ref.read(systemSettingsProvider.notifier).updateSetting('discovery_topics', newTopics, category: 'ai');
                    controller.clear();
                  }
                },
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_rounded),
              onPressed: () {
                if (controller.text.trim().isNotEmpty && !currentTopics.contains(controller.text.trim())) {
                  final newTopics = List<String>.from(currentTopics)..add(controller.text.trim());
                  ref.read(systemSettingsProvider.notifier).updateSetting('discovery_topics', newTopics, category: 'ai');
                  controller.clear();
                }
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPromptEditor(BuildContext context, WidgetRef ref, String currentPrompt) {
    final controller = TextEditingController(text: currentPrompt);
    return Column(
      children: [
        TextField(
          controller: controller,
          maxLines: 8,
          decoration: InputDecoration(
            hintText: 'Enter LLM Prompt...',
            filled: true,
            fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.tonal(
            onPressed: () async {
              await ref.read(systemSettingsProvider.notifier).updateSetting('universal_adapter_prompt', controller.text, category: 'ai');
              if (context.mounted) {
                showToast(context, 'Prompt 已更新');
              }
            },
            child: const Text('保存配置'),
          ),
        ),
      ],
    );
  }
}
