# 通用智能适配器 (Universal Adapter)

`UniversalAdapter` 是 VaultStream 的核心组件之一，用于处理所有未特定适配的 URL。结合了 Crawl4AI 的高性能爬虫能力和 LLM 的语义理解能力，理论上能够从任意网页中提取结构化数据（标题、正文、作者、图片等）。

## 核心能力

1.  通用解析: 支持任意 HTTP/HTTPS 链接，自动处理 JavaScript 渲染。
2.  智能提取: 使用 Text LLM (如 DeepSeek, Qwen-Turbo) 自动去除广告、侧边栏和导航菜单。
3.  身份伪装: 支持复用本地 Chrome Profile，自动突破 Twitter/X、Medium 等网站的登录墙。
4.  低成本: 默认使用低成本的文本模型进行清洗，仅在必要时（Discovery Service）使用视觉模型。

## 配置指南

### 1. 基础依赖

确保 `backend/requirements.txt` 中已安装以下库：
- `crawl4ai`
- `browser-use`
- `playwright`
- `langchain-openai`

### 2. 环境变量 (`backend/.env`)

为了平衡性能与成本，我们采用双模型策略：

```ini
# --- 1. 视觉模型 (用于主动发现/复杂任务) ---
# 参考: Qwen-VL-Max (阿里), 
VISION_LLM_API_KEY=sk-xxx
VISION_LLM_BASE_URL=https://dashscope.aliyuncs.com/compatible-mode/v1
VISION_LLM_MODEL=qwen-vl-max

# --- 2. 文本模型 (用于通用解析/清洗) ---
# 推荐: DeepSeek, Qwen-Turbo (成本极低)
TEXT_LLM_API_KEY=sk-xxx
TEXT_LLM_BASE_URL=https://api.deepseek.com
TEXT_LLM_MODEL=deepseek-chat

# --- 3. 浏览器配置 (用于突破登录墙) ---
CHROME_PATH=C:\Program Files\Google\Chrome\Application\chrome.exe
CHROME_USER_DATA_DIR=C:\Users\YourUser\AppData\Local\Google\Chrome\User Data
BROWSER_USE_DISABLE_EXTENSIONS=true
```

## 架构设计

### 类结构

*   `UniversalAdapter`: 继承自 `PlatformAdapter`。
    *   输入: 任意 URL。
    *   处理: 
        1. 启动 Playwright 浏览器（有头/无头）。
        2. 加载页面并等待 JS 执行。
        3. 调用 `LLMFactory.get_text_llm()` 获取配置。
        4. 使用 `LLMExtractionStrategy` 将 HTML 转化为 JSON。
    *   输出: 标准化的 `ParsedContent` 对象。

*   `LLMFactory`: 位于 `app.core.llm_factory`。
    *   负责动态加载模型配置。
    *   负责处理 Pydantic 兼容性补丁（Monkey Patch）。
    *   提供统一的错误日志记录。

### 错误处理

*   LLM 故障: 如果 LLM API 调用失败或返回非 JSON 格式，适配器会自动降级 (Fallback)，直接返回网页的原始 Markdown 内容，并在 `archive_metadata` 中标记错误。
*   浏览器故障: 自动捕获 Playwright 超时或 Crash，并返回错误信息。

## 常见问题

Q: 启动非常慢，且报 Timeout 错误？
A: 检查 `.env` 中是否设置了 `BROWSER_USE_DISABLE_EXTENSIONS=true`，否则 `browser-use` 可能会因为尝试下载外网扩展导致超时。
