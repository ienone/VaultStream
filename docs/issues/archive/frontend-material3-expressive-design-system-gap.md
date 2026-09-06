# 前端 Material 3 Expressive 设计系统落地不足

## 状态

archived

## 修复前现象

VaultStream 前端已经具备 Material 3 基础：`ThemeData(useMaterial3: true)`、`ColorScheme.fromSeed`、系统动态色、深浅主题、`NavigationBar` / `NavigationRail`、`SearchAnchor`、`SegmentedButton`、`Chip`、`FilledButton` 等都已使用。

更大的差距不是“有没有 Material 3”，而是：全局 token 已经存在，但页面级实现仍大量局部硬编码颜色、圆角、阴影、动效和断点，导致设计系统没有稳定落地为一套可复用的 expressive 语言。

当前可观察到的问题包括：

- `AppSpacing`、`AppRadius`、`AppMotion` 已存在，但页面中仍有大量 `BorderRadius.circular(数字)`、`Colors.*`、局部 `duration` / `curve`。
- 多数卡片已使用 `surfaceContainer*`，但部分收藏卡 hover、详情 hero、媒体/图表区域仍使用装饰性 `BoxShadow`。
- 动效来源分散，`flutter_animate`、`AnimatedSwitcher`、`AnimatedScale`、`AnimatedSize`、自定义 curve 混用。
- 响应式布局已有 `ResponsiveLayout`；Root Shell、自动化和搜索已改用统一窗口类别，`features/` 与 `layout/` 不再自行写 800/900/1200 布局断点。
- `FrostedAppBar` 被广泛使用，但容易形成“毛玻璃 = expressive”的误区，普通工具页也可能偏离 MD3 tonal app bar 逻辑。
- 页面局部排版仍有随手 `fontSize`、`letterSpacing`、负字距等写法，没有全部回到 TextTheme 类型阶梯。

## 影响范围

- 页面：动态页、收藏库、内容详情页、自动化页、设置页、Agent 工作台。
- 组件：AppShell、FrostedAppBar、收藏卡片、详情 hero、设置组件、Agent 消息/确认 surface、图表/媒体区域。
- 主题：`AppSpacing`、`AppRadius`、`AppMotion`、`ColorScheme`、TextTheme、响应式断点。
- 用户影响：整体已经“像 Material 3”，但不同页面的间距、半径、阴影、动效和层级语言不稳定，产品气质不统一，也增加后续 UI 重构成本。

## 复现方式

1. 搜索局部圆角：`rg -n "BorderRadius\.circular\([0-9]" frontend/lib`。
2. 搜索局部颜色：`rg -n "Colors\." frontend/lib`。
3. 搜索局部动效：`rg -n "Duration\(|Curves\.|flutter_animate|AnimatedSwitcher|AnimatedScale|AnimatedSize" frontend/lib`。
4. 搜索局部断点：`rg -n "800|900|1200|desktopBreakpoint|tabletBreakpoint" frontend/lib/features frontend/lib/layout`。
5. 对比 `frontend/lib/theme/design_tokens.dart` 中已有 token，检查页面是否绕过共享 token 自行定义视觉参数。

## 根因分析

- 项目已引入 Material 3 和基础 token，但缺少“页面实现必须使用语义 token / shared surface / shared motion”的执行约束。
- 页面开发时为了快速实现视觉效果，在局部直接调颜色、圆角、阴影、动效和断点，形成“看起来像 M3”的一次性样式。
- MD3 Expressive 的核心不是给聚合页加更多视觉装饰，而是让信息架构、adaptive layout、surface 层级、内容感知色彩和 motion 共同服务核心任务；当前 IA 和页面职责仍在调整中，进一步放大了设计系统不一致。

## 关联代码

- `frontend/lib/main.dart`
- `frontend/lib/theme/app_theme.dart`
- `frontend/lib/theme/design_tokens.dart`
- `frontend/lib/core/layout/responsive_layout.dart`
- `frontend/lib/core/widgets/frosted_app_bar.dart`
- `frontend/lib/layout/app_shell.dart`
- `frontend/lib/features/dashboard/dashboard_page.dart`
- `frontend/lib/features/automation/automation_page.dart`
- `frontend/lib/features/collection/widgets/list/content_card.dart`
- `frontend/lib/features/collection/widgets/list/collection_card_preview.dart`
- `frontend/lib/features/collection/content_detail_page.dart`
- `frontend/lib/features/settings/presentation/widgets/setting_components.dart`
- `frontend/lib/features/agent/agent_page.dart`

## 关联文档

