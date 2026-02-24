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
- `playwright`
- `langchain-openai`
- `openai`

### 2. 环境变量 (`backend/.env`)

为了平衡性能与成本，我们采用双模型策略：

```ini
# --- 1. 视觉模型 ---
# 参考: Qwen-VL-Max (阿里), 
VISION_LLM_API_KEY=sk-xxx
VISION_LLM_BASE_URL=https://dashscope.aliyuncs.com/compatible-mode/v1
VISION_LLM_MODEL=qwen-vl-max

# --- 2. 文本模型 (用于通用解析/清洗) ---
# 参考: DeepSeek
TEXT_LLM_API_KEY=sk-xxx
TEXT_LLM_BASE_URL=https://api.deepseek.com
TEXT_LLM_MODEL=deepseek-chat

# --- 3. 浏览器配置 ---
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
