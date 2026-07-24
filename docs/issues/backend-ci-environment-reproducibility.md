# 后端 CI 环境与本地测试结果不可稳定复现

## 状态

active

## 现象

- 2026-07-17 最近一次远端 Quality Gates 在后端 pytest 阶段出现 `1 failed, 762 passed, 4 skipped, 9 deselected`，失败用例为 `test_agent_api_catalog_lists_client_api_surface`。
- 同一提交序列在本地曾完成 `763 passed, 4 skipped, 9 deselected`；随后从 `backend/` 工作目录单独复测上述用例得到 `1 passed`。
- `backend/requirements.txt` 和 `backend/requirements-dev.txt` 对 FastAPI、Starlette、Pydantic、SQLAlchemy、pytest 等核心依赖没有形成可复现版本集合，GitHub Actions 每次重新解析当前可用版本。
- Quality Gates 采用串行步骤，pytest 失败后依赖审计、Bandit、OpenAPI 清单、数据库 schema gate 和敏感信息检查不会继续提供结果。
- 工作流已按仓库使用方式取消普通 push 自动触发，保留 pull request 和手动触发；历史红色运行不会自动被新的 push 覆盖。

## 影响范围

- CI：`.github/workflows/quality.yml`。
- 依赖：`backend/requirements.txt`、`backend/requirements-dev.txt`。
- 测试：`backend/tests/`，尤其是依赖应用装载、OpenAPI 枚举和全局状态的测试。
- 用户影响：开发者不能仅凭本地通过判断远端基线，偶发环境差异会掩盖真实回归，也会阻断后续质量门结果。

## 复现方式

1. 在 GitHub Actions 的 `backend/` 工作目录安装 `requirements-dev.txt` 当前解析版本。
2. 运行 `python -m pytest tests -q -m "not integration"`，记录 Agent API catalog 用例和后续质量门结果。
3. 在本地现有虚拟环境从同一工作目录运行完整命令，并单独运行该失败用例。
4. 对比 Python、操作系统、依赖版本、测试顺序和应用装载状态；当前第 4 步尚未在干净 Linux 环境完成。

## 根因分析

- 已确认：本地和 CI 没有共享锁定或约束后的 Python 依赖集合。
- 已确认：当前失败在不同环境中结果不一致，说明测试或其应用装载过程依赖未被显式控制的环境条件。
- 待验证：直接原因可能是依赖版本变化、Linux 与 Windows 差异、测试顺序、应用全局状态或它们的组合；在干净 Linux 环境复现前不能把原因归结为某一个库。
- 已确认：质量门的串行 fail-fast 结构降低了一次运行能够提供的诊断信息量。

## 关联代码

- `.github/workflows/quality.yml`
- `backend/requirements.txt`
- `backend/requirements-dev.txt`
- `backend/tests/test_api/test_agent_tools.py`
- `backend/app/services/agent/tools/api_bridge.py`

## 关联文档

- 测试价值问题：`./backend-test-suite-value-density.md`
- 测试套件价值问题：`./backend-test-suite-value-density.md`
- 后端总览：`../backend/README.md`

## 修复建议

- 最小修复：在干净 Linux 环境记录实际解析的依赖版本并稳定复现失败，确认是依赖、顺序还是全局状态问题。
- 中期修复：建立适合本项目的依赖约束或锁定机制，使本地、CI 和部署能从同一依赖基线安装。
- 中期修复：把彼此独立的安全、文档和 schema 检查调整为即使测试失败也能产生结果的质量门，避免一次失败遮蔽其余信号。
- 长期修复：按照测试与 CI 建设计划维护环境矩阵、更新策略、耗时基线和不稳定测试治理流程。

## 验证方式

- 在全新 Windows 开发环境和 GitHub Actions Linux 环境安装同一依赖集合，核心测试结果一致。
- 手动触发 Quality Gates 后，后端测试、依赖审计、Bandit、OpenAPI、schema gate 和敏感信息检查都能给出独立结果。
- 依赖升级通过明确的更新提交完成，提交中包含完整测试和兼容性结果。
- 不以重新启用普通 push 自动触发作为修复手段。
