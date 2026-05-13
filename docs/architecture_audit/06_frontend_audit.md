# 06 — 前端架构体检报告（Flutter）

> 生成日期：2026-04-07  
> 覆盖范围：139 个 Dart 文件，12 个分析维度  
> 技术栈：Flutter + Riverpod 3.x (codegen) + freezed + go_router + Dio/Retrofit

## 报告目录

- [严重性分级汇总](#严重性分级汇总)
- [1. 状态管理](#1-状态管理)
- [2. 数据流](#2-数据流)
- [3. API 契约对齐](#3-api-契约对齐)
- [4. SSE 实时更新](#4-sse-实时更新)
- [5. 导航与路由](#5-导航与路由)
- [6. 内存管理](#6-内存管理)
- [7. 错误处理](#7-错误处理)
- [8. 多平台问题](#8-多平台问题)
- [9. 性能问题](#9-性能问题)
- [10. 安全性](#10-安全性)
- [11. 代码坏味道](#11-代码坏味道)
- [12. 已知问题交叉验证](#12-已知问题交叉验证)
- [前端重构优先级路线图](#前端重构优先级路线图)

---

## 严重性分级汇总

| # | 严重性 | 分类 | 问题简述 | 位置 |
|---|---|---|---|---|
| 1.1 | 🔴 Critical | 状态管理 | `ref.watch` 在 async 变更方法中调用，Riverpod 3 下运行时抛异常 | batch_selection / distribution_rules / bot_chats 等 |
| 3.4 | 🔴 Critical | API | `QueueFilterState.copyWith` 无法将 `ruleId` 清回 null，`setRuleId(null)` 是 no-op | queue_provider.dart |
| 5.2 | 🔴 Critical | 路由 | `context.go('/login')` 导航到不存在的路由，运行时崩溃 | connection_tab.dart:561 |
| 10.1 | 🔴 High | 安全 | API Token 被 `LogInterceptor` 写入日志（`requestHeader: true`） | api_client.dart |
| 10.2 | 🔴 High | 安全 | `debugLog` 默认值 `true`，Release 包也会记录 Token | env_config.dart |
| 7.5 | 🔴 High | 安全 | `launchUrl(Uri.parse(detail.url))` 未验证 scheme，可能执行 `javascript:` URL | content_detail_page.dart:264 |
| 6.1 | 🔴 High | 内存 | `TextEditingController` 在 `build` 方法内 new，每次重建泄漏旧 controller | connection_tab.dart:103,145,221,293 |
| 2.1 | 🔴 High | 数据流 | 双重 SSE 订阅路径：`CollectionPage.ref.listen` 触发 `invalidate` 与 Provider 内部增量更新逻辑互相覆盖 | collection_page.dart:97 |
| 7.3 | 🟡 High | 错误处理 | `SystemStatusNotifier.build` `catch (_) {}` 吞掉所有异常，路由守卫无感知 | system_status_provider.dart:42 |
| 1.3 | 🟡 Medium | 状态管理 | `sseConnectionState` 是 auto-dispose 但读取 keepAlive notifier，产生非对称依赖 | sse_service.dart:362 |
| 2.1 | 🟡 Medium | 数据流 | `CollectionPage.dispose` 里的 `clearFilters` 通过 `addPostFrameCallback` 是死代码 | collection_page.dart:52 |
| 2.4 | 🟡 Medium | 数据流 | `_navigateToCollection` 两次独立 filter 状态变更，触发两次 API 请求 | dashboard_page.dart:34 |
| 4.1 | 🟡 Medium | SSE | `SseEventBus` broadcast controller 从不关闭，Provider 重建后订阅累积 | sse_service.dart |
| 4.2 | 🟡 Medium | SSE | idle timeout 与 reconnect 可能形成紧循环 | sse_service.dart:339 |
| 5.4 | 🟡 Medium | 路由 | `DiscoveryPage` 移动端用 `Navigator.push(MaterialPageRoute(...))` 绕过 GoRouter | discovery_page.dart:151 |
| 9.1 | 🟡 Medium | 性能 | 每个 `ContentCard.build` 都调用 `MediaQuery.of(context)` 计算列宽 | content_card.dart:45 |
| 9.4 | 🟡 Medium | 性能 | `_getAvailableTags` 在每次 AppBar build 时遍历全量 items | collection_page.dart:279 |
| 10.4 | 🟡 Medium | 安全 | API Token 明文存于 `SharedPreferences`，应使用 `flutter_secure_storage` | local_settings_provider.dart:51 |
| 11.1~3 | 🟡 Medium | 代码质量 | 三个 God Widget（DiscoveryPage 842行 / ReviewPage 795行 / ContentDetailPage 575行） | — |
| 6.4 | 🟢 Low | 内存 | `ShareReceiverService` provider 重建后 `initialize()` 不会重调 | share_receiver_service.dart |
| 8.1 | 🟢 Low | 平台 | `video_player` 在 Web 端缺 CORS 考虑 | pubspec.yaml |
| 8.4 | 🟢 Low | 平台 | `cached_network_image` 与 `extended_image` 同时引入，包体积冗余 | pubspec.yaml |
| 11.5 | 🟢 Low | 代码质量 | `BatchSelectionState` 与 `DiscoverySelectionState` 结构完全相同，可抽象为泛型 | — |

---

## 1. 状态管理

### 1.1 🔴 `ref.watch` 在异步变更方法中调用（Critical）

**影响文件**：

| 文件 | 方法 | 行号 |
|---|---|---|
| `batch_selection_provider.dart` | `batchUpdateTags`, `batchSetNsfw`, `batchDelete`, `batchReParse` | 48, 64, 78, 93 |
| `distribution_rules_provider.dart` | `createRule`, `updateRule`, `deleteRule` | 29, 40, 55 |
| `distribution_targets_provider.dart` | `createTarget`, `updateTarget`, `deleteTarget` | 27, 37, 52 |
| `bot_chats_provider.dart` | `createChat`, `updateChat`, `deleteChat`, `syncChats` | 32, 44, 62, 74 |
| `collection_provider.dart` | `_fetch`（从 `fetchMore` 调用时） | 228 |
| `pushed_records_provider.dart` | `_fetchRecords` | 82 |

**问题**：Riverpod 3 规定 `ref.watch` 只能在 `build()` 方法中调用。在 async 方法（mutation）中调用会在 Riverpod 检测到 Provider 重建时抛出 `StateError`。

**修复**：将所有 mutation 方法中的 `ref.watch(apiClientProvider)` 改为 `ref.read(apiClientProvider)`。

---

### 1.2 🟡 `sseConnectionState` auto-dispose 读取 keepAlive notifier

**位置**：`lib/core/network/sse_service.dart:362`

```dart
// 问题：auto-dispose provider 持有对 keepAlive notifier 的 ref.watch
@riverpod
Stream<SseConnectionState> sseConnectionState(Ref ref) {
  return ref.watch(sseServiceProvider.notifier).connectionStateStream;
}
```

这产生非对称依赖：`sseConnectionState` 会被自动释放，但它阻止了 `sseServiceProvider`（keepAlive）的释放，同时这个 auto-dispose provider 本身对用户来说是透明的。语义混乱。

---

### 1.3 🟡 `DiscoveryActionsProvider` 手动 `keepAlive()` + 手动 `_isDisposed` 追踪

**位置**：`lib/features/discovery/providers/discovery_actions_provider.dart:14`

在 `build()` 内调用 `ref.keepAlive()` 将 auto-dispose provider 转为 keepAlive，同时又手动维护 `_isDisposed` 标志位。这是重复的生命周期管理，与 Riverpod 已有的 `ref.onDispose` 语义冲突。

---

### 1.4 🟡 `CollectionPage.dispose` 中的 `clearFilters` 是死代码

**位置**：`lib/features/collection/collection_page.dart:52`

```dart
@override
void dispose() {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) {  // dispose 之后 mounted 永远是 false
      ref.read(collectionFilterProvider.notifier).clearFilters();
    }
  });
  super.dispose();
}
```

`mounted` 在 `dispose()` 调用后始终为 `false`，这段 `clearFilters` 永远不会执行。

---

### 1.5 🟡 `SearchHistory` 每次变更重复调用 `SharedPreferences.getInstance()`

**位置**：`lib/features/collection/providers/search_history_provider.dart:20,30,38,44`

`main.dart` 已将 `SharedPreferences` 初始化为全局 `sharedPrefs` 变量，但 `SearchHistoryNotifier` 的 `add/remove/clear` 方法各自重新调用 `SharedPreferences.getInstance()`，绕过了已有的单例。

---

## 2. 数据流

### 2.1 🔴 双重 SSE 订阅路径互相覆盖

**位置**：`lib/features/collection/collection_page.dart:97` 和 `collection_provider.dart` 内部

`CollectionPage.build` 中：
```dart
ref.listen(sseEventStreamProvider, (_, event) {
  if (event?.type == 'content_updated') {
    ref.invalidate(collectionProvider);  // 触发全量重新加载
  }
});
```

同时，`CollectionProvider` 内部已有增量更新逻辑，通过 `SseEventBus().eventStream` 的 `StreamSubscription` 做局部更新。结果：每个 `content_updated` 事件触发两次响应，增量更新结果被随后的全量 `invalidate` 丢弃。

**修复**：删除 `CollectionPage` 中的 `ref.listen` SSE 监听，仅保留 Provider 内部的增量逻辑。

---

### 2.2 🟡 批量操作完成后未 invalidate `collectionProvider`

**位置**：`lib/features/collection/providers/batch_selection_provider.dart`

`batchDelete` 成功后，UI 等待 SSE 事件来更新列表。若 SSE 事件来迟，列表显示已删除内容，用户体验差。且若 API 调用失败，`catch` 块缺失，错误对 UI 不可见（仅 `isProcessing` 被重置）。

---

### 2.3 🟡 `_navigateToCollection` 触发两次 API 请求

**位置**：`lib/features/dashboard/dashboard_page.dart:34`

```dart
ref.read(collectionFilterProvider.notifier).clearFilters(); // 第一次状态变更 → 触发 fetch
ref.read(collectionFilterProvider.notifier).setFilters(...); // 第二次状态变更 → 再次触发 fetch
```

`collectionProvider` watch `collectionFilterProvider`，两次独立 state 变更触发两次 invalidation 和两次 API 请求。`DiscoveryPage` 用的是原子 `resetToFilters` 方法，应统一。

---

### 2.4 🟡 分页状态随 `invalidate` 全丢，SSE 触发时用户失去滚动位置

**位置**：`collection_provider.dart` 的 `_drainPendingEvents` 方法

当 SSE 事件积累超过阈值时调用 `ref.invalidateSelf()`，用户正在浏览第 3 页的内容会被拉回第 1 页，无任何提示。

---

## 3. API 契约对齐

### 3.1 🟡 `validateConnection` 使用无拦截器的裸 Dio

**位置**：`lib/core/providers/local_settings_provider.dart:68`

```dart
final dio = Dio(); // 无日志拦截器，无统一错误处理
```

调试时该请求不出现在日志中，错误格式化也不一致。

---

### 3.2 🟡 API Token 在 Widget 树中以字符串透传

**位置**：`content_detail_page.dart:149`、`content_card.dart:31` 等多处

```dart
final apiToken = dio.options.headers['X-API-Token']?.toString();
```

Token 以字符串形式从 `Dio` options 中提取并向下传递。可通过 `ref.watch(localSettingsProvider)` 更干净地获取，减少 Token 流通的代码路径数量。

---

### 3.3 🔴 `QueueFilterState.copyWith` 无法将 `ruleId` 清为 null（Critical）

**位置**：`lib/features/review/providers/queue_provider.dart:39`

```dart
QueueFilterState copyWith({int? ruleId, QueueStatus? status}) {
  return QueueFilterState(
    ruleId: ruleId ?? this.ruleId, // null ?? existing = existing，永远无法清除！
    ...
  );
}
```

UI 调用 `setRuleId(null)` 来显示"所有内容"，但 `copyWith(ruleId: null)` 实际上保留了原值，过滤器无法清除。

**修复**：使用 sentinel 模式或对 nullable 字段使用 `freezed` 的 `@Default` 注解处理 null 清除。

---

## 4. SSE 实时更新

### 4.1 🟡 `SseEventBus` broadcast controller 从不关闭

**位置**：`lib/core/network/sse_service.dart`

`SseEventBus` 是 Dart 静态单例，其 `_eventController` 和 `_stateController` 是 `StreamController.broadcast()`，在 `SseService` Provider 被销毁重建后，这些 controller 仍存活，旧的订阅者也仍保持活跃。`dispose()` 方法存在但未在 `SseService.ref.onDispose` 中调用。

---

### 4.2 🟡 idle timeout 与 reconnect 可能形成紧循环

**位置**：`sse_service.dart:339`

```
_resetIdleTimer → _handleClose → _scheduleReconnect(2s) → _connect → _doConnect → _resetIdleTimer
```

在网络延迟较高时，服务端响应慢于 idle timeout 阈值，会触发连续的 2s 周期重连循环，大量无效请求。

---

### 4.3 🟡 `_doConnect` 在 `await` 返回后未检查 `_disposed`

**位置**：`sse_service.dart:189`

```dart
final response = await client.send(request); // await 期间可能被 dispose
// 此处无 if (_disposed) return 检查
if (response.statusCode != 200) { ... }
```

Provider 被销毁时，若 `await` 恰好完成，将继续处理响应，在已销毁状态下写 state。

---

## 5. 导航与路由

### 5.1 🔴 `context.go('/login')` 路由不存在，运行时崩溃（Critical）

**位置**：`lib/features/settings/presentation/tabs/connection_tab.dart:561`

```dart
context.go('/login'); // 应为 context.go('/connect')
```

App 路由中定义的是 `/connect` 而非 `/login`。用户从设置页退出登录时必然触发 GoRouter exception。

---

### 5.2 🟡 路由守卫在 `systemStatus` 加载中时允许访问任意路由

**位置**：`lib/routing/app_router.dart:56`

Status 加载中时 `redirect` 返回 `null`（允许通过）。若 `hasConfig: true` 但 `needsSetup: true` 的检查在 status 返回前被跳过，用户将直接进入 Dashboard，错过 Onboarding 流程。

---

### 5.3 🟡 `DiscoveryPage` 移动端使用 `Navigator.push`，绕过 GoRouter

**位置**：`lib/features/discovery/discovery_page.dart:151`

```dart
Navigator.of(context).push(MaterialPageRoute(
  builder: (_) => DiscoveryDetailPage(item: item),
));
```

URL 不更新，不支持深链接，页面生命周期不受 GoRouter 管理。

---

### 5.4 🟡 `/agent` 和 `/bot` 路由无守卫

无检查 Bot 是否已配置。未配置时进入页面，立即遭遇 API 错误，无自动跳转到设置页的逻辑。

---

## 6. 内存管理

### 6.1 🔴 `TextEditingController` 在 `build` 中创建，从不 dispose（High）

**位置**：`lib/features/settings/presentation/tabs/connection_tab.dart`

```dart
// 每次 build 调用都创建新 controller，旧 controller 泄漏
Widget _buildBaseUrlEditor(String currentValue, ...) {
  final controller = TextEditingController(text: currentValue); // Line 103
  ...
}
```

影响行号：103, 145, 221, 293（至少 3 个 controller）。`ConnectionTab` 是 `ConsumerWidget`，无 `dispose` 生命周期。

**修复**：改为 `ConsumerStatefulWidget`，在 State 中持有并 dispose controller。

---

### 6.2 🟡 `ShareReceiverService` provider 重建后 `initialize()` 不重调

**位置**：`lib/features/share_receiver/share_receiver_service.dart:119`

`shareReceiverServiceProvider` 是 auto-dispose。`initialize()` 仅在 `VaultStreamApp.initState` 调用一次。Provider 被 invalidate 重建后，新 service 实例不会再调 `initialize()`，导致分享 Intent 监听缺失。

---

## 7. 错误处理

### 7.1 🔴 `launchUrl` 无 scheme 校验（安全 + 错误处理）

**位置**：`lib/features/collection/content_detail_page.dart:264`

```dart
launchUrl(Uri.parse(detail.url), mode: LaunchMode.externalApplication)
```

未使用 `SafeUrlLauncher.openExternal`，`javascript:` 或 `data:` 格式的 URL 会被直接传给系统。

---

### 7.2 🟡 `SystemStatusNotifier` 静默吞掉所有连接错误

**位置**：`lib/core/providers/system_status_provider.dart:42`

```dart
} catch (_) {
  // 连接失败时 isLoaded=false，但 router 会当作"允许通行"处理
}
```

后端不可达时，用户看到的是空白页，而非"无法连接服务器"的明确提示。

---

### 7.3 🟡 错误信息显示原始异常对象

| 位置 | 问题 |
|---|---|
| `content_detail_page.dart:303` | `Text('加载失败: $err')` 显示原始 DioException |
| `content_detail_page.dart:504` | `Toast.show(context, '请求失败: $e')` |
| `content_detail_page.dart:524` | `Toast.show(context, '摘要生成失败: $e')` |

项目已有 `formatApiErrorMessage(e)` 工具函数，未被这几处使用。

---

## 8. 多平台问题

### 8.1 🟡 `video_player` 在 Web 端未考虑 CORS

`pubspec.yaml` 引入 `video_player: ^2.10.1`。Flutter Web 的 `video_player` 要求视频 CDN 设置 CORS 响应头。后端代理媒体 URL 时若未附带 CORS 头，视频在 Web 端无法播放，且失败无提示。

---

### 8.2 🟢 两个图片缓存库同时存在，包体积冗余

```yaml
cached_network_image: ^3.4.1  # ContentCard 使用
extended_image: ^8.2.0         # 全屏画廊使用
```

两者功能重叠。建议统一为 `extended_image`（功能更全，支持手势缩放）或 `cached_network_image`。

---

### 8.3 🟢 `google_fonts` 运行时下载字体，离线环境不可用

建议将字体打包为 Flutter assets，或在 `main.dart` 中配置 `GoogleFonts.config.allowRuntimeFetching = false` 并预加载。

---

## 9. 性能问题

### 9.1 🟡 `ContentCard` 每次 build 都调用 `MediaQuery.of(context)` 计算列宽

**位置**：`lib/features/collection/widgets/list/content_card.dart:45`

`MediaQuery.of(context).size.width` 在每张卡片的每次 build 中执行。Grid 中 20 张卡片 × 每次 scroll/rebuild = 高频无效计算。

**修复**：在 `CollectionGrid` 层计算 `cardWidth` 并通过 `InheritedWidget` 或构造参数向下传递。

---

### 9.2 🟡 `_getAvailableTags` 每次 AppBar build 遍历全量 items

**位置**：`lib/features/collection/collection_page.dart:279`

```dart
List<String> _getAvailableTags() {
  return collectionProvider.value.items  // O(n × tags/item)
      .expand((c) => c.tags)
      .toSet().toList();
}
```

此方法在 FrostedAppBar 每次重建时调用（含滚动时）。应缓存为 `late final` 或 `useMemoized`。

---

### 9.3 🟡 `DiscoveryPage._buildDesktopBody` 在每次 build 时注册 `addPostFrameCallback`

**位置**：`lib/features/discovery/discovery_page.dart:174`

```dart
if (_selectedItemId == null && response.items.isNotEmpty) {
  WidgetsBinding.instance.addPostFrameCallback((_) { ... });
}
```

在 `_selectedItemId == null` 期间，每次 rebuild 都注册一个新的 postFrameCallback，导致多次冗余的 `setState`。

---

### 9.4 🟢 ContentCard 入场动画 `index % 10 * 100ms` 延迟最长 900ms

**位置**：`content_card.dart:279`

初次加载或 `invalidate` 后，第 10 张卡片要等 900ms 才可见，体验较重。

---

## 10. 安全性

### 10.1 🔴 API Token 被 `LogInterceptor` 写入日志（High）

**位置**：`lib/core/network/api_client.dart:108`

```dart
if (EnvConfig.debugLog) {
  dio.interceptors.add(LogInterceptor(requestHeader: true)); // 包含 X-API-Token
}
```

Token 出现在 `adb logcat` 可读的设备日志中。

---

### 10.2 🔴 `debugLog` 默认值为 `true`，Release 包也记录 Token

**位置**：`lib/core/config/env_config.dart:11`

```dart
static const bool debugLog = bool.fromEnvironment('DEBUG_LOG', defaultValue: true);
```

未传 `--dart-define=DEBUG_LOG=false` 时，Release 构建同样开启日志。应将 `defaultValue` 改为 `false`。

---

### 10.3 🟡 API Token 明文存于 `SharedPreferences`

**位置**：`lib/core/providers/local_settings_provider.dart:51`

Android `SharedPreferences` 数据在 root/ADB backup 场景下可读取。应改用 `flutter_secure_storage` 存储 Token 和其他凭证。

---

### 10.4 🟡 `InteractiveLoginDialog` 未验证 `_captchaUrl` scheme

**位置**：`lib/features/auth/presentation/widgets/interactive_login_dialog.dart:156`

来自后端的 captcha URL 直接传给 `launchUrl`，应改用 `SafeUrlLauncher.openExternal`。

---

## 11. 代码坏味道

### 11.1 三个 God Widget

| 文件 | 行数 | 混杂职责 |
|---|---|---|
| `discovery_page.dart` | 842 | 过滤器 Sheet、master-detail 布局、选择模式 AppBar、搜索 Anchor，全在一个文件 |
| `review_page.dart` | 795 | 规则管理 UI、队列 UI、历史 UI、所有 CRUD 对话框 |
| `content_detail_page.dart` | 575 | SSE 订阅、ToC 滚动追踪、主题生成、5 种 action handler |

---

### 11.2 `ConnectionTab` 中直接写业务逻辑

`_checkPlatformStatus`、`_refreshZhihuZse`、`_logoutPlatform`、`_testConnection` 等均为 API 调用方法，写在 `ConsumerWidget` 中。应移至独立 Provider 或 Service。

---

### 11.3 `SelectionState` 重复定义

`BatchSelectionState`（collection）与 `DiscoverySelectionState`（discovery）结构完全相同：`selectedIds: Set<int>`, `isSelectionMode`, `isProcessing`, `count`, `isSelected`, `copyWith`。应抽象为泛型 `SelectionState<T>` 基类。

---

### 11.4 `fetchMore` / 无限滚动模式三处重复实现

`CollectionProvider.fetchMore`、`DiscoveryItemsProvider.fetchMore`、`ApprovalQueueProvider.fetchMore` 逻辑完全相同（检查 isLoading → 取当前数据 → page+1 → 合并 items）。可提取为 mixin 或抽象基类。

---

### 11.5 `AgentPage` 会话历史不持久化

**位置**：`lib/features/agent/agent_page.dart:19`

```dart
final List<_AgentMessage> _messages = [];
```

导航离开后所有对话记录丢失。对于定位为生产力工具的 Agent 功能，这是显著的 UX 缺陷。

---

## 12. 已知问题交叉验证

### `docs/known-issues/discovery-detail-top-overlap.md`

**状态：未修复（已确认）**

`_buildDesktopBody` 使用 Stack 覆盖布局，右侧面板 `DiscoveryDetailPage` 无 `topBarHeight` 参数，Gallery/Video 子组件不接收顶部偏移量。文档中描述的两种修复方案（传 height 参数 / Sliver 重构）均未实现。

---

### `docs/known-issues/discovery.md`（6 条）

**状态：全部未修复（已确认）**

| # | 问题 | 代码确认位置 |
|---|---|---|
| 1 | 桌面断点基于全 App 宽度而非内容面板宽度 | `discovery_page.dart:69`，`constraints.maxWidth < 800` |
| 2 | SearchAnchor 宽度未限制在左面板内 | `_buildSearchAnchor` 无宽度约束 |
| 3 | 过滤器用底部 Sheet 而非动画展开 | `showModalBottomSheet` 调用 |
| 4 | items 为空时不显示 Empty State | `data` 分支直接进入 build body |
| 5 | Source 过滤器用 `ref.read`，首次可能为空 | `_DiscoveryFilterSheet` 中 `ref.read(discoverySourcesProvider).value ?? []` |
| 6 | 发现页顶部有多余分割线 | `border: Border(bottom: BorderSide(...))` at line 305 |

---

### `docs/known-issues/flutter-ufffd-utf8-bug.md`

**状态：已有 Workaround**

`sse_service.dart:209` 使用 `Utf8Decoder(allowMalformed: true)`，前端侧已规避。后端侧 workaround 若被移除，前端的 `allowMalformed: true` 可防止崩溃但可能显示乱码。

---

## 前端重构优先级路线图

### P0：立即修复（代价低，1-3天）

1. **`context.go('/login')` → `/connect`**（`connection_tab.dart:561`）—— 1行改动，避免 Release 崩溃
2. **`debugLog` 默认值 `true` → `false`**（`env_config.dart:11`）—— 1行改动，修复 Token 泄漏
3. **所有 mutation 方法中 `ref.watch` → `ref.read`**（6个文件）—— 批量替换
4. **`QueueFilterState.copyWith` 修复 nullable ruleId**（`queue_provider.dart:39`）—— 使用 Optional/sentinel 模式
5. **`launchUrl` → `SafeUrlLauncher.openExternal`**（`content_detail_page.dart:264`，`interactive_login_dialog.dart:156`）

### P1：短期改善（1-2周）

6. **`ConnectionTab` → `ConsumerStatefulWidget`**，TextEditingController 正确 dispose
7. **删除 `CollectionPage` 中的冗余 SSE `ref.listen`**，保留 Provider 内部增量逻辑
8. **`_navigateToCollection` 改为原子 filter 更新**（参考 `resetToFilters`）
9. **API Token → `flutter_secure_storage`**
10. **`SystemStatusNotifier` 错误处理**：catch 后更新为可区分"未加载"与"连接失败"的状态
11. **`discovery_page.dart` 移动端使用 GoRouter 导航**，支持 URL 更新和深链接

### P2：中长期重构

12. **拆分三个 God Widget**（DiscoveryPage / ReviewPage / ContentDetailPage）
13. **提取通用 `SelectionState<T>` 和 `fetchMore` mixin**
14. **`SseEventBus` 生命周期与 `SseService` Provider 对齐**（controller 跟随 provider 关闭）
15. **`AgentPage` 会话历史持久化**（SharedPreferences 或 SQLite）
16. **修复 `DiscoveryPage` 所有 6 条已知问题**（见 docs/known-issues/discovery.md）
17. **图片缓存库统一**（择一使用 `extended_image` 或 `cached_network_image`）
