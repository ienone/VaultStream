# 知乎内容适配器完整文档

## 文档状态

active

## 适用范围

- 平台：知乎
- 当前代码：`backend/app/adapters/zhihu.py`
- 当前类：`ZhihuAdapter`
- 测试：`backend/tests/test_public_parser_integrity.py`

## 背景

知乎内容类型包括回答、文章、问题、想法、用户主页和收藏夹等。不同类型可能使用 API、HTML 解析或回退策略。该文档记录平台知识，不直接代表开发计划。

## 当前事实

当前适配器由 `ZhihuAdapter` 实现，并输出标准 `ParsedContent`。下文平台细节保留为知识库参考；如与代码不一致，以当前代码和测试为准。

收藏 fetcher 的续页游标保存收藏夹 ID 与已消费条目 offset。达到单次上限时从页内实际消费位置续读，末页转向下一收藏夹，全部结束才返回 None；输入游标无效或目标收藏夹消失时明确报错。真实账号连续两批各 3 条已验证不重复。平台收藏排序发生变化仍可能影响 offset 分页，入库继续依赖 canonical 去重，不能把两批验收宣称为并发变动下完整快照。

## 与代码的关系

- 适配器注册：`backend/app/adapters/__init__.py`
- 解析实现：`backend/app/adapters/zhihu.py`
- 收藏同步：`backend/app/adapters/favorites/zhihu_fetcher.py`
- 匿名阅读页解析：`backend/app/adapters/zhihu_parser/public_reader.py`
- 匿名 Chromium 页面：`backend/app/adapters/zhihu_parser/browser_reader.py`

## 使用方式

修改知乎解析或收藏同步前，应先区分内容解析和收藏抓取两条链路；新增字段、include 参数或 HTML 解析路径需先建 plan 并补测试。

## 已知限制

- API include 参数和 HTML 结构可能变化。
- Cookie、zse/fingerprint 和访问限制可能影响真实解析。
- 下文历史策略需要按当前代码和样本复核。

VaultStream 的知乎适配器支持解析知乎的专栏文章、问答、想法（Pin）及用户主页信息。本文档详细说明了解析策略、回退逻辑和存档内容。

---

## 1. 支持的 URL 类型

适配器会自动识别以下 URL 模式：

| 类型 | URL 模式 | 示例 |
| :--- | :--- | :--- |
| 专栏文章 (Article) | `zhuanlan.zhihu.com/p/{id}` | `https://zhuanlan.zhihu.com/p/676348421` |
| 问题 (Question) | `zhihu.com/question/{id}` | `https://www.zhihu.com/question/532925796` |
| 回答 (Answer) | `zhihu.com/question/{qid}/answer/{aid}` 或 `zhihu.com/answer/{aid}` | `https://www.zhihu.com/question/123/answer/456` |
| 想法 (Pin) | `zhihu.com/pin/{id}` | `https://www.zhihu.com/pin/1728258525883654144` |
| 用户主页 (People) | `zhihu.com/people/{token}` | `https://www.zhihu.com/people/excited-vczh` |
| 专栏主页 (Column) | `zhihu.com/column/{id}` | `https://www.zhihu.com/column/learning-ai` |
| 收藏夹 (Collection) | `zhihu.com/collection/{id}` | `https://www.zhihu.com/collection/123456` |

---

## 2. 当前解析策略

回答和文章在无账号时优先读取知乎自己的匿名 Tardis 阅读页；有账号时优先使用元数据更丰富的 API，失败后独立尝试匿名阅读页。文章、问题和用户主页的网页路径使用经过实测的独立匿名 Chromium context；账号 Cookie 不注入该公开页面路径。

| 类型 | 无账号 | 有账号 |
| --- | --- | --- |
| 回答 | Tardis → API → 普通 HTML | API → Tardis → 普通 HTML |
| 文章 | Tardis → Chromium 页面 | API → Tardis → Chromium 页面 |
| 问题、用户主页 | Chromium 页面 | API → Chromium 页面 |
| 专栏、收藏夹 | API | API |
| 想法 | 普通 HTML | 普通 HTML |

Tardis 入口为 `/tardis/zm/ans/{answer_id}` 与 `/tardis/zm/art/{article_id}`，数据在 `window.g_initialProps.renderHtml`。该请求不携带账号 Cookie，并沿用安全抓取、大小限制和知乎代理配置。

解析须同时验证 `type`、`deeplink_url` 对象 ID、回答的 `question_token` 与非空正文。回答的 deeplink 使用 `/question/{answer_id}`，这里的数字是回答 ID，不能当作父问题 ID。接口空壳或返回其他对象时继续已有读取路径，不能把推荐内容当作目标。

阅读页包含标题、正文 HTML、作者名/头像、图片和部分互动统计；没有作者 ID。实测回答的 `created` 对应普通页面 `updatedTime`，因此只保留为私有 `reader_timestamp`，不填 `published_at`。正文仍复用公式处理、图片去重和 Markdown 转换。普通 HTML 回答的发布时间读取 `createdTime`。

## 3. 访问失败与实测边界

2026-09-19 无 Cookie 实测：两条回答和一篇文章通过 Tardis 成功；其中一条回答与正常桌面网页的正文去空白后完全一致，均为 24 张正文图片。另一篇文章的 Tardis 返回空壳，9 月 20 日通过新 Chromium 路径完成解析：3597 字符正文、9 图。问题页取得统计和 3 条回答预览；主页取得用户名、头像和统计，不虚构主页发布时间。详情与样本见[探索验收记录](../../plans/2026-09-19-public-parser-exploration.process.md)。

