# 已知问题：探索详情页顶部内容被导航栏遮挡

**状态**：已修复
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
移动端遮挡问题已改为标准 `Scaffold + FrostedAppBar` 布局。`FrostedAppBar`
现在通过底部边框提供稳定分割线，不再依赖滚动 elevation 表达边界。

---

## 三、已尝试的修复

| 时间 | 修改内容 | 结果 |
|------|---------|------|
| 2026-03-09 | 将 `kToolbarHeight + 16` 改为 `kToolbarHeight + 40` | 仍遮挡，量不够且未覆盖 gallery |
| 2026-03-09 | 移除 `extendBodyBehindAppBar: true`，mobile 改用标准 Scaffold | 移动端基本修复 |
| 2026-03-09 | 桌面端文章布局两列 ScrollView 均改为 `kToolbarHeight + 24` | 文章布局改善，gallery 未修复 |
| 2026-06-05 | 嵌入式详情由外层传入顶部栏高度，文章/画廊布局统一避让；`FrostedAppBar` 增加底部边框 | 已修复当前遮挡和边界不清晰问题 |

---

## 四、当前实现

桌面端 `_buildDesktopBody` 将顶部栏高度传入嵌入式 `DiscoveryDetailPage`，
`_DesktopDetailBody` 再用 `topInset` 驱动文章布局 padding，并在画廊/视频布局外层增加同等
top padding。这样右侧详情不再硬编码外层结构，也覆盖了 `GalleryLandscapeLayout`。

通用 `FrostedAppBar` 现在直接使用 `shape` 绘制底部 0.5px 边框，保持 preferred size 不变。

如果未来要进一步降低手动布局复杂度，可以把桌面 Discovery 重构为
`CustomScrollView + SliverPersistentHeader`，但这不再是当前缺陷修复的必要条件。

---

## 五、受影响的文件

- `frontend/lib/features/discovery/discovery_page.dart` — `_buildDesktopBody`，frosted header overlay
- `frontend/lib/features/discovery/discovery_detail_page.dart` — `_DesktopDetailBody`，`_FullDetailScaffold`
- `frontend/lib/features/collection/widgets/detail/layout/gallery_landscape_layout.dart` — 共享组件，缺少 top offset 参数
- `frontend/lib/core/widgets/frosted_app_bar.dart` — 无底部描边
