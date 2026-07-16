# Gmail 自适应界面组织参考

## 文档状态

active

## 适用范围

- 平台：Android、平板和桌面宽窗口下的 Flutter 界面设计参考。
- 模块：Root Shell、动态/收藏列表、内容详情、搜索、导航和全局状态反馈。
- 场景：为 VaultStream 提取 Gmail 的信息架构和自适应布局经验。

## 背景

仓库曾在本地保存一份 Gmail APK 及 apktool、jadx 多份反编译结果，希望研究 Gmail 与个人信息流/知识库在“高密度内容浏览、搜索、列表—详情和跨设备布局”方面的共通点。

反编译目录包含约 23 万个文件、1.39 GB 数据。大部分 Java/Kotlin 符号已经混淆，重复解包结果和三方依赖远多于可复用信息，不适合作为长期参考目录。本文在删除反编译产物前，保留能够从资源限定符、布局 XML、菜单 XML、Manifest 和少量可辨识类中直接验证的设计结论。

本文只记录界面组织经验，不代表 Gmail 当前公开设计规范，也不建议复制其代码、资源、图标或具体尺寸。

## 证据范围

本次阅读的主要反编译资源包括：

- `layout/one_pane_activity_with_navigation_view.xml`
- `layout/large_screen_root_layout_with_navigation_view.xml`
- `layout/large_screen_sliding_pane_root_layout_with_navigation_view.xml`
- `layout/large_screen_two_pane_content.xml`
- `layout/conversation_view_pane_draggable_divider.xml`
- `layout/hub_navigation_rail.xml`
- `layout/navigation_rail_header.xml`
- `layout/open_search_bar_with_animation.xml`
- `layout/expressive_search_bar.xml`
- `layout/conversation_item_view.xml`
- `layout/conversation_item_view_compact.xml`
- `layout-sw600dp/bento_layout.xml`
- `menu/conversation_actions*.xml`
- `navigation/*_pane_nav_graph.xml`
- `TabletTwoPaneLayout.java`
- `LargeScreenSlidingPaneLayout.java`
- `manifest_components.csv`

反编译目录已经删除，因此上述路径只用于说明证据来源，不能作为持续链接或实现依赖。

## 一、布局不是“手机/平板”二选一

资源目录同时存在：

- `layout/`
- `layout-land/`
- `layout-sw600dp/`
- `layout-sw600dp-land/`
- `layout-w640dp/`
- `layout-w840dp-v34/`
- 对应的 `values-w600dp`、`values-w840dp` 等尺寸资源

这说明其布局选择不仅依赖方向，还结合最小宽度、当前窗口宽度、可用高度和系统版本。代码中又同时存在单栏、滑动 pane 和固定双栏容器，进一步说明中等宽度不是简单把手机布局拉宽。

对 VaultStream 的结论：

- Flutter 页面应以 `LayoutBuilder`/实际 constraints 为主，而不是只判断 `Orientation` 或设备名称。
- Compact、Medium、Expanded 是布局能力变化，不只是 padding 变化。
- 手机横屏需要同时检查高度，不能看到宽度超过某值就强行显示完整双栏。
- 在可折叠/可调整窗口环境中，详情 pane 应能够滑入、并排或独占，而不是维护互不关联的页面副本。

## 二、三种内容外壳

### 单栏外壳

`one_pane_activity_with_navigation_view.xml` 使用：

- `DrawerLayout` 作为抽屉导航容器。
- 一个完整内容 pane。
- 顶部搜索/工具区域。
- 底部导航占位。
- 浮动主操作和 Snackbar/调查等临时 surface。

列表与详情共享同一个主要内容区域，进入详情时由内容容器承担页面切换，而不是把详情硬塞到列表下方。

VaultStream 可借鉴：

- Compact 下 Root Shell 只保留底部主导航。
- 点击动态/收藏内容后进入完整 Detail Shell。
- 返回时恢复列表滚动、筛选和选中状态。
- 全局迷你播放器和 Snackbar 使用稳定锚点，不能临时覆盖底部导航。

### 滑动双栏外壳

反编译结果存在 `large_screen_sliding_pane_root_layout_with_navigation_view.xml` 和 `LargeScreenSlidingPaneLayout`。它允许列表与详情在窗口能力变化时切换可见性，并带有 pane 之间的动画，而不是始终固定为 50/50。

可辨识代码还显示：

- 布局维护列表 pane、详情 pane 和辅助 pane 的显示状态。
- 状态变化会触发 pane 平移/淡出动画。
- 动画时长集中处理，而不是由每个子页面分别控制。
- 在更宽窗口下，列表 pane 的目标宽度并非无限增长；代码出现约 560dp 上限与窗口比例结合的计算。