旧回答 API 返回 `403/code=40353`，文章和问题 API 返回 `403/code=10003`，不能宣称 API 全部匿名可用。默认 WebKit/Chromium 和 Chrome TLS 指纹 HTTP 在本轮样本均失败；Crawl4AI 0.9.3 的 Chromium 配置成功后，通过消融定位到 `--disable-blink-features=AutomationControlled` 与匹配 UA 的 `sec-ch-ua` 必须同时存在。直接 Playwright 复现相同对象与正文后，复用现有浏览器管理器按需启动 Chromium，无需引入 Crawl4AI 依赖。

等待条件核对 `js-initialData` 中的目标对象，不仅等待 script 标签，也不把首个 403 当作最终结果（实测存在 403 → JS 导航 → 200）。每次使用新 context，保留请求 URL 安全检查、代理配置与目标身份校验，结束必定关闭 context。实际适配器三次文章和三次问题均成功；主页三次中两次成功、一次 6 秒就绪等待超时，仍有访问限制，不能承诺全量稳定。

本地运行需要安装 Chromium：仓库虚拟环境执行 `python -m playwright install chromium`。Dockerfile 已加入 Chromium 安装；本轮只在 macOS 本地验收，未构建/部署新镜像。原有 WebKit 认证与其他平台路径不随此次新增浏览器改变。

错误处理：

- 明确的 401 或 `40353` 表达当前入口要求登录。
- 其他 403 表达请求被拒绝或需要验证，不一律提示更新 Cookie。
- 404 表达该入口内容不存在；其他网络/服务错误保留可重试分类。
- 公开内容解析不再自动调用账号服务刷新指纹，也不在日志打印 Cookie 或原始 HTML。
- 页面带有“登录”文案不等于正文需要登录；只接受目标对象的结构化数据。

API 路径继续使用实际 include contract。回答正文成功后，问题回答/关注数可由各列表的 `paging.totals` 补充；统计补充失败不影响正文。账号 API 的既有能力不等于本轮重新完成了账号态验收。

---

## 4. 存档内容详解

### 4.1 通用字段

所有类型的内容都会包含以下基础字段：

| 字段 | 类型 | 说明 | 来源 |
| :--- | :--- | :--- | :--- |
| `platform` | string | 固定为 `\"zhihu\"` | 常量 |
| `content_type` | string | `article`, `question`, `answer`, `pin`, `user_profile` | URL 检测 |
| `content_id` | string | 知乎内部 ID | URL 提取或 API 返回 |
| `title` | string | 标题（Pin 为摘要） | API 或 HTML |
| `body` | string | Markdown 格式正文 | 经 `markdownify` 转换 |
| `author_name` | string | 作者昵称 | API `author.name` |
| `author_id` | string/null | 作者标识，匿名阅读页不提供 | API `author.url_token` / `id` |
| `cover_url` | string | 封面/题图/头像 URL | API 或提取首图 |
| `media_urls` | list | 正文中所有图片 URL | 正则提取 |
| `published_at` | datetime/null | 发布时间，匿名阅读页不提供 | API `created_time` 或 HTML `createdTime` |
| `tags` | list | 话题/标签 | API `topics` |
| `url` | string | 原始 URL | 用户输入 |

### 4.2 统计字段（stats）

不同类型包含的统计信息：

| 统计项 | Article | Question | Answer | Pin | User |
| :--- | :---: | :---: | :---: | :---: | :---: |
| `voteup_count` (点赞) | ✅ | ✅ | ✅ | - | ✅ (获赞总数) |
| `comment_count` (评论) | ✅ | ✅ | ✅ | ✅ | - |
| `thanks_count` (感谢) | - | - | ✅ | - | ✅ |
| `follower_count` (关注) | - | ✅ | - | - | ✅ |
| `answer_count` (回答数) | - | ✅ | - | - | ✅ |
| `visit_count` (浏览量) | - | ✅ | - | - | - |
| `reaction_count` (鼓掌) | - | - | - | ✅ | - |
| `repin_count` (转发) | - | - | - | ✅ | - |

数据来源：
- API 模式：直接从 JSON 的对应字段提取
- HTML 模式：从 `js-initialData` 中的 `initialState` 对象提取
- Tardis 模式：从 `renderHtml` 提取点赞、评论、收藏，以及回答对应的问题回答数；不提供上表全部字段

### 4.3 归档数据（archive）

每条内容会额外生成离线归档数据，包含：

```json
{
  \"version\": 2,
  \"type\": \"article\",
  \"title\": \"文章标题\",
  \"plain_text\": \"纯文本内容（无 HTML 标签）\",
  \"markdown\": \"Markdown 格式正文\",
  \"images\": [
    {\"url\": \"https://...\", \"type\": \"content\"},
    {\"url\": \"https://...\", \"type\": \"avatar\"}
  ],
  \"links\": [],
  \"stored_images\": []
}
```


---

### Q3: 关于评论数据

当前仅存储评论数量。完整评论列表需要额外的 API 请求，且数据量大，暂未实现。

---

## 6. 开发者参考

### 6.1 添加新的 Include 参数

如果需要获取更多字段，可以修改 `API_INCLUDE_PARAMS`：

```python
# backend/app/adapters/zhihu.py
API_INCLUDE_PARAMS = {
    \"answer\": \"content,excerpt,voteup_count,comment_count,...\",  # 添加你需要的字段
}
```

### 6.2 扩展 HTML 解析器

HTML 解析器位于 `backend/app/adapters/zhihu_parser/`：
- `public_reader.py` - 匿名 Tardis 阅读页解析
- `article_parser.py` - 文章解析
- `question_parser.py` - 问题解析
- `answer_parser.py` - 回答解析
- `pin_parser.py` - 想法解析
- `people_parser.py` - 用户主页解析
