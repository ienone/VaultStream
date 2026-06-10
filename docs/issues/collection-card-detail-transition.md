# 收藏卡片到详情正文转场设计缺陷

## 状态

active

## 现象

收藏卡片进入详情页时，首屏可能出现卡片飞行层、详情头图、正文和右侧信息卡互相重叠。该问题不是“目标 Hero 为空”的旧问题，而是共享转场、透明详情层和图片失败态叠加后的当前布局问题。

产品目标不是简单删除动效，而是实现“卡片 ↔ 正文”的无缝切换：用户点击收藏卡片后，应感到卡片容器自然展开为阅读 surface，封面、标题和主色调延续到详情页，正文和侧栏在展开完成后清晰出现；返回时则自然收回到原卡片位置。

## 影响范围

- 页面：收藏库、内容详情页。
- 组件：收藏卡片、详情头图、媒体失败态、右侧信息卡。
- 用户影响：打开详情页时阅读区域被遮挡，截图中可见图片失败块和标题/正文重叠。

## 复现方式

1. 打开桌面宽屏前端。
2. 进入收藏库。
3. 点击带封面或远程图片的收藏卡片。
4. 观察进入详情页首屏时，卡片飞行层、图片失败占位、正文和右侧信息卡是否重叠。
5. 使用图片加载失败样本重复检查。

## 当前事实

旧问题中提到的目标 Hero 空 `SizedBox.expand()` 已经不再是当前事实。当前代码已经存在真实详情侧目标：

- `frontend/lib/features/collection/content_detail_page.dart` 定义了 `DetailHeroHeader`。
- 详情页 Hero child 已使用 `DetailHeroHeader`。
- `frontend/lib/features/collection/widgets/list/content_card.dart` 仍然给卡片包 `Hero`。
- `ContentDetailPage` 根部仍使用 `Stack`，底层放 Hero 头图，上层叠透明 `Scaffold`。

## 根因分析

当前问题是布局和动画层级问题：

- 列表卡片、详情头图、详情正文都参与首屏视觉叠加。
- 自定义 flight shuttle 会在转场期间再渲染一套卡片预览。
- 详情页上层 `Scaffold` 透明，正文和侧栏更容易与底层头图发生视觉重叠。
- 图片加载失败时失败占位尺寸和颜色会放大重叠观感。

更深层的设计错误是把“整张卡片 Hero 到详情页底层头图”当作无缝转场。卡片和详情页不是同一个布局：列表卡片是瀑布流中的紧凑摘要，详情页是阅读和检查单条内容的完整 surface。正确的转场对象应是“容器和关键视觉锚点”，而不是让卡片预览、详情头图和正文同时参与同一个 Hero 层。

## 转场设计原则

1. 只共享一个主容器，不共享整页。
   - 源端是收藏卡片外壳。
   - 目标端是详情页的入口阅读 surface 或顶部摘要 surface。
   - 不应把 Hero 目标放在透明 `Scaffold` 背后的底层 `Stack` 中。
2. 正文不参与飞行，只延迟显现。
   - 转场前 0%~60% 只做容器、圆角、主色、封面/标题的连续变化。
   - 正文、右侧信息卡、后处理状态等重内容在容器展开后 fade/slide in。
3. 图片只是锚点，不是唯一转场对象。
   - 封面加载成功时，封面区域可以作为容器内部的 shared visual。
   - 图片失败或无封面时，使用稳定的色块和平台/类型 icon，不触发不同尺寸的失败块飞行。
4. 详情页背景必须稳定。
   - 转场期间详情页应有不透明的 `surface` 背景。
   - 避免透明 `Scaffold` 让底层 Hero、正文和列表残影同时可见。
5. 桌面与移动使用同一语义、不同目标布局。
   - 移动端可采用卡片展开为全屏阅读 surface。
   - 桌面端不应强行从瀑布流卡片飞到两栏完整布局；应先展开为顶部/左侧阅读 surface，右侧信息卡延迟出现。

## 推荐方案

采用 Material container transform 思路，而不是当前“全卡片 Hero + 透明详情页 Stack”的实现。

