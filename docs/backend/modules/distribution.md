# 后端模块：分发系统

## 文档状态

active

## 代码位置

- Router: `backend/app/routers/distribution.py`
- Queue router: `backend/app/routers/distribution_queue.py`
- Service: `backend/app/services/distribution/*`
- Rule service: `backend/app/services/distribution_rule_service.py`
- Push: `backend/app/push/*`
- Tasks: `backend/app/tasks/distribution_worker.py`

## 功能

- 管理分发规则和目标。
- 根据内容匹配规则生成队列项。
- 支持推送、取消、重试、重新排序、批量操作。
- 支持 Telegram 和 Napcat/QQ 推送服务。

## 不承担职责

- 不管理平台账号登录。
- 不解析原始内容。
- 不替代收藏库内容编辑。

## 实现逻辑

内容入库或规则刷新后，分发服务根据条件匹配规则，生成 `content_queue_items`。worker 消费队列并调用 push service，将结果记录到 pushed records。

## 测试

- `backend/tests/test_distribution_engine.py`
- `backend/tests/test_distribution_decision.py`
- `backend/tests/test_distribution_scheduler.py`
- `backend/tests/test_distribution_rule_service.py`
- `backend/tests/test_api/test_distribution.py`
- `backend/tests/test_api/test_distribution_queue_extra.py`
- `backend/tests/test_push_services.py`

## 与其他模块交互

- contents: 内容状态和媒体用于推送。
- media: 推送时读取缩略图/媒体。
- config-system: 自动审批、worker 开关和策略应受配置控制。
- events-tasks: 推送结果进入事件和 run 记录。

## 对应前端

- `../../frontend/pages/automation.md`
- `../../frontend/pages/content-detail.md`

## API 接口

详见 `../api.md` 中分发队列 API、分发规则 API 和分发目标 API。

## 配置与策略

- 自动审批、队列 worker、重试和立即推送都应受自动化策略约束。
- 分发目标和规则必须通过后端校验，不能只依赖前端禁用按钮。

## 当前问题

- 自动化页面职责过载：`../../issues/frontend-automation-page-responsibility-overload.md`
- 用户控制面与策略缺口：`../../issues/frontend-control-policy-gaps.md`
- 统一任务结果 contract：`../../issues/task-run-result-contract-missing.md`

## 尚未实现 / 计划扩展

分发规则、目标、队列和运行结果的边界按前端 IA 与总路线第零阶段 contract 计划推进。