VaultStream 可借鉴：

- Medium 宽度使用 adaptive list-detail：未选择内容时列表占主区域；选择后详情滑入或成为主要 pane。
- 不把中等宽度机械设为固定双栏，避免两边都太窄。
- pane 状态由 Shell/路由管理，列表和详情 renderer 不自行决定全局布局。
- 动画表达“同一对象从列表进入详情”，不引入残留 Hero 图层。

### 固定双栏外壳

`large_screen_two_pane_content.xml` 明确把 `conversation_list_place_holder` 与 `conversation_view_pane` 放入同一个 `TabletTwoPaneLayout`；详情 pane 中又区分：

- 无选择空态。
- 正常内容 pager。
- 顶部详情 toolbar。
- 可替换的 miscellaneous/辅助 pane。
- 使用 `colorSurfaceVariant` 的窄分隔区域。

VaultStream 可借鉴：

- Expanded 下动态、收藏库和通知中心使用列表—详情结构。
- 详情没有选择时显示真正有用的空态，而不是默认打开第一项造成误操作。
- 主详情与字幕、目录、Agent 证据或任务诊断等 supporting pane 分开。
- 分隔主要靠 surface tonal difference 和细分隔，不用每个区域套厚边框/阴影卡片。
- 超宽窗口限制列表和正文宽度，多余空间用于 supporting pane 或留白。

## 三、导航层级与主操作

资源中同时出现底部导航、抽屉、Navigation Rail 和带主操作的 rail header。`navigation_rail_header.xml` 将菜单入口和 FAB 放在 rail 顶部；rail 菜单本身居中。

其价值不在于“所有页面都放一个 FAB”，而在于：

- 导航承担目的地切换。
- 一个稳定的高频创建动作可以和导航共处，但视觉上与目的地分开。
- 大屏导航不需要把所有工具和设置都变成一级目的地。

VaultStream 应保持：

- Root Shell 主目的地只保留动态、收藏库、自动化。
- 搜索、通知、设置和当前播放属于全局工具，不与主目的地平铺。
- “保存内容”可以作为稳定主操作，但不能在每个页面重复出现不同版本。
- Agent 是上下文能力；复杂任务可进入工作台，但不必永久占据主导航。

## 四、搜索是应用结构的一部分

Gmail 的搜索资源不是普通页面中的一个孤立输入框：

- 搜索栏位于 `AppBarLayout`。
- 使用 `scroll|enterAlways|snap` 与内容滚动协调。
- 搜索栏下方可以出现筛选 chips。
- 加载进度以一条低高度进度条集成在同一区域。
- 选择模式和促销/辅助入口使用延迟加载的 `ViewStub`，不常驻占位。
- `expressive_search_bar.xml` 通过 M3 Expressive 主题覆盖升级外观，但仍保留同一结构。

VaultStream 可借鉴：

- 动态和收藏库共用一致的搜索心智，但结果域和默认过滤可以不同。
- 搜索栏只承载查询和少数高价值入口；复杂过滤进入 chips + sheet/pane。
- 当前过滤条件必须可见且可快速清除。
- 语义搜索/RAG 作为搜索增强结果，不把搜索页直接变成纯聊天页。
- 加载、离线和索引状态靠近搜索上下文显示，不在页面其他位置重复一套状态卡。

## 五、高密度列表的信息层级

`conversation_item_view.xml` 的主要层级可以识别为：

1. 左侧联系人/来源图像。
2. 第一行发送者与右侧时间。
3. 第二行主题。
4. 第三行摘要片段。
5. 可选附件、标签、排序理由和预览 carousel。
6. 星标作为独立快捷动作。

同时存在单独的 `conversation_item_view_compact.xml`，说明紧凑密度不是通过在同一布局里不断隐藏控件临时实现，而是有清晰的结构取舍。

VaultStream 的列表卡应据此收敛：

- 第一视觉层：标题/主体身份。
- 第二层：作者、来源和时间。
- 第三层：一段摘要或关键变化。
- 媒体预览只在确实提高判断效率时出现。
- 标签、AI 理由、统计和处理状态不能全部平铺在每张卡上。
- 普通浏览态只保留一个真正高频快捷动作；其他动作进入选择模式、滑动动作或菜单。
- 动态卡、收藏卡、事件更新卡可以共享信息节奏，但不能强行共用同一万能卡片。

## 六、详情动作分层

Gmail 为普通详情和 two-pane 详情分别定义动作菜单。主工具栏保留少量高频动作，overflow 又按语义分组：

