# 通用内容适配器

## 文档状态

active

## 适用范围

- 平台：未命中特定平台适配器的 HTTP/HTTPS URL
- 当前代码：`backend/app/adapters/universal_adapter.py`
- 当前类：`UniversalAdapter`
- 相关工具：`backend/app/adapters/utils/tiered_fetcher.py`、`backend/app/adapters/utils/content_agent.py`
- 测试：`backend/tests/test_adapters/test_universal_offline.py`、`backend/tests/test_universal_adapter.py`

## 背景

通用内容适配器承担的是兜底解析职责：当 URL 没有命中特定平台适配器时，后端仍需要尽量抓取页面内容并归一化为 `ParsedContent`。本文用于记录当前 tiered fetch + content agent 流程，避免旧的爬虫库或结构化抽取设想被误认为仍在运行。

## 当前事实

当前实现不是旧文档描述的“直接依赖浏览器爬虫库加结构化抽取策略”的流程。`backend/requirements.txt` 当前没有对应的顶层爬虫库依赖。

当前实现是 Agentic V3 路径：

1. `UniversalAdapter.parse()` 接收 URL。
2. 调用 `tiered_fetch()` 获取原始内容。
3. `tiered_fetch()` 采用多级获取策略，例如 Cloudflare markdown、direct HTTP、浏览器后备路径。
4. 将获取结果交给 `process_content_agent()`。
5. content agent 生成标准化 `ParsedContent`。

## 核心能力

- 处理未被特定平台识别的 URL。
- 多级抓取，尽量先使用低成本路径。
- 使用内容 agent 将网页内容转为标准内容模型。
- 输出统一 `ParsedContent`，供内容服务入库。

## 与代码的关系

- 适配器注册：`backend/app/adapters/__init__.py`
- 抓取层：`backend/app/adapters/utils/tiered_fetcher.py`
- Agent 处理：`backend/app/adapters/utils/content_agent.py`
- LLM 配置：`backend/app/core/llm_factory.py`

## 配置

通用适配器可能读取文本模型配置和代理配置。具体配置以 `backend/app/core/config.py` 和 `backend/app/core/llm_factory.py` 为准。

## 已知限制

- 通用解析质量依赖抓取结果和 LLM 输出。
- JS 重渲染、登录墙、反爬和动态内容可能导致抓取失败。
- 真实 LLM 集成测试必须标记为 integration，不应进入默认测试集合。

## 使用方式

这是知识库文档，不是待办清单。若要调整 tiered fetch、content agent 或通用解析策略，先创建 plan，并同步更新 adapter 测试。
