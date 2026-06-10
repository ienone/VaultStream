# Discovery 占位动作泄漏为用户可见工作流

## 状态

active

## 现象

- 收件箱列表、Discovery 详情页和批量操作 sheet 向用户展示“加入规则候选”“请求分发”“修复失败”等动作。
- 用户点击后，前端显示“已加入规则候选”“已记录分发请求”“已标记待修复”等成功提示。
- 后端 `_apply_inbox_action()` 实际只在 `content.metadata/context` 中写入 `inbox_action.status = "placeholder"`、`distribution_requested = True` 或类似标记，并未真正进入规则候选、分发队列或修复流程。

## 影响范围

- 页面：`/inbox`、`/discovery`、Discovery 详情页、Discovery 批量操作 sheet。
- 后端模块：discovery、distribution。
- 数据：候选内容 context / metadata 中的占位标记。
- 用户影响：用户会误以为分发、修复或规则候选流程已经执行，实际只是记录意图，造成流程断裂和状态误导。

## 复现方式

1. 进入 `/inbox` 或 `/discovery`。
2. 对单条候选内容打开更多菜单，选择“请求分发”或“修复失败”。
3. 观察前端成功 toast。
4. 检查后端 `backend/app/routers/discovery.py`，确认该动作只写 placeholder/context 标记，没有调用分发队列或修复服务。

## 根因分析

- Discovery 页面文档定义的是候选内容审核与收件箱处理，不承担真实分发队列操作。
- AI 生成代码把“未来可能的流程入口”做成了用户可点击动作，并用成功 toast 表达已执行。
- 后端为了保留意图写入 placeholder 字段，但前端没有把该状态解释为“仅记录意图”。

## 关联代码

- `frontend/lib/features/discovery/discovery_page.dart`
- `frontend/lib/features/discovery/discovery_detail_page.dart`
- `frontend/lib/features/discovery/widgets/discovery_batch_action_sheet.dart`
- `frontend/lib/features/discovery/providers/discovery_actions_provider.dart`
- `backend/app/routers/discovery.py`

## 关联文档

- `../frontend/pages/discovery.md`
- `../frontend/README.md`
- `../backend/modules/discovery.md`
- `../backend/modules/distribution.md`
- `frontend-automation-page-responsibility-overload.md`
- `frontend-ui-layer-api-write-boundary.md`

## 修复建议

- 最小修复：从 Discovery 菜单、详情页和批量 sheet 删除“请求分发”“修复失败”“加入规则候选”等未闭环动作。
- 如果保留：文案必须明确为“记录意图”，且不得用“已分发/已修复”类成功语义；同时在后端 API 文档中写明返回 contract。
- 长期修复：真正的分发、修复、规则候选流程应进入自动化/分发模块，由对应 service/task 执行并生成可追踪 run。

## 验证方式

- 自动测试：前端 widget 测试确认 Discovery 操作菜单不展示未闭环动作；后端 API 测试确认 placeholder contract 明确。
- 手动验收：桌面和移动进入 `/inbox`、详情页、批量操作 sheet，确认不再出现会误导为真实分发/修复的动作。
- 截图/日志：保留操作菜单截图和后端 context 写入日志。
