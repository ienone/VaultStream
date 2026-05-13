# 下一轮 Goal Mode 提示词

下面这段可以直接作为下一轮 Goal Mode 任务使用。

```text
目标：按 docs/exam/08_action_plan.md 的优先级修复 VaultStream 的 P0/P1 问题，先恢复质量门禁和明显安全风险。

仓库：C:\Users\86138\Documents\coding\VaultStream

约束：
- 先读取 docs/exam/00_index.md 到 08_action_plan.md，确认现有审计结论。
- 不要回滚用户已有未提交修改；开始前先看 git status。
- 每次只处理一个逻辑批次，保持提交原子性。
- 后端测试必须使用 repo 根目录 .venv：
  .venv\Scripts\python.exe -m pytest backend/tests -q
- Flutter 修改前先跑 codegen：
  cd frontend
  dart run build_runner build --delete-conflicting-outputs
- 如果 Flutter toolchain 卡住，先定位 cache/lock/network/toolchain 问题，不要盲目改业务代码。

第一批任务：
1. 修复 backend/tests/test_content_summary.py 与 content_summary_service.py 的契约断裂，让 pytest 至少通过收集阶段。
2. 将前端 DEBUG_LOG 默认改为 false，并确保 Dio 日志脱敏 X-API-Token、Authorization、cookie、bot token。
3. 在 release/build workflow 中显式传入 DEBUG_LOG=false。

验收：
- .venv\Scripts\python.exe -m pytest backend/tests -q
- cd frontend && dart run build_runner build --delete-conflicting-outputs && flutter analyze && flutter test
- git diff 只包含本批任务相关改动。
- 最终回复列出改动文件、验证结果、未完成风险。
```

## 备选：只修安全批次

```text
目标：只修复 docs/exam/03_security.md 中的 P1 安全项，不处理架构重构。

任务：
1. 升级 lxml 到安全版本，并验证相关 parser/adapter 测试。
2. 修复 /proxy/image 的 SSRF 绕过、redirect 后校验、大文件限制。
3. 将所有直接 launchUrl(Uri.parse(...)) 改为 safe_url_launcher.dart。

约束：
- 不改 unrelated UI。
- 不重构 RAG/Agent/Distribution。
- 保持后端/前端各自最小测试覆盖。
```

