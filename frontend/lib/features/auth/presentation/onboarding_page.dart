import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/system_status_provider.dart';
import '../../../core/layout/responsive_layout.dart';
import '../../../core/utils/safe_url_launcher.dart';
import '../../../theme/design_tokens.dart';
import '../../automation/providers/bot_chats_provider.dart';
import '../../settings/providers/bot_config_actions.dart';
import '../../settings/providers/settings_provider.dart';
import '../../settings/presentation/widgets/setting_components.dart'
    as settings_ui;
import 'widgets/interactive_login_dialog.dart';

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  int _currentStep = 0;
  bool _isLoading = false;
  String? _error;
  final _scrollController = ScrollController();
  final _textFeatureKey = GlobalKey();
  final _summaryFeatureKey = GlobalKey();
  final _embeddingFeatureKey = GlobalKey();
  final _visionFeatureKey = GlobalKey();
  final _telegramKey = GlobalKey();
  final _qqKey = GlobalKey();
  final _accountsKey = GlobalKey();
  bool _enableTextLlm = false;
  bool _enableAutoSummary = false;
  bool _enableEmbedding = false;
  bool _enableVisionLlm = false;
  final _llmBaseUrlController = TextEditingController(
    text: 'https://api.deepseek.com',
  );
  final _llmKeyController = TextEditingController();
  final _llmModelController = TextEditingController(text: 'deepseek-chat');
  final _summaryKeyController = TextEditingController();
  final _summaryModelController = TextEditingController(
    text: 'gemini-2.5-flash',
  );
  final _embeddingKeyController = TextEditingController();
  final _embeddingModelController = TextEditingController(
    text: 'gemini-embedding-2',
  );
  final _embeddingDimController = TextEditingController(text: '1536');
  final _visionBaseUrlController = TextEditingController();
  final _visionKeyController = TextEditingController();
  final _visionModelController = TextEditingController(text: 'qwen-vl-max');
  List<String> _textModels = const [];
  List<String> _visionModels = const [];

  bool _enableTelegramBot = false;
  bool _enableQqBot = false;
  final _tgTokenController = TextEditingController();
  final _tgAdminIdController = TextEditingController();
  final _qqUrlController = TextEditingController(text: 'http://127.0.0.1:3000');
  final _qqAdminIdController = TextEditingController();

  final _weiboController = TextEditingController();
  final _xhsController = TextEditingController();
  final _zhihuController = TextEditingController();
  bool _weiboIsConnected = false;
  bool _xhsIsConnected = false;
  bool _zhihuIsConnected = false;

  static const int _totalSteps = 4;
  static const int _botStep = 1;
  static const int _accountStep = 2;
  static const int _finishStep = 3;

  @override
  void dispose() {
    for (final controller in [
      _llmBaseUrlController,
      _llmKeyController,
      _llmModelController,
      _summaryKeyController,
      _summaryModelController,
      _embeddingKeyController,
      _embeddingModelController,
      _embeddingDimController,
      _visionBaseUrlController,
      _visionKeyController,
      _visionModelController,
      _tgTokenController,
      _tgAdminIdController,
      _qqUrlController,
      _qqAdminIdController,
      _weiboController,
      _xhsController,
      _zhihuController,
    ]) {
      controller.dispose();
    }
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _put(String key, Object value) =>
      ref.read(systemSettingsProvider.notifier).updateSetting(key, value);

  Future<void> _saveProvider(String target) async {
    final isText = target == 'text_llm';
    final base = isText
        ? _llmBaseUrlController.text.trim()
        : _visionBaseUrlController.text.trim();
    final key = isText
        ? _llmKeyController.text.trim()
        : _visionKeyController.text.trim();
    final model = isText
        ? _llmModelController.text.trim()
        : _visionModelController.text.trim();
    if (base.isEmpty || key.isEmpty) {
      throw StateError('请先填写 API Base URL 和 API Key');
    }
    await _put('${target}_api_base', base);
    await _put('${target}_api_key', key);
    if (model.isNotEmpty) await _put('${target}_model', model);
  }

  Future<void> _discoverModels(String target) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await _saveProvider(target);
      final models = await ref
          .read(aiModelDiscoveryActionsProvider)
          .discover(target);
      if (!mounted) return;
      setState(() {
        if (target == 'text_llm') {
          _textModels = models;
        } else {
          _visionModels = models;
        }
      });
      settings_ui.showToast(context, '已发现 ${models.length} 个可用模型');
    } catch (e) {
      if (mounted) setState(() => _error = '模型探测失败：$e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleComplete() async {
    if (_enableTextLlm &&
        (_llmKeyController.text.trim().isEmpty ||
            _llmBaseUrlController.text.trim().isEmpty)) {
      setState(() {
        _currentStep = 0;
        _error = '请填写内容理解的 API 地址和密钥';
      });
      return;
    }
    if (_enableAutoSummary && _summaryKeyController.text.trim().isEmpty) {
      setState(() {
        _currentStep = 0;
        _error = '请填写自动摘要的 API Key';
      });
      return;
    }
    if (_enableEmbedding && _embeddingKeyController.text.trim().isEmpty) {
      setState(() {
        _currentStep = 0;
        _error = '请填写语义搜索的 API Key';
      });
      return;
    }
    if (_enableVisionLlm &&
        (_visionKeyController.text.trim().isEmpty ||
            _visionBaseUrlController.text.trim().isEmpty)) {
      setState(() {
        _currentStep = 0;
        _error = '请填写图像理解的 API 地址和密钥';
      });
      return;
    }
    if (_enableTelegramBot && _tgTokenController.text.trim().isEmpty) {
      setState(() {
        _currentStep = _botStep;
        _error = '请填写 Telegram Bot Token';
      });
      return;
    }
    if (_enableQqBot && _qqUrlController.text.trim().isEmpty) {
      setState(() {
        _currentStep = _botStep;
        _error = '请填写 Napcat API 地址';
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      if (_enableTextLlm) await _saveProvider('text_llm');
      await _put('enable_auto_summary', _enableAutoSummary.toString());
      if (_enableAutoSummary) {
        await _put('summary_api_key', _summaryKeyController.text.trim());
        await _put('summary_model', _summaryModelController.text.trim());
      }
      if (_enableEmbedding) {
        await _put('embedding_api_key', _embeddingKeyController.text.trim());
        await _put('embedding_model', _embeddingModelController.text.trim());
        final dimension = int.tryParse(_embeddingDimController.text.trim());
        if (dimension != null) {
          await _put('embedding_output_dimensionality', dimension);
        }
      }
      if (_enableVisionLlm) await _saveProvider('vision_llm');
      if (_enableTelegramBot || _enableQqBot) await _saveBots();
      await _saveAccounts();
      await _put('onboarding_completed', 'true');
      if (!mounted) return;
      settings_ui.showToast(context, '配置完成！可随时在设置中修改。');
      ref.read(systemStatusProvider.notifier).refresh();
      ref.invalidate(botChatsProvider);
    } catch (e) {
      if (mounted) setState(() => _error = '保存失败：$e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveBots() async {
    if (_enableTelegramBot) {
      await ref
          .read(botConfigActionsProvider)
          .saveCredentials(
            platform: 'telegram',
            telegramToken: _tgTokenController.text,
            napcatHttpUrl: '',
          );
      if (_tgAdminIdController.text.trim().isNotEmpty) {
        await _put('telegram_admin_ids', _tgAdminIdController.text.trim());
      }
    }
    if (_enableQqBot) {
      await ref
          .read(botConfigActionsProvider)
          .saveCredentials(
            platform: 'qq',
            telegramToken: '',
            napcatHttpUrl: _qqUrlController.text,
          );
      if (_qqAdminIdController.text.trim().isNotEmpty) {
        await _put('qq_admin_ids', _qqAdminIdController.text.trim());
      }
    }
  }

  Future<void> _saveAccounts() async {
    if (_weiboController.text.trim().isNotEmpty) {
      await _put('weibo_cookie', _weiboController.text.trim());
    }
    if (_xhsController.text.trim().isNotEmpty) {
      await _put('xiaohongshu_cookie', _xhsController.text.trim());
    }
    if (_zhihuController.text.trim().isNotEmpty) {
      await _put('zhihu_cookie', _zhihuController.text.trim());
    }
  }

  Future<void> _showLoginDialog(String platform, String label) async {
    final connected = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          InteractiveLoginDialog(platform: platform, platformLabel: label),
    );
    if (connected == true && mounted) {
      setState(() {
        if (platform == 'weibo') _weiboIsConnected = true;
        if (platform == 'xiaohongshu') _xhsIsConnected = true;
        if (platform == 'zhihu') _zhihuIsConnected = true;
      });
    }
  }

  Widget _providerFields({
    required String target,
    required TextEditingController base,
    required TextEditingController key,
    required TextEditingController model,
    required List<String> models,
  }) {
    return Column(
      children: [
        TextField(
          controller: base,
          decoration: const InputDecoration(
            labelText: 'API Base URL',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: key,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'API Key',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        if (models.isEmpty)
          TextField(
            controller: model,
            decoration: const InputDecoration(
              labelText: '模型',
              border: OutlineInputBorder(),
            ),
          )
        else
          DropdownButtonFormField<String>(
            initialValue: models.contains(model.text) ? model.text : null,
            decoration: const InputDecoration(
              labelText: '模型',
              border: OutlineInputBorder(),
            ),
            items: models
                .map((item) => DropdownMenuItem(value: item, child: Text(item)))
                .toList(),
            onChanged: (value) => model.text = value ?? model.text,
          ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: _isLoading ? null : () => _discoverModels(target),
            icon: const Icon(Icons.travel_explore),
            label: const Text('探测模型'),
          ),
        ),
      ],
    );
  }

  Widget _featureCard({
    required GlobalKey cardKey,
    required String title,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
    required Widget configuration,
  }) {
    return Card(
      key: cardKey,
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SwitchListTile(
            secondary: Icon(icon),
            title: Text(title),
            value: value,
            onChanged: onChanged,
          ),
          AnimatedSize(
            duration: AppMotion.contentSwap,
            curve: AppMotion.standardCurve,
            child: value
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: configuration,
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _responsiveCardWrap({
    required List<Widget> children,
    required int maxColumns,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final widthClass = ResponsiveLayout.widthClassFor(constraints.maxWidth);
        final columns =
            maxColumns >= 3 && widthClass.atLeast(WindowWidthClass.expanded)
            ? 3
            : maxColumns >= 2 && widthClass.atLeast(WindowWidthClass.medium)
            ? 2
            : 1;
        const spacing = 12.0;
        final itemWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return AnimatedSize(
          duration: AppMotion.contentSwap,
          curve: AppMotion.standardCurve,
          alignment: Alignment.topCenter,
          child: Wrap(
            spacing: spacing,
            runSpacing: spacing,
            crossAxisAlignment: WrapCrossAlignment.start,
            children: children
                .map(
                  (child) => AnimatedContainer(
                    duration: AppMotion.contentSwap,
                    curve: AppMotion.standardCurve,
                    width: itemWidth,
                    child: child,
                  ),
                )
                .toList(),
          ),
        );
      },
    );
  }

  Widget _featureStep() {
    final cards = [
      _featureCard(
        cardKey: _textFeatureKey,
        title: '内容理解',
        icon: Icons.text_snippet_outlined,
        value: _enableTextLlm,
        onChanged: (value) => setState(() => _enableTextLlm = value),
        configuration: _providerFields(
          target: 'text_llm',
          base: _llmBaseUrlController,
          key: _llmKeyController,
          model: _llmModelController,
          models: _textModels,
        ),
      ),
      _featureCard(
        cardKey: _summaryFeatureKey,
        title: '自动摘要',
        icon: Icons.auto_awesome_outlined,
        value: _enableAutoSummary,
        onChanged: (value) => setState(() => _enableAutoSummary = value),
        configuration: Column(
          children: [
            TextField(
              controller: _summaryKeyController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Gemini API Key',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _summaryModelController,
              decoration: const InputDecoration(
                labelText: '模型',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      _featureCard(
        cardKey: _embeddingFeatureKey,
        title: '语义搜索',
        icon: Icons.manage_search_outlined,
        value: _enableEmbedding,
        onChanged: (value) => setState(() => _enableEmbedding = value),
        configuration: Column(
          children: [
            TextField(
              controller: _embeddingKeyController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Embedding API Key',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _embeddingModelController,
                    decoration: const InputDecoration(
                      labelText: '模型',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _embeddingDimController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '维度',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      _featureCard(
        cardKey: _visionFeatureKey,
        title: '图像理解',
        icon: Icons.image_search_outlined,
        value: _enableVisionLlm,
        onChanged: (value) => setState(() => _enableVisionLlm = value),
        configuration: _providerFields(
          target: 'vision_llm',
          base: _visionBaseUrlController,
          key: _visionKeyController,
          model: _visionModelController,
          models: _visionModels,
        ),
      ),
    ];
    return _responsiveCardWrap(
      children: [cards[0], cards[3], cards[1], cards[2]],
      maxColumns: 2,
    );
  }

  Widget _botConfigCard({required bool telegram}) {
    final enabled = telegram ? _enableTelegramBot : _enableQqBot;
    return Card(
      key: telegram ? _telegramKey : _qqKey,
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SwitchListTile(
            secondary: Icon(
              telegram ? Icons.send_outlined : Icons.chat_outlined,
            ),
            title: Text(telegram ? 'Telegram' : 'QQ'),
            value: enabled,
            onChanged: (value) => setState(() {
              if (telegram) {
                _enableTelegramBot = value;
              } else {
                _enableQqBot = value;
              }
            }),
          ),
          if (enabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  TextField(
                    controller: telegram
                        ? _tgTokenController
                        : _qqUrlController,
                    decoration: InputDecoration(
                      labelText: telegram ? 'Bot Token' : 'Napcat API 地址',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: telegram
                        ? _tgAdminIdController
                        : _qqAdminIdController,
                    decoration: InputDecoration(
                      labelText: telegram ? '管理员 ID（可选）' : '管理员 QQ 号（可选）',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _botStepContent() {
    return _responsiveCardWrap(
      children: [
        _botConfigCard(telegram: true),
        _botConfigCard(telegram: false),
      ],
      maxColumns: 2,
    );
  }

  Widget _accountCard(
    String label,
    String id,
    bool connected,
    TextEditingController controller,
    String url,
  ) {
    return Card.outlined(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            leading: Icon(
              connected ? Icons.check_circle : Icons.account_circle_outlined,
              color: connected ? Theme.of(context).colorScheme.primary : null,
            ),
            title: Text(label),
            subtitle: Text(connected ? '已连接' : '未连接'),
            trailing: connected
                ? null
                : FilledButton.tonalIcon(
                    onPressed: () => _showLoginDialog(id, label),
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('扫码连接'),
                  ),
          ),
          ExpansionTile(
            shape: const Border(),
            collapsedShape: const Border(),
            title: const Text('手动 Cookie'),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              TextField(
                controller: controller,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Cookie',
                  border: OutlineInputBorder(),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => SafeUrlLauncher.openExternal(context, url),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('浏览器打开'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _accountStepContent() {
    return KeyedSubtree(
      key: _accountsKey,
      child: _responsiveCardWrap(
        children: [
          _accountCard(
            '微博',
            'weibo',
            _weiboIsConnected,
            _weiboController,
            'https://weibo.com',
          ),
          _accountCard(
            '小红书',
            'xiaohongshu',
            _xhsIsConnected,
            _xhsController,
            'https://www.xiaohongshu.com',
          ),
          _accountCard(
            '知乎',
            'zhihu',
            _zhihuIsConnected,
            _zhihuController,
            'https://www.zhihu.com',
          ),
        ],
        maxColumns: 3,
      ),
    );
  }

  void _jumpToConfiguration(int step, GlobalKey key) {
    setState(() => _currentStep = step);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final targetContext = key.currentContext;
      if (targetContext == null) return;
      Scrollable.ensureVisible(
        targetContext,
        duration: AppMotion.surfaceEnter,
        curve: AppMotion.standardCurve,
        alignment: 0.08,
      );
    });
  }

  Widget _reviewCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: AppShape.cardMediaBorder,
                ),
                child: Icon(icon),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(subtitle),
                  ],
                ),
              ),
              const Icon(Icons.edit_outlined),
            ],
          ),
        ),
      ),
    );
  }

  Widget _finishStepContent() {
    final hasConfiguredAccounts =
        _weiboIsConnected ||
        _xhsIsConnected ||
        _zhihuIsConnected ||
        _weiboController.text.trim().isNotEmpty ||
        _xhsController.text.trim().isNotEmpty ||
        _zhihuController.text.trim().isNotEmpty;
    final cards = <Widget>[
      if (_enableTextLlm)
        _reviewCard(
          title: '内容理解',
          subtitle: _llmModelController.text.trim(),
          icon: Icons.text_snippet_outlined,
          onTap: () => _jumpToConfiguration(0, _textFeatureKey),
        ),
      if (_enableAutoSummary)
        _reviewCard(
          title: '自动摘要',
          subtitle: _summaryModelController.text.trim(),
          icon: Icons.auto_awesome_outlined,
          onTap: () => _jumpToConfiguration(0, _summaryFeatureKey),
        ),
      if (_enableEmbedding)
        _reviewCard(
          title: '语义搜索',
          subtitle: _embeddingModelController.text.trim(),
          icon: Icons.manage_search_outlined,
          onTap: () => _jumpToConfiguration(0, _embeddingFeatureKey),
        ),
      if (_enableVisionLlm)
        _reviewCard(
          title: '图像理解',
          subtitle: _visionModelController.text.trim(),
          icon: Icons.image_search_outlined,
          onTap: () => _jumpToConfiguration(0, _visionFeatureKey),
        ),
      if (_enableTelegramBot)
        _reviewCard(
          title: 'Telegram',
          subtitle: '推送已启用',
          icon: Icons.send_outlined,
          onTap: () => _jumpToConfiguration(_botStep, _telegramKey),
        ),
      if (_enableQqBot)
        _reviewCard(
          title: 'QQ',
          subtitle: '推送已启用',
          icon: Icons.chat_outlined,
          onTap: () => _jumpToConfiguration(_botStep, _qqKey),
        ),
      if (hasConfiguredAccounts)
        _reviewCard(
          title: '平台账户',
          subtitle: '检查登录状态',
          icon: Icons.account_circle_outlined,
          onTap: () => _jumpToConfiguration(_accountStep, _accountsKey),
        ),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          Text('确认配置', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 6),
          Text(
            cards.isEmpty ? '没有需要确认的可选配置' : '点击卡片可返回修改',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (cards.isNotEmpty) ...[
            const SizedBox(height: 32),
            _responsiveCardWrap(children: cards, maxColumns: 3),
          ],
        ],
      ),
    );
  }

  Widget _currentStepContent() {
    return switch (_currentStep) {
      0 => _featureStep(),
      _botStep => _botStepContent(),
      _accountStep => _accountStepContent(),
      _ => _finishStepContent(),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('初始化向导')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 720;
            return Column(
              children: [
                _OnboardingProgress(
                  currentStep: _currentStep,
                  onStepTapped: (step) => setState(() => _currentStep = step),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: EdgeInsets.fromLTRB(
                      wide ? 32 : 16,
                      24,
                      wide ? 32 : 16,
                      32,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1180),
                        child: _currentStepContent(),
                      ),
                    ),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                _OnboardingNavigation(
                  currentStep: _currentStep,
                  totalSteps: _totalSteps,
                  isLoading: _isLoading,
                  onBack: _currentStep == 0
                      ? null
                      : () => setState(() => _currentStep -= 1),
                  onNext: () {
                    if (_currentStep < _finishStep) {
                      setState(() => _currentStep += 1);
                    } else {
                      _handleComplete();
                    }
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _OnboardingProgress extends StatelessWidget {
  const _OnboardingProgress({
    required this.currentStep,
    required this.onStepTapped,
  });

  final int currentStep;
  final ValueChanged<int> onStepTapped;

  static const _labels = ['功能与 AI', '通知', '账户', '完成'];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surface,
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final edge = constraints.maxWidth / (_labels.length * 2);
            final progress = currentStep / (_labels.length - 1);
            return SizedBox(
              height: 64,
              child: Stack(
                children: [
                  Positioned(
                    top: 16,
                    left: edge,
                    right: edge,
                    child: ClipRect(
                      child: Stack(
                        children: [
                          Container(
                            key: const ValueKey('onboarding-progress-line'),
                            height: 2,
                            color: colorScheme.outlineVariant,
                          ),
                          FractionallySizedBox(
                            widthFactor: progress,
                            alignment: Alignment.centerLeft,
                            child: Container(
                              height: 2,
                              color: colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var index = 0; index < _labels.length; index++)
                        Expanded(
                          child: _ProgressItem(
                            label: _labels[index],
                            index: index,
                            currentStep: currentStep,
                            onTap: () => onStepTapped(index),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ProgressItem extends StatelessWidget {
  const _ProgressItem({
    required this.label,
    required this.index,
    required this.currentStep,
    required this.onTap,
  });

  final String label;
  final int index;
  final int currentStep;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final active = index == currentStep;
    final complete = index < currentStep;
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: Align(
        alignment: Alignment.topCenter,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: AppShape.cardMediaBorder,
            hoverColor: colorScheme.primary.withValues(alpha: 0.08),
            splashColor: colorScheme.primary.withValues(alpha: 0.14),
            highlightColor: colorScheme.primary.withValues(alpha: 0.05),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: AppMotion.stateChange,
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: active
                          ? colorScheme.primary
                          : complete
                          ? colorScheme.primaryContainer
                          : colorScheme.surface,
                      border: Border.all(
                        color: active || complete
                            ? colorScheme.primary
                            : colorScheme.outline,
                      ),
                    ),
                    child: Center(
                      child: complete
                          ? Icon(
                              Icons.check_rounded,
                              size: 15,
                              color: colorScheme.onPrimaryContainer,
                            )
                          : Text(
                              '${index + 1}',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: active
                                        ? colorScheme.onPrimary
                                        : colorScheme.onSurface,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: active ? colorScheme.primary : null,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OnboardingNavigation extends StatelessWidget {
  const _OnboardingNavigation({
    required this.currentStep,
    required this.totalSteps,
    required this.isLoading,
    required this.onBack,
    required this.onNext,
  });

  final int currentStep;
  final int totalSteps;
  final bool isLoading;
  final VoidCallback? onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              OutlinedButton(
                onPressed: isLoading ? null : onBack,
                child: const Text('上一步'),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: isLoading ? null : onNext,
                icon: isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        currentStep == totalSteps - 1
                            ? Icons.check
                            : Icons.arrow_forward,
                      ),
                label: Text(currentStep == totalSteps - 1 ? '完成' : '下一步'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