- `../../frontend/README.md`
- `../../frontend/navigation.md`
- `../../frontend/components/navigation-shell.md`
- `../../frontend/pages/collection.md`
- `../../frontend/pages/content-detail.md`
- `../../frontend/pages/automation.md`
- `../../frontend/pages/settings.md`
- `../../plans/2026-06-10-frontend-information-architecture-redesign.plan.md`
- `frontend-dashboard-scope-creep.md`
- `frontend-automation-page-responsibility-overload.md`
- `frontend-navigation-utility-group-layout.md`

## 修复建议

### 1. 设计 token 清账

- 把常用 surface、容器、状态、半径、间距、运动节奏收敛为语义 token。
- 减少页面直接写 `BorderRadius.circular(数字)`、`Colors.*`、局部 `Duration` / `Curve`。
- 在 `AppSpacing`、`AppRadius`、`AppMotion` 基础上增加更语义化的页面级 token，例如 `cardRadius`、`mediaRadius`、`paneRadius`、`stateChangeDuration`、`containerTransformDuration`。

### 2. 减少阴影，更多使用 tonal surface

- MD3 更依赖 `surfaceContainer*` 层级表达深度。
- 只保留确实需要浮起反馈的少量 shadow，例如拖拽、菜单、悬浮层或明确 hover feedback。
- 收藏卡 hover、详情 hero、媒体/图表区域优先转为 tonal elevation / `outlineVariant` / container 层级表达。

### 3. 统一 motion 语言

- 将 `AppMotion` 扩展为语义动效：`emphasizedEnter`、`emphasizedExit`、`containerTransform`、`stateChange`、`listItemEnter`。
- 页面不直接选择 curve 和 duration，而是引用语义动效。
- 收藏卡到正文、导航分支切换、筛选面板展开、通知中心打开等关键场景应有统一 motion 规则。

### 4. 用 canonical / adaptive layout 替代零散断点

- 在 `ResponsiveLayout` 中形成 compact / medium / expanded 的正式布局模型。
- 对动态流、收藏库、自动化、设置、通知中心分别定义 list-detail、supporting pane、side sheet、full screen detail 的断点策略。
- 自动化页已有规则侧栏 + 内容区的雏形，应提升为正式 list-detail / supporting-pane 模式，而不是局部 360px 规则侧栏写法。

### 5. 收藏与详情页作为 Expressive 标杆

- 收藏页已有 masonry grid、搜索、过滤容器转场、扩展 FAB、Hero 到详情、内容色生成局部主题，适合作为 content-aware expressive 示例页。
- 修复已知 Hero 问题后，封面主色应从局部 `accent.withAlpha` 用法转为生成局部 `ColorScheme`，再使用 `primaryContainer`、`onPrimaryContainer`、`surfaceContainer*` 等语义颜色。
- 卡片到正文转场应遵循前端 IA plan 中的单一 shared container 设计；旧 Hero/透明详情叠层问题已经归档。

### 6. 设置与 Agent surface 表达升级

- 设置页组件化程度较好，但仍偏列表表单。应结合 Section Shell，用更清晰的二级导航、当前内容区和分组 surface 表达层级。
- Agent 页已用统一窗口类别组织 conversation surface 与会话 supporting pane，并将确认、错误和工具过程收敛为语义 surface；后续仍需真实模型、辅助技术和动态色人工验收。

### 7. 明确 FrostedAppBar 的适用范围

- 保留毛玻璃作为产品特征，但不要把“毛玻璃”等同于 expressive。
- 内容沉浸页、媒体页、需要透出背景层级的页面可以使用毛玻璃。
- 普通工具页优先使用 standard / medium top app bar + scrolledUnder tonal elevation。

### 8. 排版回到类型阶梯

- 全局字体使用 Lexend / Inter 可以保留。
- 页面级标题、section title、label、正文应使用 TextTheme 角色扩展。
- 避免页面随手写 `fontSize`、`letterSpacing: -0.5` 等局部排版参数。

## 优先级建议

1. 先做设计 token 清账：颜色、半径、spacing、motion 从页面局部收敛到主题和共享组件。
2. 再做导航与 IA：动态页减负，自动化拆清楚，utility 入口分组规范化。
3. 然后把收藏/详情页作为示范页，完成 content-aware color、container transform、adaptive detail layout。
4. 最后统一设置、Agent、自动化的复杂 surface，让 dialog、bottom sheet、side pane、fullscreen dialog 有清晰使用规则。

## 当前进展

