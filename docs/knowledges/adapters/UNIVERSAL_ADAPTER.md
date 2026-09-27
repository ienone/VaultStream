# 通用内容适配器

## 文档状态

active

## 适用范围

- 平台：未命中特定平台适配器的 HTTP/HTTPS URL
- 当前代码：`backend/app/adapters/universal_adapter.py`
- 当前类：`UniversalAdapter`
- 相关工具：`backend/app/adapters/utils/tiered_fetcher.py`、`backend/app/adapters/utils/content_agent.py`
- 测试：`backend/tests/test_public_parser_integrity.py`

## 背景

通用内容适配器承担的是兜底解析职责：当 URL 没有命中特定平台适配器时，后端仍需要尽量抓取页面内容并归一化为 `ParsedContent`。本文用于记录当前 tiered fetch + content agent 流程，避免旧的爬虫库或结构化抽取设想被误认为仍在运行。

## 当前事实

浏览器等待时间由 `core/crawler_config.py::get_delay_for_url` 同步匹配固定域名表；主域和子域使用同一延迟，未命中为 5 秒。该匹配不读取数据库，也不维护异步包装。

当前实现不是旧文档描述的“直接依赖浏览器爬虫库加结构化抽取策略”的流程。`backend/requirements.txt` 当前没有对应的顶层爬虫库依赖。

当前获取与处理路径：

1. `UniversalAdapter.parse()` 接收 URL。
2. 调用 `tiered_fetch()` 获取原始内容。
3. 一次 HTTP 内容协商同时接受 Markdown/HTML，直接复用返回的 HTML；内容不足才使用共享 Playwright/WebKit。404/410 和 429 不启动浏览器。
4. 将获取结果交给 `process_content()`。
5. 明确的正文节点直接提取，其余页面由 content agent 处理；适配器统一映射为 `ParsedContent`。

## 核心能力

- 处理未被特定平台识别的 URL。
- 多级抓取，尽量先使用低成本路径；已知验证页不作为正文。
- Telegraph 的 `article.tl_article_content`，以及 Article/NewsArticle/BlogPosting/TechArticle 中单一 `itemprop=articleBody`，可直接转换并读取明确元数据，零模型调用。存在音视频/iframe 或明确付费标识时继续原处理流程，不声称简单抽取覆盖复杂页面。
- 重定向后按最终 URL 解析相对链接。
- 使用 LangChain function calling 和本地 Pydantic contract 完成可选选择器定位，以及一次完成正文边界、字段和清理项的提取；缺失工具调用、字段类型错误或越界行号直接失败，不使用正则 JSON 提取或静默回退。
- 内容处理过程复用同一个 `ChatOpenAI`，OpenAI 兼容端点使用 chat completions，并保留完整模型名及配置的 extra_body。
- 输出统一 `ParsedContent`，供内容服务入库。

## 与代码的关系

- 适配器注册：`backend/app/adapters/__init__.py`
- 抓取层：`backend/app/adapters/utils/tiered_fetcher.py`
- Agent 处理：`backend/app/adapters/utils/content_agent.py`
- LLM 配置：`backend/app/services/config_service.py::LLMConfig`

## 配置

确定性正文提取无需配置模型 Key；其他页面才要求文本模型。通用适配器读取 `LLMConfig`，保留完整模型名，不经过已退休的 Crawl4AI provider 字符串转换。抓取与 Agent 处理异常保持原始类型，不一律标为可重试；未生效的 `use_magic/user_data_dir/max_retries` 参数已移除。

## 已知限制

- 通用解析质量依赖抓取结果；非确定性路径还依赖 LLM 输出。
- 2026-09-19 Telegraph 真实样本已完成适配器解析，正文 1978 字符，标题/作者齐全，模型调用为 0；schema.org 路径仅完成离线合同验收。
- JS 重渲染、登录墙、反爬和动态内容可能导致抓取失败。
- 提取调用读取完整编号正文，不通过截掉中段降低输入；长页可能增加单次输入量，调用次数减少不等于总 token 必然下降。

## 使用方式

这是知识库文档，不是待办清单。若要调整 tiered fetch、content agent 或通用解析策略，同步模块文档并执行一次性入口验收。
