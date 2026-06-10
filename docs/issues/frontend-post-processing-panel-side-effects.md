# 内容详情后处理面板直接执行跨模块写操作

## 状态

active

## 现象

- `frontend/lib/features/collection/widgets/detail/components/post_processing_status_panel.dart` 是约 500 行的展示组件，但内部直接读取 `apiClientProvider` 并执行多类后端写操作。
- 该组件根据 `stage['key']`、`stage['status']` 等动态字段推断动作，然后触发生成摘要、语义重建、分发重试/入队、巡逻评分、embedding retry 等接口。
- 成功 toast 只从响应中猜测 `run_id` 字段，并跳转到 `/home?run=...`，而当前导航文档定义的统一任务结果入口是 `/tasks/:runId`。

## 影响范围

- 页面：收藏内容详情页。
- 后端模块：contents、search-rag、distribution、events-tasks。
- 数据：摘要、语义索引、分发队列项、巡逻评分、后台任务 run。
- 用户影响：一个 UI 面板承担多个业务域的写操作，失败态、权限策略、run 详情跳转和 API contract 都难以统一。

## 复现方式

1. 打开任意收藏内容详情页。
2. 进入后处理状态区域。
3. 对失败或未完成 stage 点击“生成摘要”“重建索引”“重试分发”“巡逻评分”等操作。
4. 观察组件内部直接调用对应 API，并在成功后通过 SnackBar action 跳转 `/home?run=...`。

## 根因分析

- 后处理状态展示、stage action 推导、跨模块写操作和 run 结果导航被堆在同一个 widget 文件中。
- `processing-status` 返回值缺少前端 typed view model，组件只能用动态 map 猜字段。
- 任务结果页 contract 未强制落地，导致各处继续用临时弹层或首页 query 展示 run。

## 关联代码

- `frontend/lib/features/collection/widgets/detail/components/post_processing_status_panel.dart`
- `backend/app/routers/contents.py`
- `backend/app/routers/search.py`
- `backend/app/routers/distribution_queue.py`
- `backend/app/services/background_task_state.py`

## 关联文档

- `../frontend/pages/content-detail.md`
- `../frontend/pages/tasks.md`
- `../frontend/components/task-result.md`
- `../backend/modules/contents.md`
- `../backend/modules/search-rag.md`
- `../backend/modules/distribution.md`
- `../backend/modules/events-tasks.md`

## 修复建议

- 最小修复：把成功后的 run 跳转改为 `/tasks/:runId`，避免继续分裂任务结果入口。
- 中期修复：把 stage action 判定和 API 写操作移入详情页 controller/provider，组件只接收 typed status 与可执行 action view model。
- 长期修复：为 `processing-status` 建立明确 response model；所有产生 run 的动作统一返回稳定 `run_id` 和任务类型元数据。

## 验证方式

- 自动测试：`flutter analyze`；为后处理 action provider 增加单元测试；为 run 跳转增加 widget/router 测试。
- 手动验收：分别触发摘要、语义重建、分发重试、巡逻评分，确认 UI 不直接拼接 API，成功后进入 `/tasks/:runId`。
- 截图/日志：保留任务结果页展示 run 详情的截图。