- Root Shell 已用 `WindowWidthClass` 决定底部导航、NavigationRail 和 extended rail，删除原独立 800px 主导航断点；840 边界及短横屏均有 widget 回归。
- 自动化总览、分发 list-detail 和处理阶段列数按组件自身可用宽度映射同一窗口类别，不再各自写 900px 判断。
- 全局搜索的双列结果也按结果区自身可用宽度和高度选择 supporting pane，不再读取整屏宽度或写局部 900px 判断。
- 规则详情系统返回先回分发域，其他自动化分区先回总览，避免统一断点迁移后破坏 Detail Shell 层级。
- `ResponsiveLayout` 中与 `AppPane` 重复且无调用方的宽度常量已删除，布局类别与尺寸 token 不再双份定义。
- 自动化总览与规则编辑面已移除局部圆角、动画时长/曲线和手写字号，统一使用 `AppShape`、`AppMotion`、`AppPane` 与 `TextTheme`；`AppShape.sheetBorder` 和 `AppMotion.listItemStagger` 补齐了页面实际需要的语义 token。
- Agent 页已删除私有 920px 断点，按正文区域的统一宽度/高度类别切换会话 supporting pane 与横向会话栏；正文、错误和输入区统一限宽，短横屏不会强行并排。消息、工具结果、待确认和错误 surface 使用 `AppShape` 与 `ColorScheme` 语义，滚动跟随使用 `AppMotion`，并覆盖 839/840 边界和 1200×450 短横屏。
- 设置 Section Shell 已按页面自身可用尺寸使用同一窗口宽度/高度类别：`expanded` 以上显示分区 supporting pane，compact/medium 与短横屏使用分区列表 → 全屏详情。侧栏、工作区和表单最大宽度统一进入 `AppPane`；设置页与共享 `SettingGroup`、`SettingTile`、`AdaptiveTaskSurface`、展开项和加载态已移除局部数字圆角、640px 弹层断点及毫秒动效，改用 `AppShape` / `AppMotion`，并覆盖 839/840 边界、1200×450 短横屏和 compact 深链。
- 详情媒体网格已移除局部 300/400ms 翻页与选中动效、8/12/13/16/20 圆角、固定字号以及选中缩略图阴影，改用共享 motion、shape、TextTheme 和 inverse/tonal surface；横向翻页、九宫格溢出、Hero 与统一媒体来源专项保持通过。
- 收藏详情的富文本、Markdown、统计、骨架与全屏图集已继续收敛到共享 shape、motion、TextTheme 和 ColorScheme；删除了只按 brightness 缓存 Markdown 样式的错误实现，避免同亮度动态色/内容主题切换继续显示旧颜色。详情页及其 `widgets/detail` 当前已无本 issue 复现式中的数字圆角、局部毫秒动效、固定状态色、固定字号或负字距命中。
- 动态页遗留的 Bot 状态、系统健康、探索饼图和 donut 卡片均无代码/测试/文档调用方，且与当前“近期信息流”职责冲突，已直接删除而不是为死代码补 token；动态领域剩余的 250ms 只用于后台事件去抖，不属于视觉 motion。
- 自动化队列、收藏同步、Bot 编辑、设置业务分区、收藏筛选、动态内容块、引导与认证页面已完成后续清账：页面形状、视觉 motion、状态色和排版分别回到 `AppShape`、`AppMotion`、`ColorScheme` 与 `TextTheme`，重复平台徽标改为共享组件。
- 普通工具页的 `FrostedAppBar` 已全部替换为标准 Material 3 `AppBar`，无调用方的毛玻璃实现已删除；沉浸媒体仍保留必要的黑白遮罩，二维码仍保留必要的黑白对比，拖拽代理仍保留浮起阴影。
- `features/` 与 `layout/` 静态扫描已无数字圆角、手写字号或字距；剩余毫秒值是请求去抖或播放位置数据，不是视觉 motion。Flutter analyze 无问题，完整测试 199 passed。代码问题已关闭；真实动态色设备、减少动效、键盘全链路和 TalkBack/VoiceOver 仍属于人工验收范围，不由 widget 测试替代。

## 验证方式

- 静态检查：统计 `BorderRadius.circular(数字)`、`Colors.*`、局部 `Duration` / `Curve` 命中数量，并在重构后持续下降。
- UI 回归：桌面、平板、手机竖屏、手机横屏下检查动态页、收藏库、详情页、自动化、设置、通知中心。
- 主题检查：浅色、深色、系统动态色下 surface 层级、文本对比度和状态色可读。
- 动效检查：导航、筛选、卡片到详情、列表到详情、通知中心打开/关闭均使用语义 motion。
- 可访问性：检查文本层级、触控区域、颜色对比和减少动效偏好。

## 参考

- Flutter API：`ThemeData.useMaterial3`。该配置会影响颜色、排版、形状和组件默认值。
- Flutter API：`ColorScheme.fromSeed`。该 API 会从 seed 生成符合 Material 3 色彩系统和对比要求的 tonal palettes。
