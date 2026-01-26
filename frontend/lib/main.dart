import 'package:flutter/material.dart'; // 引入Flutter的Material库，用于构建符合Material Design规范的应用
import 'package:flutter_riverpod/flutter_riverpod.dart'; // 引入Riverpod库，用于状态管理
import 'package:dynamic_color/dynamic_color.dart'; // 引入dynamic_color库，用于动态颜色支持
import 'theme/app_theme.dart'; // 引入自定义的应用主题
import 'routing/app_router.dart'; // 引入自定义的应用路由
import 'core/providers/theme_provider.dart';

import 'core/providers/local_settings_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final container = ProviderContainer();
  await container.read(localSettingsProvider.notifier).init();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const VaultStreamApp(),
    ),
  );
  //启动代码，使用Riverpod的ProviderScope包裹应用
  // Riverpod是一个状态管理库，ProviderScope是其核心Widget，
  // ProviderScope提供一个上下文作用域，用于管理和存储应用中的所有提供者（providers）。
  // 只有在ProviderScope作用域内的providers才能被访问和监听。
  // 通过将整个应用包裹在ProviderScope中，可以确保应用中的任何位置都可以访问和使用定义的providers。
  // 因此这段代码表示启动一个使用Riverpod进行状态管理的Flutter应用VaultStreamApp.
}

class VaultStreamApp extends ConsumerWidget {
  // ConsumerWidget是Riverpod提供的一个可以监听providers的无状态Widget(stateless widget)。
  // providers是Riverpod中的核心概念，表示应用中的状态或数据源,比如计数器的值、用户信息等。
  // extends 用于继承类，表示VaultStreamApp类继承自ConsumerWidget类,能使用WidgetRef来访问和监听providers。

  const VaultStreamApp({
    super.key,
  }); // 常量构造函数，接受一个可选的key参数，传递给父类ConsumerWidget的构造函数。

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        );
      },
    );
  }
}

// 启动-> ProviderScope(Riverpod状态管理)-> VaultStreamApp(应用主体)-> DynamicColorBuilder(动态颜色支持)-> MaterialApp.router(路由化应用)
