# 知乎内容适配器完整文档

## 文档状态

active

## 适用范围

- 平台：知乎
- 当前代码：`backend/app/adapters/zhihu.py`
- 当前类：`ZhihuAdapter`
- 测试：`backend/tests/test_adapters/test_zhihu.py`

## 背景

知乎内容类型包括回答、文章、问题、想法、用户主页和收藏夹等。不同类型可能使用 API、HTML 解析或回退策略。该文档记录平台知识，不直接代表开发计划。

## 当前事实

当前适配器由 `ZhihuAdapter` 实现，并输出标准 `ParsedContent`。下文平台细节保留为知识库参考；如与代码不一致，以当前代码和测试为准。

## 与代码的关系

- 适配器注册：`backend/app/adapters/__init__.py`
- 解析实现：`backend/app/adapters/zhihu.py`
- 收藏同步：`backend/app/adapters/favorites/zhihu_fetcher.py`
- 测试样本：`backend/tests/data/zhihu/`

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

## 2. 解析策略

### 2.1 策略概览


| 内容类型 | 主要解析方式 | 回退方式 | 原因 |
| :--- | :--- | :--- | :--- |
| Answer（回答） | ✅ API 优先 | HTML | API 公开可用，无需签名 |
| User Profile（用户） | ✅ API 优先 | HTML | API 公开可用 |
| Column（专栏） | ✅ API 优先 | ❌ 无 | 基础信息 API 可用 |
| Collection（收藏夹） | ✅ API 优先 | ❌ 无 | 基础信息 API 可用 |
| Article（文章） | ✅ API 优先 | HTML | 通过 zhuanlan.zhihu.com 端点绕过了主站风控 |
| Question（问题） | API 尝试 | HTML、指纹刷新 | 当前真实样本中 API 返回 `10003`，HTML 返回 403；不得视为稳定可用 |
| Pin（想法） | ⚠️ HTML 唯一方式 | - | 无公开 API，仅能解析 HTML |

### 2.2 详细说明

#### ✅ API 优先类型（Answer / User Profile）

核心：
- 知乎的回答详情 API (`/api/v4/answers/{id}`) 完全公开，无需任何 Cookie 或签名即可访问
- 用户信息 API (`/api/v4/members/{id}`) 同样公开
- 文章 API 切换至专栏端点 (`zhuanlan.zhihu.com/api/articles/{id}`)，配合 `x-xsrftoken` 和浏览器指纹头可成功解析。
- 这些接口返回完整的 JSON 结构，包含统计信息

Include 参数配置：
```python
# Answer 完整参数
include=content,excerpt,voteup_count,comment_count,created_time,updated_time,thanks_count,relationship.is_author,is_thanked,voting

# User 完整参数
include=allow_message,answer_count,articles_count,follower_count,following_count,voteup_count,thanked_count,favorited_count,pins_count,question_count
```

优势：
- 稳定性高，不受页面改版影响
- 返回结构化数据，易于解析
- 包含完整的统计信息（点赞、评论等）

#### ⚠️ 高风控类型（Question / Pin）

原因：
- 问题 API（`/api/v4/questions`）和甚至普通网页访问，自 2024 年底起强制要求 `x-zse-96` 动态 HMAC 签名 + 有效 Cookie
- 即使提供 Cookie，缺少动态签名，API 仍会返回 `10003` 错误，HTML 请求则返回 `403 安全验证` 拦截。
- 实现签名算法成本高且不稳定（知乎持续更新算法）

HTML 回退机制：
1. 直接请求网页 URL（如 `https://zhuanlan.zhihu.com/p/676348421`）
2. 从 HTML 中提取 `<script id=\"js-initialData\">` 标签
3. 解析其中的 JSON 状态对象（与 API 返回的结构相同）

该回退只有在服务端 HTTP 请求实际获得包含 `js-initialData` 的页面时才成立。用户浏览器可打开页面，不等于后端 HTTP 客户端也能访问；不能把浏览器可见性当作解析成功证据。

---

## 3. 回退逻辑流程

```mermaid
graph TD
    A[用户提交 URL] --> B{检测内容类型}
    B --> C{是 Answer/User 类型?}
    C -->|是| D[尝试 API 解析]
    D --> E{API 成功?}
    E -->|是| F[返回结果]
    E -->|否| G[回退 HTML 解析]
    
    C -->|否| H{是 Article/Question?}
    H -->|是| I[尝试 API 后回退 HTML]
    H -->|否| J{是 Pin?}
    J -->|是| I
    J -->|否| K[API 解析 Column/Collection]
    
    G --> L{HTML 解析成功?}
    I --> L
    L -->|是| F
    L -->|否| M[抛出错误]
```

关键决策点：
1. 类型判断：基于 URL 模式自动识别内容类型
2. 策略选择：根据类型选择 API 或 HTML
3. API 失败处理：仅对 API 优先类型启用 HTML 回退
4. 错误分类：
   - 403/401 → `AuthRequiredAdapterError`（需要 Cookie）
   - 404 → `NonRetryableAdapterError`（内容不存在）
   - 其他 → `RetryableAdapterError`（可重试）

### 3.1 2026-07-28 真实验证

- 回答、专栏文章、用户主页通过结构化 API 成功解析，标题、正文、作者、图片、发布时间和统计均存在。
- 同一问题页在已配置登录 Cookie 下仍表现为：问题 API `403/code=10003`，普通 HTML `403`；自动刷新指纹后复验仍失败。因此本轮矩阵明确记为“不通过”，而不是添加未经验证的慢速浏览器兜底。
- 当前问题页失败属于知乎请求签名/风控边界，不是 URL 识别或数据库字段映射问题。

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
| `description` | string | Markdown 格式正文 | 经 `markdownify` 转换 |
| `author_name` | string | 作者昵称 | API `author.name` |
| `author_id` | string | 作者 URL Token | API `author.url_token` |
| `cover_url` | string | 封面/题图/头像 URL | API 或提取首图 |
| `media_urls` | list | 正文中所有图片 URL | 正则提取 |
| `published_at` | datetime | 发布时间 | API `created_time` |
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
- `article_parser.py` - 文章解析
- `question_parser.py` - 问题解析
- `answer_parser.py` - 回答解析
- `pin_parser.py` - 想法解析
- `people_parser.py` - 用户主页解析