- organize：移动、标签、重要性。
- do later：稍后、任务。
- misc：退订、静音、打印、查看原始内容。
- abuse：举报和垃圾信息。

two-pane 不是简单复用同一菜单：在列表仍可见时，刷新、撰写、已读/未读等上下文动作会调整。

VaultStream 可借鉴：

- 详情顶部只显示返回/关闭、收藏状态和一两个核心动作。
- 重新解析、重新索引、媒体归档、调试 payload 等进入“处理与诊断”区域，不与阅读动作平铺。
- 标签/加入事件/稍后等属于内容组织动作，可以分组。
- 删除、外部分发等高风险或副作用动作独立分组并明确确认。
- 大屏 list-detail 下的动作必须考虑列表仍可见的上下文，不机械复制手机 AppBar。

## 七、临时状态有稳定位置

`activity_main_root.xml` 中可以看到：

- 离线 banner。
- 顶部 loading indicator。
- 内容 frame。
- Snackbar anchor。
- tooltip overlay。
- ghost loading container。

这些状态是 Shell 级容器的一部分，而不是由每个列表项自行堆叠。

VaultStream 应建立：

- 全局连接/后端不可用状态。
- 页面级加载与局部增量加载的不同表现。
- 通知中心承载长任务；Snackbar 只承载即时、可撤销反馈。
- 全局播放器、底部导航、Snackbar 和系统手势区域之间的统一 inset/anchor 规则。
- 空态、错误态和无选择状态必须保持布局稳定。

## 八、账户菜单的适配方式

普通 `bento_layout.xml` 只是全屏内容容器；`layout-sw600dp/bento_layout.xml` 则增加 scrim，并将内容放入有固定宽度、边距和底部间距的 `MaterialCardView`。

这说明同一低频账户/工具内容在窄屏可以作为完整 surface，在宽屏则更适合作为受限宽度的浮层，而不是无限拉伸。

VaultStream 可用于：

- 账号快速切换、当前服务器/工作空间信息使用小型全局 surface。
- 完整账号连接、Cookie 修复和权限配置仍进入设置 Section Shell。
- 宽屏 dialog/menu/sheet 必须限制宽度；不能把手机底部 sheet 拉成全宽桌面面板。

## 九、不应照搬的部分

- Gmail 的邮件专属动作、标签体系和“撰写”心智不能直接套到知识库。
- 反编译资源包含 Gmail、Chat、Meet 和大量公共库，文件名存在跨产品混杂。
- 部分布局来自旧 AppCompat/legacy mail 代码，并不代表最新 M3 Expressive 最佳实践。
- Java 符号大量混淆，只能验证 pane 状态、动画和布局关系，不能可靠还原完整架构。
- 未进行 Gmail 真机交互和截图对照，因此不在本文记录具体视觉尺寸、颜色或运行时行为。
- 不复制 Gmail 图标、drawable、文案、代码或私有资源。

## 十、对 VaultStream 的优先落地点

1. Root Shell：三个主目的地 + 全局搜索/通知/设置/播放状态。
2. 动态和收藏库：Compact 全屏详情、Medium 滑动 list-detail、Expanded 固定 list-detail。
3. 搜索：SearchBar + 可见过滤 chips + 自适应筛选 surface。
4. 内容卡：重建标题、来源/时间、摘要、媒体预览和快捷动作的优先级。
5. 内容详情：阅读动作、内容组织动作、处理诊断动作和危险动作分层。
6. 全局状态：离线、任务、Snackbar、播放器和导航的统一锚点。
7. 设置与账号：窄屏整页、宽屏受限 surface/Section Shell，而不是统一全屏表单。

## 与代码的关系

- 当前导航：`../../frontend/navigation.md`
- 当前内容详情：`../../frontend/pages/content-detail.md`
- 当前收藏库：`../../frontend/pages/collection.md`
- 当前动态页：`../../frontend/pages/dashboard.md`
- 当前设置：`../../frontend/pages/settings.md`
- 现有前端 IA 计划：`../../plans/2026-06-10-frontend-information-architecture-redesign.plan.md`

本文是知识资料，不直接授权 UI 修改。实施时先建立对应 plan，读取当前页面文档并以 Flutter 代码和多断点运行结果为事实来源。

## 已知限制

- 证据快照来自 2026-06-10 本地 APK 反编译结果，具体 Gmail 版本和当前在线产品可能已经变化。
- 原始 APK 和反编译目录已在仓库卫生清理中删除，本文是保留的可维护替代物。
- 文中对混淆代码的解释只保留能够与布局资源相互印证的部分。
