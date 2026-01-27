# VaultStream Flutter 客户端

Flutter 跨平台客户端，支持 Web、Desktop、Mobile 多端统一的 VaultStream 管理控制台。

## 项目概述

基于 Flutter + Material 3 构建的多端应用，提供以下核心功能：

- 收藏中心 (Collection): 瀑布流展示收藏内容，支持媒体预览、全文搜索、多维筛选
- 审批面板 (Review): 分发规则配置、推送审计、实时监控
- 仪表板 (Dashboard): 队列负载监控、存储容量分析、运行状态
- 设置页面 (Settings): API 地址、主题
- 多端适配: 响应式布局，完美适配手机竖屏、平板、桌面宽屏

## 技术栈

| 组件 | 说明 |
|------|------|
| 框架 | Flutter 3.x + Material 3 |
| 状态管理 | Riverpod (Provider) |
| 路由 | go_router |
| 序列化 | freezed + json_serializable |
| HTTP 客户端 | dio |
| 存储 | shared_preferences (本地缓存) |
| 分析 | Flutter Lints |

## 快速开始

### 前置条件

- Flutter SDK: 3.10.0 或更高版本
- Dart SDK: 随 Flutter 附带
- 编辑器: VS Code 或 Android Studio

### 1. 检查环境

```bash
# 验证 Flutter 安装
flutter doctor

# 输出应显示:
# ✓ Flutter (version 3.x.x)
# ✓ Dart (version 3.x.x)
# ✓ Android toolchain / Xcode (取决于平台)
```

### 2. 安装依赖

```bash
# 获取最新依赖
flutter pub get
```

### 3. 代码生成

项目使用 `freezed` 和 `json_serializable` 需要代码生成:

```bash
# 生成模型和序列化代码
dart run build_runner build

# 或监听文件变化自动生成 (开发时推荐)
dart run build_runner watch
```

### 4. 启动应用

#### Web 版本 (推荐开发)
```bash
flutter run -d chrome
```

#### Android 模拟器
```bash
flutter run -d emulator
```

#### iOS 模拟器 (macOS only)
```bash
flutter run -d iphone
```

#### Windows Desktop
```bash
flutter run -d windows
```

#### Linux Desktop
```bash
flutter run -d linux
```

## 项目结构

