# 验证策略

## 文档状态

active

日常改动采用针对性验收；临时脚本完成验证后删除，只留下必要结果和截图。长期测试必须证明自己保护的是权限、外部副作用、数据完整性或难以人工复现的历史竞态，不按接口、字段、页面数量铺开，不追求覆盖率。

## 长期保留的边界

- Agent 路径权限、确认唯一执行与取消：`test_agent_execution_boundaries.py`、`test_api/test_agent_tools.py`。
- API/媒体鉴权、SSRF、签名绑定与到期、路径逃逸：`test_core/test_safe_fetch.py`、`test_api/test_media.py`、`test_api/test_media_manifest.py`、`test_services/test_media_access.py`；Bot 访问控制：`test_bot/test_permissions.py`。
- 批量文件回滚和共享对象保留、范围先于候选截断：`test_content_lifecycles.py`；人工编辑保护：`test_tasks/test_parsing_task.py`；事件最后成员及并发删除：`test_api/test_knowledge_events.py`。
- 策略关闭后的副作用限制：`test_automation_policy.py`；任务排他领取、准确结算及新队列实例接续：`test_queue_concurrency.py`；运行中任务和通知引用保留：`test_background_task_state.py`。
- 前端仅保留 `discovery_feed_provider_test.dart`、`playback_restore_test.dart`、`api_client_log_redaction_test.dart`，分别验证查询竞态、暂停恢复及日志脱敏。播放器测试只替换 OS 解码边界，不证明真实播放质量。

测试复用实际 SQLite 引擎、外键、ORM、文件存储和 ASGI 路由。独立测试数据库在 `backend/.test-runtime/` 内创建并清理；不启动应用 lifespan/worker，不访问用户数据库。外部模型在调用边界替换。默认禁止非回环网络，并把资源未释放警告视为错误。

## 执行与验收

- 后端：仓库根 `.venv/bin/python -m pytest backend/tests -q`。
- 前端：`frontend/` 下 `flutter analyze --no-pub`、`flutter test --no-pub`；沙盒外执行规则见根 AGENTS。
- CI 保留必要回归、依赖声明、OpenAPI、schema、静态分析和安全检查；不生成覆盖率报告。
- UI、普通业务结果、外部平台解析、真实登录/同步/发送、原生媒体与性能按当前改动验收，不进入长期 mock/布局/压测套件。有外部副作用时必须具备用户授权。
- 临时探针写入 `backend/manual_tests/`，验证后删除；不把被删除套件原样搬到脚本目录，不另建通用测试基础设施。

2026-09-06 清理结果：正式测试源码从 159 文件 / 34,367 行收敛至 17 文件 / 1,280 行（含公共 fixture），净减 33,087 行；另删除 35 个已用诊断脚本 / 4,230 行和不再使用的样本、覆盖率及测试依赖。后端 39 项与前端 6 项通过，静态分析、依赖声明、OpenAPI 和 schema 检查通过。这些结果只对应上述保留边界，不再把旧完整套件数量当作当前保障。
