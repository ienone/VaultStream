# VaultStream 架构体检报告

> 生成日期：2026-04-07  
> 覆盖范围：276 个 Python 文件，10 条系统链路  
> 审计方法：全量代码阅读 + 数据流追踪 + 静态分析

## 报告目录

| 文件 | 内容 |
|---|---|
| [01_system_overview.md](./01_system_overview.md) | 系统全貌：模块地图、链路清单、单例库存 |
| [02_chain_flows.md](./02_chain_flows.md) | 10 条数据流全链路追踪（含状态突变点） |
| [03_smell_catalog.md](./03_smell_catalog.md) | 坏味道目录：严重性分级 + 定位 + 根因 |
| [04_architecture_diagrams.md](./04_architecture_diagrams.md) | 3 张 Mermaid 架构图：现状 / 重构建议 / 目标 |
| [05_refactor_roadmap.md](./05_refactor_roadmap.md) | 重构优先级路线图（P0/P1/P2） |
| [06_frontend_audit.md](./06_frontend_audit.md) | 前端体检报告（Flutter，139个Dart文件，12个维度） |
| [07_rag_vector_search_implementation.md](./07_rag_vector_search_implementation.md) | RAG 增强向量搜索完整落地指南（前后端联合，4个阶段） |

## 核心数字

### 后端（Python / FastAPI）
- **10 条系统链路** 全量追踪
- **7 个高危问题** 存在数据完整性或静默失败风险
- **3 个神类** 超过 800 行（parsing.py / zhihu.py / content_agent.py）
- **4 头分裂配置** `.env` + `Settings 单例` + `_SETTINGS_CACHE` + `DB KV`
- **0 个向量索引** 搜索为全表扫描 O(N)

### 前端（Flutter / Dart）
- **3 个 Critical 问题** 可在 Release 包中复现（崩溃 / 功能失效）
- **2 个高危安全问题** API Token 默认写入日志 + 明文存储
- **6 个 mutation 方法** 使用了 Riverpod 3 非法的 `ref.watch`
- **3 个 God Widget** 单文件超 575 行
- **6 条已记录已知问题** 在代码中全部确认未修复