```
frontend/
├── lib/
│   ├── main.dart                        # 应用入口
│   ├── core/                            # 核心模块 (横切关注点)
│   │   ├── config/
│   │   │   └── app_config.dart          # 应用全局配置
│   │   ├── network/                     # 网络层
│   │   │   ├── api_client.dart          # API 客户端 (Dio)
│   │   │   └── interceptors.dart        # 请求/响应拦截器
│   │   ├── providers/                   # 全局 Riverpod providers
│   │   │   ├── auth_provider.dart       # 认证状态
│   │   │   └── theme_provider.dart      # 主题状态
│   │   ├── services/                    # 业务服务
│   │   │   ├── local_storage_service.dart  # shared_preferences 封装
│   │   │   └── api_service.dart         # API 服务封装
│   │   ├── utils/                       # 工具函数
│   │   │   ├── extensions.dart
│   │   │   ├── date_formatter.dart
│   │   │   └── validators.dart
│   │   └── widgets/                     # 通用组件
│   │       ├── loading_widget.dart
│   │       ├── error_widget.dart
│   │       └── empty_state_widget.dart
│   ├── features/                        # 功能模块 (Clean Architecture)
│   │   ├── collection/                  # 收藏中心 (M3 集成)
│   │   │   ├── data/
│   │   │   │   ├── models/              # 数据模型 (freezed)
│   │   │   │   ├── repositories/        # 数据仓库
│   │   │   │   └── datasources/         # 数据源 (API、本地)
│   │   │   ├── domain/
│   │   │   │   └── entities/            # 业务实体
│   │   │   ├── presentation/
│   │   │   │   ├── screens/
│   │   │   │   │   ├── collection_screen.dart      # 主列表
│   │   │   │   │   └── content_detail_screen.dart  # 详情页
│   │   │   │   ├── widgets/
│   │   │   │   │   ├── content_grid_widget.dart    # 网格展示
│   │   │   │   │   ├── search_filter_widget.dart   # 搜索过滤
│   │   │   │   │   └── media_viewer_widget.dart    # 媒体查看器
│   │   │   │   └── providers/           # Feature-level providers
│   │   │   └── routes/                  # 路由配置 (可选)
│   │   │
│   │   ├── review/                      # 审批面板 (M4 集成)
│   │   │   ├── data/
│   │   │   ├── domain/
│   │   │   ├── presentation/
│   │   │   │   ├── screens/
│   │   │   │   │   ├── rules_management_screen.dart  # 规则管理
│   │   │   │   │   └── push_audit_screen.dart        # 推送审计
│   │   │   │   ├── widgets/
│   │   │   │   └── providers/
│   │   │   └── routes/
│   │   │
│   │   ├── dashboard/                   # 仪表板 (系统监控)
│   │   │   └── presentation/
│   │   │       ├── screens/
│   │   │       │   └── dashboard_screen.dart      # 主仪表板
│   │   │       ├── widgets/
│   │   │       │   ├── queue_monitor_widget.dart  # 队列监控
│   │   │       │   ├── storage_widget.dart        # 存储分析
│   │   │       │   └── health_check_widget.dart   # 健康检查
│   │   │       └── providers/
│   │   │
│   │   └── settings/                    # 设置页面
│   │       └── presentation/
│   │           ├── screens/
│   │           │   └── settings_screen.dart   # 配置界面
│   │           ├── widgets/
│   │           └── providers/
│   │
│   ├── routing/                         # 路由配置
│   │   └── app_router.dart              # go_router 全局路由
│   │
│   ├── layout/                          # 响应式布局组件
│   │   ├── adaptive_scaffold.dart       # 自适应脚手架
│   │   └── responsive_widget.dart       # 响应式包装
│   │
│   └── theme/                           # 主题配置
│       └── app_theme.dart               # Material 3 主题定义
│
├── test/                                # Widget 和集成测试
│
├── web/                                 # Web 构建输出
│   └── index.html                       # HTML 入口
│
├── android/                             # Android 原生配置
│   └── app/                             # Android 应用配置
│
├── linux/                               # Linux 桌面配置
│   └── CMakeLists.txt                  # Linux 构建配置
│
├── .metadata                            # Flutter 元数据文件
├── analysis_options.yaml                # Dart 分析规则
├── pubspec.yaml                         # Flutter 依赖管理
├── pubspec.lock                         # 依赖版本锁定
├── README.md                            # 本文件
└── .gitignore                           # Git 忽略规则
```

**关键目录说明**:
- `lib/core/` - 横切关注点：网络、存储、主题、认证等全局能力
- `lib/features/*/data/` - 数据层：Repository、DataSource、Model
- `lib/features/*/presentation/` - 表现层：Screen、Widget、Provider
- `lib/routing/` - 统一路由配置，所有屏幕在此定义
- `lib/theme/` - Material 3 主题，支持动态色彩

## 核心功能说明

### 收藏中心

主要界面:
- `collection_page.dart` - 瀑布流/网格展示
- `content_detail_page.dart` - 内容详情和编辑

功能:
- 瀑布流/自适应网格展示
- 媒体预览（图片、视频缩略图）
- 全文搜索（FTS5）
- 多维筛选：平台、作者、标签、状态、日期
- 批量操作：修改标签、删除、重解析

相关 Providers:
- `collection_provider.dart` - 内容列表状态
- `search_history_provider.dart` - 搜索历史状态

### 审批面板 (Review)

主要界面:
- `rules_management_screen.dart` - 分发规则 CRUD
- `push_audit_screen.dart` - 推送历史和审计

功能:
- 规则配置：标签 → 目标平台
- NSFW 策略和审批流管理
- 推送历史追踪
- 重新推送失败任务

相关 Providers:
- `distribution_rules_provider.dart` - 规则状态
- `push_records_provider.dart` - 推送历史状态

### 仪表板 (Dashboard)

主要组件:
- `queue_monitor_widget.dart` - 任务队列监控（Pending/Processing/Failed）
- `storage_widget.dart` - 存储占用分析
- `health_check_widget.dart` - 后端健康检查

