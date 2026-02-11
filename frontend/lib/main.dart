import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'theme/app_theme.dart';
import 'routing/app_router.dart';
import 'core/providers/theme_provider.dart';
import 'features/share_receiver/share_receiver_service.dart';

List<SharedMediaFile>? _initialSharedMedia;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  timeago.setLocaleMessages('zh_CN', timeago.ZhCnMessages());

  if (!kIsWeb) {
    try {
      _initialSharedMedia = await ReceiveSharingIntent.instance.getInitialMedia();
      debugPrint('📥 main: 初始分享内容 ${_initialSharedMedia?.length ?? 0} 个');
      if (_initialSharedMedia != null && _initialSharedMedia!.isNotEmpty) {
        for (final file in _initialSharedMedia!) {
          debugPrint('📥 main: type=${file.type}, path=${file.path}');
        }
      }
    } catch (e) {
      debugPrint('📥 main: 获取初始分享失败: $e');
    }
  }

  runApp(
    ProviderScope(
      child: VaultStreamApp(initialSharedMedia: _initialSharedMedia),
    ),
  );
}

class VaultStreamApp extends ConsumerStatefulWidget {
  final List<SharedMediaFile>? initialSharedMedia;

  const VaultStreamApp({
    super.key,
    this.initialSharedMedia,
  });

  @override
  ConsumerState<VaultStreamApp> createState() => _VaultStreamAppState();
}

class _VaultStreamAppState extends ConsumerState<VaultStreamApp> {
  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleInitialShare();
        ref.read(shareReceiverServiceProvider).initialize();
      });
    }
  }

  void _handleInitialShare() {
    final files = widget.initialSharedMedia;
    if (files != null && files.isNotEmpty) {
      debugPrint('📥 VaultStreamApp: 处理初始分享 ${files.length} 个文件');
      
      String? sharedText;
      final mediaFiles = <SharedMediaFile>[];

      for (final file in files) {
        if (file.type == SharedMediaType.text || file.type == SharedMediaType.url) {
          sharedText = file.path;
        } else {
          mediaFiles.add(file);
        }
      }

      final content = SharedContent(
        text: sharedText,
        mediaFiles: mediaFiles,
      );

      if (!content.isEmpty) {
        debugPrint('📥 VaultStreamApp: 设置分享内容到状态');
        ref.read(shareReceiverStateProvider.notifier).setSharedContent(content);
      }
      
      // 重置 intent 避免重复处理
      ReceiveSharingIntent.instance.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    // build方法是Flutter Widget的核心方法，用于构建Widget的UI。
    // build方法接受两个参数：BuildContext和WidgetRef。
    // context参数是Flutter框架传递的BuildContext对象，表示Widget在Widget树中的位置。
    // ref参数是WidgetRef对象，提供访问和监听Riverpod providers的功能。

    final router = ref.watch(goRouterProvider);
    final themeMode = ref.watch(themeModeProvider);

    return DynamicColorBuilder(
      // return语句用于返回一个Widget，这里返回的是DynamicColorBuilder Widget
      builder: (lightDynamic, darkDynamic) {
        // builder参数是一个回调函数，接受两个参数lightDynamic和darkDynamic，作用是根据动态颜色构建应用的主题
        // lightDynamic表示浅色主题的动态颜色，darkDynamic表示深色主题的动态颜色
        return MaterialApp.router(
          // MaterialApp.router是Flutter框架提供的一个用于构建路由化应用的Widget
          // 它是MaterialApp的一个变体，专门用于处理路由配置
          // routerConfig参数用于传递应用的路由配置，这里传递的是前面获取的router变量
          title: 'VaultStream',
          theme: AppTheme.light(lightDynamic), // 默认主题，使用浅色动态颜色
          darkTheme: AppTheme.dark(darkDynamic), // 深色主题，使用深色动态颜色
          themeMode: themeMode, // 主题模式
          routerConfig: router, // 应用的路由配置是叫router
          debugShowCheckedModeBanner: false,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('zh', 'CN'),
            Locale('en', 'US'),
          ],
        );
      },
    );
  }
}

// 启动-> ProviderScope(Riverpod状态管理)-> VaultStreamApp(应用主体)-> DynamicColorBuilder(动态颜色支持)-> MaterialApp.router(路由化应用)
