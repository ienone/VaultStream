import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/providers/system_status_provider.dart';
import '../../settings/presentation/widgets/setting_components.dart'
    as settings_ui;

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  int _currentStep = 0;
  bool _isLoading = false;
  String? _error;

  // Step 1: AI Engine
  final _llmBaseUrlController = TextEditingController(
    text: 'https://api.deepseek.com',
  );
  final _llmKeyController = TextEditingController();
  final _llmModelController = TextEditingController(text: 'deepseek-chat');

  // Step 2: Bot Setup
  bool _enableBot = false;
  String _botPlatform = 'telegram';
  final _tgTokenController = TextEditingController();
  final _tgAdminIdController = TextEditingController();
  final _qqUrlController = TextEditingController(text: 'http://127.0.0.1:3000');

  // Step 3: Features
  bool _enableAutoSummary = true;

  @override
  void dispose() {
    _llmBaseUrlController.dispose();
    _llmKeyController.dispose();
    _llmModelController.dispose();
    _tgTokenController.dispose();
    _tgAdminIdController.dispose();
    _qqUrlController.dispose();
    super.dispose();
  }

  Future<void> _handleComplete() async {
    if (_llmKeyController.text.trim().isEmpty) {
      setState(() {
        _currentStep = 0;
        _error = '请输入 AI 的 API Key';
      });
      return;
    }

    if (_enableBot) {
      if (_botPlatform == 'telegram' &&
          _tgTokenController.text.trim().isEmpty) {
        setState(() {
          _currentStep = 1;
          _error = '启用 Telegram 推送时，必须输入 Bot Token';
        });
        return;
      }
      if (_botPlatform == 'qq' && _qqUrlController.text.trim().isEmpty) {
        setState(() {
          _currentStep = 1;
          _error = '启用 QQ推送 时，必须输入 Napcat API 地址';
        });
        return;
      }
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final dio = ref.read(apiClientProvider);

      // 1. 保存 AI 引擎配置 (使用正确的 /settings/{key} 路径)
      await dio.put(
        '/settings/text_llm_api_base',
        data: {'value': _llmBaseUrlController.text.trim()},
      );
      await dio.put(
        '/settings/text_llm_api_key',
        data: {'value': _llmKeyController.text.trim()},
      );
      if (_llmModelController.text.trim().isNotEmpty) {
        await dio.put(
          '/settings/text_llm_model',
          data: {'value': _llmModelController.text.trim()},
        );
      }

      // 2. 保存 Bot 配置
      if (_enableBot) {
        if (_botPlatform == 'telegram') {
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
          if (_tgAdminIdController.text.isNotEmpty) {
            await dio.put(
              '/settings/telegram_admin_ids',
              data: {'value': _tgAdminIdController.text.trim()},
            );
          }
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

      // 3. 保存特性配置
      await dio.put(
        '/settings/enable_auto_summary',
        data: {'value': _enableAutoSummary.toString()},
      );

      if (mounted) {
        settings_ui.showToast(context, '配置完成！');
        ref.read(systemStatusProvider.notifier).refresh();
      }
    } catch (e) {
      setState(() {
        _error = '保存失败: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  List<Step> _buildSteps(ColorScheme colorScheme) {
    return [
      Step(
        title: const Text('AI 引擎配置'),
        subtitle: const Text('必填'),
        isActive: _currentStep >= 0,
        state: _currentStep > 0 ? StepState.complete : StepState.indexed,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('AI 引擎用于自动清洗网页、提取正文并生成摘要。推荐使用 DeepSeek。'),
            const SizedBox(height: 16),
            TextField(
              controller: _llmBaseUrlController,
              decoration: const InputDecoration(
                labelText: 'API Base URL',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _llmKeyController,
              decoration: const InputDecoration(
                labelText: 'API Key',
                border: OutlineInputBorder(),
                suffixIcon: Icon(Icons.password),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _llmModelController,
              decoration: const InputDecoration(
                labelText: '模型名称 (Model)',
                hintText: 'deepseek-chat',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      Step(
        title: const Text('通知机器人设置'),
        subtitle: const Text('可选'),
        isActive: _currentStep >= 1,
        state: _currentStep > 1 ? StepState.complete : StepState.indexed,
        content: Column(
          children: [
            SwitchListTile(
              title: const Text('启用推送机器人'),
              subtitle: const Text('开启后可以通过 Telegram 或 QQ 接收并管理收藏。'),
              value: _enableBot,
              onChanged: (val) => setState(() => _enableBot = val),
            ),
            if (_enableBot) ...[
              const Divider(),
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
                onSelectionChanged: (set) =>
                    setState(() => _botPlatform = set.first),
              ),
              const SizedBox(height: 16),
              if (_botPlatform == 'telegram') ...[
                TextField(
                  controller: _tgTokenController,
                  decoration: const InputDecoration(
                    labelText: 'Bot Token',
                    hintText: '12345678:ABC...',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _tgAdminIdController,
                  decoration: const InputDecoration(
                    labelText: '管理员 ID (您的 TG 用户 ID)',
                    hintText: 'e.g. 12345678',
                    border: OutlineInputBorder(),
                  ),
                ),
              ] else ...[
                TextField(
                  controller: _qqUrlController,
                  decoration: const InputDecoration(
                    labelText: 'Napcat API 地址',
                    hintText: 'http://127.0.0.1:3000',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
      Step(
        title: const Text('增强功能体验'),
        isActive: _currentStep >= 2,
        state: _currentStep == 2 ? StepState.editing : StepState.indexed,
        content: Column(
          children: [
            SwitchListTile(
              title: const Text('智能内容摘要'),
              subtitle: const Text('收藏时自动使用 AI 读取图文并生成结构化摘要。'),
              value: _enableAutoSummary,
              onChanged: (val) => setState(() => _enableAutoSummary = val),
              secondary: const Icon(Icons.auto_awesome),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.error, color: colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(color: colorScheme.error),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('初始化向导')),
      body: SafeArea(
        child: Stepper(
          type: StepperType.vertical,
          currentStep: _currentStep,
          onStepTapped: (index) {
            setState(() => _currentStep = index);
          },
          onStepContinue: () {
            if (_currentStep < 2) {
              setState(() => _currentStep += 1);
            } else {
              _handleComplete();
            }
          },
          onStepCancel: () {
            if (_currentStep > 0) {
              setState(() => _currentStep -= 1);
            }
          },
          controlsBuilder: (context, details) {
            final isLastStep = _currentStep == 2;
            return Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Row(
                children: [
                  FilledButton.icon(
                    onPressed: _isLoading ? null : details.onStepContinue,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : (isLastStep
                              ? const Icon(Icons.check)
                              : const Icon(Icons.arrow_forward)),
                    label: Text(isLastStep ? '完成' : '下一步'),
                  ),
                  const SizedBox(width: 12),
                  if (_currentStep > 0)
                    OutlinedButton(
                      onPressed: _isLoading ? null : details.onStepCancel,
                      child: const Text('上一步'),
                    ),
                ],
              ),
            );
          },
          steps: _buildSteps(colorScheme),
        ),
      ),
    );
  }
}
