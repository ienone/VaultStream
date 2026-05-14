# VaultStream 全项目审计索引

审计日期：2026-05-13  
审计范围：`backend/`、`frontend/`、`docs/`、`.github/workflows/`、`backend/Dockerfile`、`backend/docker-compose.yml`、当前 SQLite 数据库样本 `backend/data/vaultstream.db`。  
初始约束：2026-05-13 只产出审计文档，未修改业务代码。2026-05-14 已进入整改阶段，当前实现状态以 `10_implementation_status.md` 为准。

## 结论

VaultStream 的主体架构已经具备可运行产品形态：FastAPI 后端、SQLite 持久化、Flutter 客户端、内容采集/解析/分发/发现/Agent/RAG 等模块均有实现。但当前代码库处于“功能推进快于工程收敛”的状态，主要风险集中在 5 类：

1. 质量门禁部分红灯：后端 pytest 当前收集阶段失败；Flutter 在 `frontend` 目录下 `analyze/test` 已通过。
2. 安全暴露：前端默认记录 API token 请求头，`lxml 5.4.0` 存在已知漏洞，图片代理 debug 模式绕过内网 URL 防护。
3. 文档与实现漂移：数据库文档声明 FTS5，但当前 DB 没有 `contents_fts`，代码也未找到创建路径。
4. 类型/契约松散：多个 API 返回 `dict`，前后端大量 `Map<String, dynamic>`/`JSON Any`，RAG/summary 测试与实现不同步。
5. 性能路径未闭环：语义检索向量以 JSON 存储并逐行 Python 计算；FTS 缺失后会退化为 LIKE；Discovery 入库后未看到 embedding 索引调度。

## 验证摘要

| 项目 | 命令/检查 | 结果 |
| --- | --- | --- |
| 后端测试 | `.venv\Scripts\python.exe -m pytest backend\tests -q -m "not integration" -W error::ResourceWarning` | 通过：646 passed, 4 skipped, 16 deselected |
| 依赖漏洞 | `.venv\Scripts\python.exe -m pip_audit -r backend\requirements.txt` | 通过：No known vulnerabilities found |
| Bandit | `.venv\Scripts\python.exe -m bandit -r backend\app --severity-level high --confidence-level high` | 通过：No issues identified |
| Vulture | `.venv\Scripts\python.exe -m vulture backend\app backend\tests --min-confidence 80` | 多处未使用 import/变量/fixture 候选 |
| SQLite | `PRAGMA integrity_check; PRAGMA foreign_key_check;` | `ok`，外键检查空；16 张表、86 个索引 |
| FTS 表 | 当前 DB 表清单 + 代码搜索 | 已有 `ensure_content_fts()`、trigger、backfill 和 health 暴露 |
| Flutter analyze | `cd frontend && flutter analyze` | 通过：No issues found，10.8s |
| Flutter test | `cd frontend && flutter test` | 通过：All tests passed；仍有一个既有 widget tap offset warning |
| OpenAPI 文档 | `.venv\Scripts\python.exe scripts\check_openapi_docs.py` | 通过：OpenAPI docs check passed: 92 endpoints covered |
| 自动审计脚本 | `audit_repo.py --with-tests` | 外层 903s 超时；未生成完整自动报告 |

## 文件导航

- `01_architecture.md`：架构边界、模块耦合、文档漂移、Agent/RAG/Discovery 实现状态。
- `02_code_quality_redundancy.md`：代码质量、重复/废弃代码、前端 codegen、动态类型问题。
- `03_security.md`：依赖漏洞、token 暴露、SSRF/URL 安全、Docker/CI 安全基线。
- `04_type_contract_resource.md`：类型契约、API schema、资源释放、SSE 生命周期。
- `05_performance_scalability.md`：SQLite、FTS、向量检索、媒体代理、前端性能风险。
- `06_tests_quality_gates.md`：本次验证、测试缺口、CI 门禁缺失、建议门禁。
- `07_feature_gaps_roadmap.md`：README/ROADMAP/API 与当前实现的功能差距。
- `08_action_plan.md`：按 P0/P1/P2/P3 排序的落地计划。
- `09_goal_mode_prompt.md`：可复用的下一轮 Goal Mode 提示词。
- `10_implementation_status.md`：审计问题实现状态总览，区分已修、未修和假修复/弱验证。

## 优先级定义

- P0：当前阻断交付或会直接泄露敏感凭据。
- P1：高概率影响安全、数据正确性、核心功能可用性或后续开发效率。
- P2：中期会拖慢性能、维护、扩展或产品一致性。
- P3：清理、文档、体验和低风险改进。
