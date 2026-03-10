# 已知问题：探索详情页顶部内容被导航栏遮挡

**状态**：未完全修复  
**影响范围**：`lib/features/discovery/`（桌面端嵌入式详情 + 移动端全页详情）  
**首次发现**：2026-03-09

---

## 一、问题描述

打开探索（Discovery）页面时，详情区域的顶部内容会被导航栏/顶部栏遮住，无法正常显示。  
收藏（Library）详情页无此问题，两者显示效果不一致。

---

## 二、根本原因

### 2.1 桌面端（`_buildDesktopBody`）

桌面端采用 **Stack 叠层架构**：

```
Padding(top: MediaQuery.padding.top)         ← 仅处理系统状态栏
  └─ Stack
       ├─ Positioned.fill                    ← 左右面板，从 top:0 开始
       │    ├─ 左侧列表 (padding top: kToolbarHeight ✓)
       │    └─ 右侧详情 (_DesktopDetailBody)
       └─ Positioned(top: 0)                 ← 毛玻璃顶部栏覆盖在上方
            height: kToolbarHeight
```

右侧详情 `_DesktopDetailBody` 是一个独立 widget，它**不知道**外层有多少偏移量，
只能用硬编码的 `top: kToolbarHeight + 24` 来规避遮挡。这导致：

- **文章布局**：临时加了 `kToolbarHeight + 24` padding，在标准桌面分辨率下勉强可用，
  但并非真正的响应式解决方案。
- **画廊/视频布局**：使用 `GalleryLandscapeLayout`（共享组件），该组件内部没有
  `kToolbarHeight` 偏移量，顶部内容**仍然被遮挡**。
- **Web 端**：`MediaQuery.of(context).padding.top` 通常为 0，等式成立，
  但依赖常量 `kToolbarHeight` 而非真实布局高度，脆弱。

### 2.2 移动端（`_FullDetailScaffold`）

原来使用 `extendBodyBehindAppBar: true` + 手动计算 padding，现已去掉该配置，
改为标准 `Scaffold + FrostedAppBar` 布局（与收藏详情页一致）。  
移动端遮挡问题基本已解决。

**但遗留问题**：`FrostedAppBar` 设置了 `scrolledUnderElevation: 0`，
内容上滑时顶部栏与内容区域之间**没有分割线**，视觉上边界不清晰。
收藏详情页的 AppBar 同样如此，但对用户来说仍可感知为问题。

---

## 三、已尝试的修复

| 时间 | 修改内容 | 结果 |
|------|---------|------|
| 2026-03-09 | 将 `kToolbarHeight + 16` 改为 `kToolbarHeight + 40` | 仍遮挡，量不够且未覆盖 gallery |
| 2026-03-09 | 移除 `extendBodyBehindAppBar: true`，mobile 改用标准 Scaffold | 移动端基本修复 |
| 2026-03-09 | 桌面端文章布局两列 ScrollView 均改为 `kToolbarHeight + 24` | 文章布局改善，gallery 未修复 |

---

## 四、正确修复方案

### 方案 A（推荐）：将顶部栏高度传入 `_DesktopDetailBody`

在 `_buildDesktopBody` 中将实际顶部栏高度作为参数传下去，
`_DesktopDetailBody` 用参数驱动 padding，而不是硬编码常量：

```dart
// discovery_page.dart
_DesktopDetailBody(
  item: item,
  topBarHeight: kToolbarHeight,  // 新增参数
)
```

```dart
// discovery_detail_page.dart
class _DesktopDetailBody extends ConsumerStatefulWidget {
  final double topBarHeight;   // 新增
  // ...
}

// 在 SingleChildScrollView 中：
padding: EdgeInsets.fromLTRB(28, widget.topBarHeight + 24, 16, 28),
```

同样在 `GalleryLandscapeLayout` 调用处，通过 `contentPadding` 或类似参数把
`topBarHeight` 传进去，或在外层包一个 `Padding` widget。

### 方案 B：改用 `CustomScrollView + SliverPersistentHeader`

将 Stack 架构重构为标准的 Sliver 架构，让 Flutter 框架自动处理 AppBar 和内容区域的滚动关系，
彻底消除手动计算 padding 的需求。工程量较大，适合后续大重构。

### 顶部栏描边

在 `FrostedAppBar` 中增加 `bottom: PreferredSize` 描边，或在 AppBar 下方插一条 `Divider`，
与桌面端毛玻璃头部的 `BorderSide` 保持视觉一致。

---

## 五、受影响的文件

- `frontend/lib/features/discovery/discovery_page.dart` — `_buildDesktopBody`，frosted header overlay
- `frontend/lib/features/discovery/discovery_detail_page.dart` — `_DesktopDetailBody`，`_FullDetailScaffold`
- `frontend/lib/features/collection/widgets/detail/layout/gallery_landscape_layout.dart` — 共享组件，缺少 top offset 参数
- `frontend/lib/core/widgets/frosted_app_bar.dart` — 无底部描边
