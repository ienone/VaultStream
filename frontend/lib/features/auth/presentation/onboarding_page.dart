import 'package:frontend/core/network/api_client.dart';
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
import 'widgets/onboarding_feature_card.dart';

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage>
    with SingleTickerProviderStateMixin {
  late final TabController _stepController;
  int get _currentStep => _stepController.index;
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
  void initState() {
    super.initState();
    _stepController = TabController(length: _totalSteps, vsync: this);
  }

  void _selectStep(int step) {
    FocusScope.of(context).unfocus();
    setState(() => _stepController.index = step);
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

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
    _stepController.dispose();
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
      if (mounted) {
        setState(
          () => _error = formatApiErrorMessage(e, fallbackMessage: '模型探测失败'),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleComplete() async {
    if (_enableTextLlm &&
        (_llmKeyController.text.trim().isEmpty ||
            _llmBaseUrlController.text.trim().isEmpty)) {
      setState(() {
        _stepController.index = 0;
        _error = '请填写内容理解的 API 地址和密钥';
      });
      return;
    }
    if (_enableAutoSummary && _summaryKeyController.text.trim().isEmpty) {
      setState(() {
        _stepController.index = 0;
        _error = '请填写自动摘要的 API Key';
      });
      return;
    }
    if (_enableEmbedding && _embeddingKeyController.text.trim().isEmpty) {
      setState(() {
        _stepController.index = 0;
        _error = '请填写语义搜索的 API Key';
      });
      return;
    }
    if (_enableVisionLlm &&
        (_visionKeyController.text.trim().isEmpty ||
            _visionBaseUrlController.text.trim().isEmpty)) {
      setState(() {
        _stepController.index = 0;
        _error = '请填写图像理解的 API 地址和密钥';
      });
      return;
    }
    if (_enableTelegramBot && _tgTokenController.text.trim().isEmpty) {
      setState(() {
        _stepController.index = _botStep;
        _error = '请填写 Telegram Bot Token';
      });
      return;
    }
    if (_enableQqBot && _qqUrlController.text.trim().isEmpty) {
      setState(() {
        _stepController.index = _botStep;
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
      if (mounted) {
        setState(
          () => _error = formatApiErrorMessage(e, fallbackMessage: '保存失败'),
        );
      }
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
      animationStyle: MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : null,
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
            borderRadius: AppShape.cardBorder,
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

  Widget _responsiveCardWrap({
    required List<Widget> children,
    required int maxColumns,
  }) {
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxColumns == 1
              ? AppPane.readableMaxWidth
              : double.infinity,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
            final columns = (constraints.maxWidth / (320 * textScale))
                .floor()
                .clamp(1, maxColumns);
            const spacing = 12.0;
            final itemWidth =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              crossAxisAlignment: WrapCrossAlignment.start,
              children: [
                for (final child in children)
                  SizedBox(width: itemWidth, child: child),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _featureStep() {
    final cards = [
      OnboardingFeatureCard(
        key: _textFeatureKey,
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
      OnboardingFeatureCard(
        key: _summaryFeatureKey,
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
      OnboardingFeatureCard(
        key: _embeddingFeatureKey,
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
            LayoutBuilder(
              builder: (context, constraints) {
                final modelField = TextField(
                  controller: _embeddingModelController,
                  decoration: const InputDecoration(labelText: '模型'),
                );
                final dimensionField = TextField(
                  controller: _embeddingDimController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '维度'),
                );
                final textScale =
                    MediaQuery.textScalerOf(context).scale(16) / 16;
                if (constraints.maxWidth < 480 * textScale) {
                  return Column(
                    children: [
                      modelField,
                      const SizedBox(height: AppSpacing.sm),
                      dimensionField,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(flex: 2, child: modelField),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: dimensionField),
                  ],
                );
              },
            ),
          ],
        ),
      ),
      OnboardingFeatureCard(
        key: _visionFeatureKey,
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
      maxColumns: 1,
    );
  }

  Widget _botConfigCard({required bool telegram}) {
    final enabled = telegram ? _enableTelegramBot : _enableQqBot;
    return OnboardingFeatureCard(
      key: telegram ? _telegramKey : _qqKey,
      title: telegram ? 'Telegram' : 'QQ',
      icon: telegram ? Icons.send_outlined : Icons.chat_outlined,
      value: enabled,
      onChanged: (value) => setState(() {
        if (telegram) {
          _enableTelegramBot = value;
        } else {
          _enableQqBot = value;
        }
      }),
      configuration: Column(
        children: [
          TextField(
            controller: telegram ? _tgTokenController : _qqUrlController,
            decoration: InputDecoration(
              labelText: telegram ? 'Bot Token' : 'Napcat API 地址',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: telegram ? _tgAdminIdController : _qqAdminIdController,
            decoration: InputDecoration(
              labelText: telegram ? '管理员 ID（可选）' : '管理员 QQ 号（可选）',
              border: const OutlineInputBorder(),
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
      maxColumns: 1,
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
          LayoutBuilder(
            builder: (context, constraints) {
              final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
              final stacked = constraints.maxWidth < 440 * textScale;
              final connectButton = connected
                  ? null
                  : FilledButton.tonalIcon(
                      onPressed: () => _showLoginDialog(id, label),
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('扫码连接'),
                    );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                    leading: Icon(
                      connected
                          ? Icons.check_circle
                          : Icons.account_circle_outlined,
                      color: connected
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    title: Text(label),
                    subtitle: Text(connected ? '已连接' : '未连接'),
                    trailing: stacked ? null : connectButton,
                  ),
                  if (stacked && connectButton != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: connectButton,
                      ),
                    ),
                ],
              );
            },
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
    _selectStep(step);
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

  Widget _reviewItem({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.edit_outlined),
        onTap: onTap,
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
        _reviewItem(
          title: '内容理解',
          subtitle: _llmModelController.text.trim(),
          icon: Icons.text_snippet_outlined,
          onTap: () => _jumpToConfiguration(0, _textFeatureKey),
        ),
      if (_enableAutoSummary)
        _reviewItem(
          title: '自动摘要',
          subtitle: _summaryModelController.text.trim(),
          icon: Icons.auto_awesome_outlined,
          onTap: () => _jumpToConfiguration(0, _summaryFeatureKey),
        ),
      if (_enableEmbedding)
        _reviewItem(
          title: '语义搜索',
          subtitle: _embeddingModelController.text.trim(),
          icon: Icons.manage_search_outlined,
          onTap: () => _jumpToConfiguration(0, _embeddingFeatureKey),
        ),
      if (_enableVisionLlm)
        _reviewItem(
          title: '图像理解',
          subtitle: _visionModelController.text.trim(),
          icon: Icons.image_search_outlined,
          onTap: () => _jumpToConfiguration(0, _visionFeatureKey),
        ),
      if (_enableTelegramBot)
        _reviewItem(
          title: 'Telegram',
          subtitle: '推送已启用',
          icon: Icons.send_outlined,
          onTap: () => _jumpToConfiguration(_botStep, _telegramKey),
        ),
      if (_enableQqBot)
        _reviewItem(
          title: 'QQ',
          subtitle: '推送已启用',
          icon: Icons.chat_outlined,
          onTap: () => _jumpToConfiguration(_botStep, _qqKey),
        ),
      if (hasConfiguredAccounts)
        _reviewItem(
          title: '平台账户',
          subtitle: '检查登录状态',
          icon: Icons.account_circle_outlined,
          onTap: () => _jumpToConfiguration(_accountStep, _accountsKey),
        ),
    ];
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppPane.readableMaxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('确认配置', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.md),
            if (cards.isEmpty) const Text('没有需要确认的可选配置') else ...cards,
          ],
        ),
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
    final compactHeight = WindowMetrics.of(context).heightClass.isCompact;
    return Scaffold(
      appBar: AppBar(
        title: const Text('初始化向导'),
        toolbarHeight: compactHeight ? 48 : null,
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverToBoxAdapter(
                  child: ExcludeFocus(
                    excluding: _isLoading,
                    child: IgnorePointer(
                      ignoring: _isLoading,
                      child: TabBar(
                        controller: _stepController,
                        isScrollable: true,
                        tabAlignment: TabAlignment.start,
                        dividerColor: Colors.transparent,
                        onTap: _isLoading ? null : _selectStep,
                        tabs: const [
                          Tab(child: Text('1 · 功能与 AI')),
                          Tab(child: Text('2 · 通知')),
                          Tab(child: Text('3 · 账户')),
                          Tab(child: Text('4 · 完成')),
                        ],
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  sliver: SliverToBoxAdapter(child: _currentStepContent()),
                ),
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
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
                            : () => _selectStep(_currentStep - 1),
                        onNext: () {
                          if (_currentStep < _finishStep) {
                            _selectStep(_currentStep + 1);
                          } else {
                            _handleComplete();
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
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
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: OverflowBar(
            alignment: MainAxisAlignment.spaceBetween,
            overflowAlignment: OverflowBarAlignment.end,
            spacing: AppSpacing.xs,
            overflowSpacing: AppSpacing.xs,
            children: [
              OutlinedButton(
                onPressed: isLoading ? null : onBack,
                child: const Text('上一步'),
              ),
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
