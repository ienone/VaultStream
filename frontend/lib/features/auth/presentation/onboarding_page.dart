import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
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

  // 步骤0: 文字LLM
  final _llmBaseUrlController = TextEditingController(
    text: 'https://api.deepseek.com',
  );
  final _llmKeyController = TextEditingController();
  final _llmModelController = TextEditingController(text: 'deepseek-chat');

  // 步骤0: 视觉LLM（可选子区）
  bool _enableVisionLlm = false;
  final _visionBaseUrlController = TextEditingController();
  final _visionKeyController = TextEditingController();
  final _visionModelController = TextEditingController(text: 'qwen-vl-max');

  // 步骤1: Bot
  bool _enableBot = false;
  String _botPlatform = 'telegram';
  final _tgTokenController = TextEditingController();
  final _tgAdminIdController = TextEditingController();
  final _qqUrlController = TextEditingController(text: 'http://127.0.0.1:3000');

  // 步骤2/3/4: 平台Cookie
  final _weiboController = TextEditingController();
  final _xhsController = TextEditingController();
  final _zhihuController = TextEditingController();

  // 步骤5: 功能
  bool _enableAutoSummary = true;

  static const int _totalSteps = 6;

  @override
  void dispose() {
    _llmBaseUrlController.dispose();
    _llmKeyController.dispose();
    _llmModelController.dispose();
    _visionBaseUrlController.dispose();
    _visionKeyController.dispose();
    _visionModelController.dispose();
    _tgTokenController.dispose();
    _tgAdminIdController.dispose();
    _qqUrlController.dispose();
    _weiboController.dispose();
    _xhsController.dispose();
    _zhihuController.dispose();
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

      // 1. 文字LLM配置
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

      // 1b. 视觉模型配置（可选）
      if (_enableVisionLlm && _visionKeyController.text.trim().isNotEmpty) {
        if (_visionBaseUrlController.text.trim().isNotEmpty) {
          await dio.put(
            '/settings/vision_llm_api_base',
            data: {'value': _visionBaseUrlController.text.trim()},
          );
        }
        await dio.put(
          '/settings/vision_llm_api_key',
          data: {'value': _visionKeyController.text.trim()},
        );
        if (_visionModelController.text.trim().isNotEmpty) {
          await dio.put(
            '/settings/vision_llm_model',
            data: {'value': _visionModelController.text.trim()},
          );
        }
      }

      // 2. Bot配置
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

      // 3. Cookie配置（非空才保存）
      if (_weiboController.text.trim().isNotEmpty) {
        await dio.put(
          '/settings/weibo_cookie',
          data: {'value': _weiboController.text.trim()},
        );
      }
      if (_xhsController.text.trim().isNotEmpty) {
        await dio.put(
          '/settings/xiaohongshu_cookie',
          data: {'value': _xhsController.text.trim()},
        );
      }
      if (_zhihuController.text.trim().isNotEmpty) {
        await dio.put(
          '/settings/zhihu_cookie',
          data: {'value': _zhihuController.text.trim()},
        );
      }

      // 4. 功能配置
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

  /// 构建平台Cookie步骤的通用内容
  Widget _buildCookieStep({
    required String platform,
    required String url,
    required IconData icon,
    required TextEditingController controller,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('配置 $platform Cookie 后，可收藏需要登录才能访问的内容。此步骤可跳过，稍后在设置中填写。'),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () =>
              launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
          icon: Icon(icon, size: 18),
          label: Text('打开 $platform 网站'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: controller,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: '$platform Cookie',
            hintText: '从浏览器开发者工具 → Application → Cookies 中复制完整 Cookie 字符串',
            border: const OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  List<Step> _buildSteps(ColorScheme colorScheme) {
    return [
      // ── 步骤 0: AI 引擎 ──
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
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'API Key *',
                border: OutlineInputBorder(),
                suffixIcon: Icon(Icons.password),
              ),
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
            const SizedBox(height: 20),
            // Vision LLM 子区域
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('配置视觉模型 (Vision LLM)'),
                    subtitle: const Text('用于理解图片内容，支持 Qwen-VL 等多模态模型（可选）'),
                    secondary: const Icon(Icons.remove_red_eye_outlined),
                    value: _enableVisionLlm,
                    onChanged: (v) => setState(() => _enableVisionLlm = v),
                  ),
                  if (_enableVisionLlm) ...[
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          TextField(
                            controller: _visionBaseUrlController,
                            decoration: const InputDecoration(
                              labelText: 'Vision API Base URL',
                              hintText:
                                  'https://dashscope.aliyuncs.com/compatible-mode/v1',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _visionKeyController,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'Vision API Key',
                              border: OutlineInputBorder(),
                              suffixIcon: Icon(Icons.password),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _visionModelController,
                            decoration: const InputDecoration(
                              labelText: '视觉模型名称',
                              hintText: 'qwen-vl-max',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),

      // ── 步骤 1: Bot 设置 ──
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
              onChanged: (v) => setState(() => _enableBot = v),
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
                onSelectionChanged: (s) =>
                    setState(() => _botPlatform = s.first),
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

      // ── 步骤 2: 微博 ──
      Step(
        title: const Text('微博 Cookie'),
        subtitle: const Text('可跳过'),
        isActive: _currentStep >= 2,
        state: _currentStep > 2 ? StepState.complete : StepState.indexed,
        content: _buildCookieStep(
          platform: '微博',
          url: 'https://weibo.com',
          icon: Icons.share_rounded,
          controller: _weiboController,
        ),
      ),

      // ── 步骤 3: 小红书 ──
      Step(
        title: const Text('小红书 Cookie'),
        subtitle: const Text('可跳过'),
        isActive: _currentStep >= 3,
        state: _currentStep > 3 ? StepState.complete : StepState.indexed,
        content: _buildCookieStep(
          platform: '小红书',
          url: 'https://www.xiaohongshu.com',
          icon: Icons.explore_rounded,
          controller: _xhsController,
        ),
      ),

      // ── 步骤 4: 知乎 ──
      Step(
        title: const Text('知乎 Cookie'),
        subtitle: const Text('可跳过'),
        isActive: _currentStep >= 4,
        state: _currentStep > 4 ? StepState.complete : StepState.indexed,
        content: _buildCookieStep(
          platform: '知乎',
          url: 'https://www.zhihu.com',
          icon: Icons.question_answer_rounded,
          controller: _zhihuController,
        ),
      ),

      // ── 步骤 5: 智能摘要 ──
      Step(
        title: const Text('AI 智能摘要'),
        isActive: _currentStep >= 5,
        state: _currentStep == 5 ? StepState.editing : StepState.indexed,
        content: Column(
          children: [
            SwitchListTile(
              title: const Text('启用 AI 自动摘要'),
              subtitle: const Text(
                '收藏时自动使用 AI 读取并生成结构化摘要。\n仅适用于文章、知乎回答等长文内容，推文等简短内容不触发。',
              ),
              value: _enableAutoSummary,
              onChanged: (v) => setState(() => _enableAutoSummary = v),
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
    final colorScheme = Theme.of(context).colorScheme;
    // 步骤2/3/4 可跳过
    final bool isSkippable = _currentStep >= 2 && _currentStep <= 4;
    final bool isLastStep = _currentStep == _totalSteps - 1;

    return Scaffold(
      appBar: AppBar(title: const Text('初始化向导')),
      body: SafeArea(
        child: Stepper(
          type: StepperType.vertical,
          currentStep: _currentStep,
          onStepTapped: (i) => setState(() => _currentStep = i),
          onStepContinue: () {
            if (_currentStep < _totalSteps - 1) {
              setState(() => _currentStep += 1);
            } else {
              _handleComplete();
            }
          },
          onStepCancel: () {
            if (_currentStep > 0) setState(() => _currentStep -= 1);
          },
          controlsBuilder: (context, details) {
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
                        : Icon(isLastStep ? Icons.check : Icons.arrow_forward),
                    label: Text(isLastStep ? '完成' : '下一步'),
                  ),
                  if (_currentStep > 0) ...[
                    const SizedBox(width: 12),
                    OutlinedButton(
                      onPressed: _isLoading ? null : details.onStepCancel,
                      child: const Text('上一步'),
                    ),
                  ],
                  // 步骤2/3/4 提供跳过按钮
                  if (isSkippable) ...[
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: _isLoading
                          ? null
                          : () => setState(() => _currentStep += 1),
                      child: const Text('跳过'),
                    ),
                  ],
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