### 动画阶段

1. 点击瞬间：冻结源卡片视觉状态，取消 hover scale，源卡片位置保留占位，避免瀑布流重排。
2. 0%~60%：卡片容器从源 rect 展开到详情入口 surface rect，圆角从约 28px 过渡到详情 surface 圆角或全屏圆角，阴影逐渐降低，背景色从卡片 surface 过渡到详情 surface / 动态主色 surface。
3. 20%~70%：封面、平台 badge、标题作为容器内部锚点做位置/尺寸过渡；如果图片不可用，使用稳定 fallback，不显示网络失败大块。
4. 60%~100%：正文阅读区、信息侧栏、AppBar 操作按钮渐入并轻微上移；不得在 60% 前出现在飞行层下方。
5. 返回时：正文和侧栏先淡出，入口 surface 收缩回源卡片。如果源卡片已不可见或已被过滤，降级为普通 fade/scale 返回。

### Flutter 实现边界

- 源端 `ContentCard`：只给“卡片容器 shell”参与 shared transition；不要用带 `InkWell`、hover 动画和完整业务 preview 的 widget 作为 flight shuttle。
- 目标端 `ContentDetailPage`：移除当前底层 Hero + 透明 `Scaffold` 的结构；将目标 shared container 放在正常 layout 中，占据详情首屏的真实位置。
- `flightShuttleBuilder`：如继续使用 `Hero`，shuttle 应是轻量、无网络请求、无 Riverpod watch 的 snapshot surface；只渲染容器、封面/fallback、标题和少量 metadata。
- `placeholderBuilder`：源卡片和目标 surface 都应保留尺寸占位，避免列表和详情布局跳动。
- 详情内容：正文、右侧信息卡、后处理状态、富媒体网格应由详情页自己的入场动画控制，不应放进 Hero child。
- 图集内部图片 Hero 可以保留为独立问题域，但 tag 必须与卡片到详情的 container tag 分离。

### 降级策略

- 从深链接 `/collection/:id` 直接进入详情页时，没有源卡片 rect，使用普通 fade/slide 入场。
- 列表筛选、删除、分页或刷新导致返回时源卡片不存在时，使用普通 fade 返回。
- 图片代理失败、封面缺失、NSFW 遮罩等状态不得破坏容器转场，只影响容器内部的静态 fallback。

## 关联代码

- `frontend/lib/features/collection/widgets/list/content_card.dart`
- `frontend/lib/features/collection/widgets/list/collection_card_preview.dart`
- `frontend/lib/features/collection/content_detail_page.dart`
- `frontend/lib/features/collection/widgets/detail/components/media_grid.dart`

## 关联文档

- `../frontend/pages/collection.md`
- `../frontend/pages/content-detail.md`
- `../frontend/components/media-rendering.md`
- `frontend-dashboard-scope-creep.md`

## 修复建议

最小修复：

1. 先禁用当前整卡片到详情底层头图的共享 `Hero` 转场，避免继续出现重叠和残影。
2. 详情页改为不透明 `Scaffold` 背景，移除底层 Hero + 上层透明内容的叠层结构。
3. 图片失败态使用固定尺寸、低干扰占位，不能遮挡正文。

长期修复：

1. 按上述 container transform 方案重新实现卡片到详情正文的无缝切换。
2. 将 shared transition 抽成收藏域内的明确组件或 helper，避免页面随手新增 Hero tag。
3. 为桌面、移动、图片失败、无封面、深链接和返回源卡片不存在等场景建立验收样例。

## 验证方式

- 桌面宽屏：卡片进入详情页，正文、头图、右侧信息卡不重叠。
- 移动端：打开详情页没有飞行卡片残影。
- 图片失败：失败占位不遮挡正文。
- 回退：详情页返回收藏列表不出现残影。
- 动效验收：进入时先看到卡片容器展开，再看到正文/侧栏出现；不得同时出现飞行卡片、底层头图和正文三套视觉层。
- 降级验收：深链接进入详情、返回时源卡片不存在、封面加载失败时，均能退化为稳定普通转场。
