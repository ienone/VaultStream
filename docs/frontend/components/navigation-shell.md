# Navigation Shell

## 文档状态

active

## 当前代码

- `frontend/lib/layout/app_shell.dart`
- `frontend/lib/layout/root_page_actions.dart`
- `frontend/lib/core/layout/responsive_layout.dart`

## 当前职责

- 主导航只展示动态、收藏库、自动化三个目的地。宽度达到 medium 使用固定窄 `NavigationRail`，短横屏省略文字标签并保留语义与 tooltip；侧栏直接使用 Material 的 scrollable 能力，在极短窗口中可滚动；compact 使用标准 `NavigationBar`，键盘出现时隐藏底栏。
- 主导航没有保存按钮、工具队列或额外的“更多”目的地；不随大屏扩成宽栏，也不使用竖线重复分隔。
- 三个主页的 AppBar 复用 `layout/root_page_actions.dart`：普通加号打开统一保存 surface，工具按钮打开全局搜索、Agent、消息盒子、账号中心和设置。局部操作仍由各页 AppBar 负责，选择模式不混入全局动作。
- 工具按钮和消息菜单项沿用同一个持久化消息未读计数。SSE 到达后重读事实 API，Web 端保留既有低频刷新。服务端空闲心跳 30 秒，客户端失活阈值 90 秒；替换连接与销毁时通过 http AbortableRequest 中止旧响应流，旧流迟到的事件/错误不得触发新的连接或更新当前状态。
- 包装 `StatefulNavigationShell`，普通分支切换及 Rail/Bar 切换保留页面状态；重复点击当前目的地仍返回该分支根页面。
- 系统分享沿用同一捕获表面；mini player 在导航之外、正文下方维持当前全局播放会话。

## 不承担职责

- 不执行业务动作。
- 不持有页面业务状态。
- 不决定账号、设置或自动化的功能边界。

## 状态与输入输出

- 输入：`StatefulNavigationShell` 当前分支、屏幕宽高、用户点击的导航目标。
- 输出：桌面 `NavigationRail`、移动 `NavigationBar`、全局工具入口和当前分支内容。
- 副作用：只执行路由跳转，不直接调用业务 API，也不在普通分支切换时重置收藏库筛选。

## 响应式和失败态要求

- 手机竖屏底栏只有三个目的地；平板、桌面与足够宽的短横屏使用窄侧栏。保存、工具始终位于主页页头，不在导航旁增加额外按钮。
- 自动化分区的系统返回先回 `/automation`；规则详情先回 `/automation/distribution`。
- 工具与设置使用独立路由。设置分区切换只替换当前设置地址，保留进入前的主分支；窄屏先返回设置列表，再返回来源页面。
- 正文与 mini player 避让横向安全区，侧栏布局避让底部系统区域；不覆盖 AppBar，不创建第二套内容状态或播放控制器。

## 设计约束

主导航只承载 Root Shell 高频业务入口。消息盒子、设置、任务详情、独立账号中心、Agent/RAG 等均不得作为同级主导航项；需要保留的工具或深链入口应放入全局工具区或具体业务下钻。账号对象与连接动作不再作为设置 Section Shell 的长期目标职责。
