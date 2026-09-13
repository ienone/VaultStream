# 界面层级与横竖屏整改交付（2026-09-07）

本轮在现有共享工作区完成，未创建 worktree；用户明确授权把本轮及此前全部未提交变更按领域提交并推送。前一轮 R1–R8、A1–A5、U1–U12 的逐项结果见 [原审查处理记录](2026-09-06-implementation-review.md)。本页只补充此次整改，运行数据库与凭据不进入 Git。

## 参考源码与实际取舍

- [Animeko 导航尺寸决策](https://github.com/open-ani/animeko/blob/073f035dac1b7b23ad509bd1a88bf0b201d3e94d/app/shared/ui-adaptive/src/commonMain/kotlin/ui/adaptive/navigation/AniNavigationSuiteScaffold.kt#L151)：高度紧凑且宽度达到 medium 时使用 Rail。VaultStream 沿用自身窗口类别，短横屏使用窄栏、省略标签；原生 Rail 滚动处理极短窗口，不另造导航系统。
- [Animeko 设置主从布局](https://github.com/open-ani/animeko/blob/073f035dac1b7b23ad509bd1a88bf0b201d3e94d/app/shared/ui-settings/src/commonMain/kotlin/ui/settings/SettingsScreen.kt#L435)：双栏才补默认详情；标题尺寸看高度，分别处理 pane 滚动和 insets。本轮缩短紧凑高度顶栏，已显示详情在缩窄时保持，单一设置表面承接实际内容。
- [Mihon 主导航](https://github.com/mihonapp/mihon/blob/3a64c8d65cf9fe44346a5994642db440c73aa70a/app/src/main/java/eu/kanade/tachiyomi/ui/home/HomeScreen.kt#L83)与[设置页](https://github.com/mihonapp/mihon/blob/3a64c8d65cf9fe44346a5994642db440c73aa70a/app/src/main/java/eu/kanade/tachiyomi/ui/setting/SettingsScreen.kt#L35)：导航随设备空间变化；窄屏先退出详情内部导航，宽屏分为列表与正文并消费横向安全区。VaultStream 保持既有 GoRouter 返回路径和状态，不照搬 Compose 容器或新增依赖。

## 完成的改动

- 自动化首层三张圆角卡改成普通入口列表，只保留领域名称、真实计数/状态与进入动作。桌面同样限宽，不把三个入口放大填屏。
- 解析、媒体归档、摘要和索引去掉逐阶段边框卡，保留真实阶段与开关。读取失败明确显示失败，不无限伪装成“正在读取”。
- 分发短横屏将模式与队列/历史切换放在同一行，收紧状态栏；窄屏规则直接选择，保留编辑与新建。规则列表去掉卡片、展开动画和重复详情，删除整份 `rule_config_panel.dart`，编辑统一进入现有规则页。
- 推送凭证从 Card + Stepper 改为可折叠的直接表单，删除没有接入保存的旧管理员输入框，保留真实管理员、白名单和黑名单。Token 遮蔽。Telegram 停止是正常状态，显示启动；运行中显示停止/重启。QQ 离线和状态读取失败准确表达，不展示猜测配置状态的红框和四个常驻按钮。
- 设置单双栏共享同一个内容子树；桌面默认详情缩窄后保持。连续表面使用 Material，修复 ColoredBox 遮挡 ListTile 水波纹。横向安全区、短顶栏和可滚动 Rail 由共享布局处理。
- 保存弹层的最大高度在当前尺寸重新计算，修复横屏打开再转竖屏仍受旧高度限制；保留输入、滚动和键盘避让。
- 实际浏览器运行暴露 SSE 心跳 300 秒与客户端 90 秒超时不一致，且 Web 关闭 HTTP client 不保证取消响应流。服务端改为 30 秒心跳，客户端使用现有 http 的 AbortableRequest；替换/销毁连接取消旧流，迟到事件与错误不再驱动当前连接。

保留内容卡、媒体资产、队列对象、编辑表单和独立弹层，因为它们承载可识别业务对象或操作。人工编辑保护、任务持久化、审批权限、规则与真实管理员配置均保留；没有用删功能换取减行数。

## 验证

- 最终保留回归：后端 39 项通过；前端 6 项通过；Flutter analyze 无问题，Flutter Web JavaScript 构建通过，`git diff --check` 通过。
- 临时布局验收 6 项：设置来源/返回与四尺寸状态、极短 Rail、导航状态、保存弹层旋转和 320px 键盘 inset。另有真实推送表单四尺寸保持 1 项、处理阶段读取失败 1 项、SSE 替换连接 1 项；全部通过后删除脚本。
- Chrome 使用实验库的只读 API，后台 lifecycle worker 停止。检查 390×844、844×390、768×1024、1200×900 的导航与代表页面；实际规则筛选、滚动、表单展开、输入与尺寸切换。输入验收改用当前语义节点的键盘事件，排除旧节点/DOM 填值仅改变覆盖层的误判。
- 真实 SSE 连续运行 90 秒，在约 30/60/90 秒收到心跳；随后事件健康、设置与分发统计均返回 200。临时替换测试单独验证 8 次旧请求中止及迟到错误，不把模拟连接测试称为真实网络链路。
- 依赖声明、OpenAPI 文档清单、SQLite schema gate 通过；pip-audit 无已知漏洞；Bandit 高严重度且高置信度门槛通过。对变更文本进行了凭据模式检查，运行数据库和临时验收脚本排除。

没有触发真实 Bot 启停、发送、同步、账号操作或保存凭证。原生设备旋转、软键盘、后台生命周期、折叠屏铰链与长时间断网恢复没有实机验收；Wasm 仍受现有 secure storage 依赖限制。网页视口与模拟 inset 不能替代这些边界。

## 前后截图

自动化首层整改前：

![此前手机自动化](/Users/ienone/coding/vaultstream/docs/issues/assets/2026-09-07-navigation-settings/automation-390.png)

本次手机与横屏：

![手机自动化](/Users/ienone/coding/vaultstream/docs/issues/assets/2026-09-07-flat-layout/automation-390.png)
![横屏自动化](/Users/ienone/coding/vaultstream/docs/issues/assets/2026-09-07-flat-layout/automation-844.png)

平板与桌面：

![平板自动化](/Users/ienone/coding/vaultstream/docs/issues/assets/2026-09-07-flat-layout/automation-768.png)
![桌面自动化](/Users/ienone/coding/vaultstream/docs/issues/assets/2026-09-07-flat-layout/automation-1200.png)

分发横屏整改前后：

![此前分发横屏](/Users/ienone/coding/vaultstream/docs/issues/assets/2026-09-06-implementation-review/after/distribution-844.png)
![本次分发横屏](/Users/ienone/coding/vaultstream/docs/issues/assets/2026-09-07-flat-layout/distribution-844.png)

阶段与推送表单（管理员数字为未提交的示例草稿）：

![手机处理阶段](/Users/ienone/coding/vaultstream/docs/issues/assets/2026-09-07-flat-layout/processing-390.png)
![桌面处理阶段](/Users/ienone/coding/vaultstream/docs/issues/assets/2026-09-07-flat-layout/processing-1200.png)
![手机推送表单](/Users/ienone/coding/vaultstream/docs/issues/assets/2026-09-07-flat-layout/push-form-390.png)
![横屏推送表单](/Users/ienone/coding/vaultstream/docs/issues/assets/2026-09-07-flat-layout/push-form-844.png)
![桌面推送表单](/Users/ienone/coding/vaultstream/docs/issues/assets/2026-09-07-flat-layout/push-form-1200.png)

## 内容视图横竖屏补充

进一步读取两项目的内容布局实现，而不止参考导航外观：

- [Animeko AdaptivePlayerScreenLayout](https://github.com/open-ani/animeko/blob/073f035dac1b7b23ad509bd1a88bf0b201d3e94d/app/shared/ui-episode/src/commonMain/kotlin/ui/episode/AdaptivePlayerScreenLayout.kt#L146) 使用 `movableContentOf` 在不同布局中复用播放器，并分别组织紧凑、横向和剧场布局。VaultStream 复用自身播放控制器，通过稳定的子树身份移动画面及信息列表；此次没有新增剧场模式。
- [Mihon TwoPanelBox](https://github.com/mihonapp/mihon/blob/3a64c8d65cf9fe44346a5994642db440c73aa70a/presentation-core/src/main/java/tachiyomi/presentation/core/components/TwoPanelBox.kt#L27) 从可用宽度扣除安全区，限制一侧宽度后把余量交给另一侧。[MangaScreen](https://github.com/mihonapp/mihon/blob/3a64c8d65cf9fe44346a5994642db440c73aa70a/app/src/main/java/eu/kanade/presentation/manga/MangaScreen.kt#L137) 分别组织小、大屏内容。VaultStream 据此按内容区约束决定布局，保留既有窗口类别，不复制 Compose 容器或断点。

本次实现：

- 收藏库取消“手机横屏强制单列”，按实际内容宽度和字号决定列数。844×390 普通字号显示两列；放大字号时自动减少列数。骨架同步列数和紧凑内容卡高度。
- 播放器在足够宽的短横屏和桌面将视频、信息并排；竖屏画面在上，标题、设置、章节、书签和队列在下面滚动。视频不会随信息一起滚出视野，横屏信息栏独立滚动；大字号空间不足时恢复单列。
- 倍速改为下拉，定时停止改为菜单，显示当前值；删除外围设置卡、重复标题、常驻选项组和空书签说明。书签和队列使用直接列表，不再套分组卡；书签入口收成有工具提示的按钮。队列保留整行点击播放、移除和排序，删除重复的播放按钮与类型图标。保留真正的书签、章节及播放队列。删除声音模式中的重复说明与装饰图标，实际播放/暂停状态由控制按钮表达。
- 动态、收藏库（含多选）、Agent 和播放器的紧凑高度顶栏使用 48dp。进度时间移到进度条下方，避免大字号挤压进度条；媒体失败区允许滚动到重试操作。

收藏库横屏前后：

![此前收藏库横屏](/Users/ienone/coding/vaultstream/docs/issues/assets/2026-09-06-implementation-review/after/collection-844.png)
![本次收藏库横屏](/Users/ienone/coding/vaultstream/docs/issues/assets/2026-09-07-responsive-content/collection-844.png)

本次手机、平板和桌面收藏库：

![手机收藏库](/Users/ienone/coding/vaultstream/docs/issues/assets/2026-09-07-responsive-content/collection-390.png)
![平板收藏库](/Users/ienone/coding/vaultstream/docs/issues/assets/2026-09-07-responsive-content/collection-768.png)
![桌面收藏库](/Users/ienone/coding/vaultstream/docs/issues/assets/2026-09-07-responsive-content/collection-1200.png)

播放器本次四尺寸实拍（没有保存同场景的旧播放器截图，不伪造前图）：

![手机播放器](/Users/ienone/coding/vaultstream/docs/issues/assets/2026-09-07-responsive-content/player-390.png)
![横屏播放器](/Users/ienone/coding/vaultstream/docs/issues/assets/2026-09-07-responsive-content/player-844.png)
![平板播放器](/Users/ienone/coding/vaultstream/docs/issues/assets/2026-09-07-responsive-content/player-768.png)
![桌面播放器](/Users/ienone/coding/vaultstream/docs/issues/assets/2026-09-07-responsive-content/player-1200.png)