功能:
- 实时任务统计
- 存储容量和分布
- API 响应时间监控

### 设置页面 (Settings)

主要设置:
- API 地址配置
- 主题色选择

## 开发指南

### 添加新 API 接口

1. 定义数据模型 (使用 freezed):

```dart
// lib/features/collection/data/models/my_model.dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'my_model.freezed.dart';
part 'my_model.g.dart';

@freezed
class MyModel with _$MyModel {
  const factory MyModel({
    required int id,
    required String name,
    @Default([]) List<String> tags,
  }) = _MyModel;

  factory MyModel.fromJson(Map<String, dynamic> json) =>
      _$MyModelFromJson(json);
}
```

2. 在 API Client 添加方法:

```dart
// lib/core/network/api_client.dart
Future<MyModel> getMyModel(int id) async {
  final response = await dio.get('/api/v1/my-model/$id');
  return MyModel.fromJson(response.data);
}
```

3. 创建 Feature Provider:

```dart
// lib/features/collection/presentation/providers/my_model_provider.dart
final myModelProvider = FutureProvider.family<MyModel, int>((ref, id) {
  final apiService = ref.watch(apiServiceProvider);
  return apiService.getMyModel(id);
});
```

4. 在 UI 中使用:

```dart
// lib/features/collection/presentation/screens/my_screen.dart
ConsumerWidget(
  builder: (context, ref, child) {
    final asyncValue = ref.watch(myModelProvider(123));
    return asyncValue.when(
      data: (model) => Text(model.name),
      loading: () => const CircularProgressIndicator(),
      error: (err, stack) => Text('Error: $err'),
    );
  },
)
```

### 响应式布局

项目使用 `AdaptiveScaffold` 和 `ResponsiveWidget` 处理多端适配：

```dart
// 自动根据屏幕宽度选择布局
AdaptiveScaffold(
  mobile: MobileLayout(),
  tablet: TabletLayout(),
  desktop: DesktopLayout(),
)
```

### 样式和主题

项目使用 Material 3 动态色彩系统：

```dart
// lib/theme/app_theme.dart
MaterialApp(
  theme: ThemeData(
    useMaterial3: true,
    colorSchemeSeed: Colors.blue,
  ),
)
```

### 本地存储

使用 `shared_preferences` 存储简单数据：

```dart
// lib/core/services/local_storage_service.dart
class LocalStorageService {
  static final _instance = LocalStorageService._();
  
  factory LocalStorageService() => _instance;
  LocalStorageService._();

  late SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  Future<void> saveToken(String token) async {
    await _prefs.setString('auth_token', token);
  }

  String? getToken() => _prefs.getString('auth_token');
}

// 在 Provider 中使用
final tokenProvider = FutureProvider<String?>((ref) async {
  return LocalStorageService().getToken();
});
```

## 构建和打包

### Web 版本

```bash
# 开发构建 (带热重载)
flutter run -d chrome

# 生产构建
flutter build web --release

# 输出目录: build/web/
```

### Android APK

```bash
# 生成 release APK
flutter build apk --release

# 或生成 AAB (Google Play)
flutter build appbundle --release
```

### iOS 应用

```bash
flutter build ios --release
open ios/Runner.xcworkspace  # 使用 Xcode 签名上传
```

### Windows EXE

```bash
flutter build windows --release
# 输出: build/windows/runner/Release/
```

### Linux 应用

```bash
flutter build linux --release
# 输出: build/linux/x64/release/bundle/
```

## 测试

### 运行单元测试

```bash
flutter test
```

### 运行集成测试

```bash
flutter test integration_test/
```

### 代码覆盖率

```bash
flutter test --coverage
```

## 调试

### 启用详细日志

```bash
flutter run -v
```

### 使用 DevTools

```bash
flutter pub global activate devtools
devtools

# 或在运行时自动打开
flutter run --dev-tools
```

## 依赖升级

```bash
# 检查过期依赖
flutter pub outdated

# 升级所有依赖
flutter pub upgrade

# 升级到最新版本
flutter pub upgrade --major-versions
```

## 许可证

MIT License - 同主项目
