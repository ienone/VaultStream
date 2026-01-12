# 知乎内容适配器 API 文档

VaultStream 的知乎适配器支持解析知乎的专栏文章、问答、想法（Pin）及用户主页信息。

## 1. 支持的 URL 类型

适配器会自动识别以下 URL 模式：

- **专栏文章 (Article)**: `https://zhuanlan.zhihu.com/p/{article_id}`
- **问题 (Question)**: `https://www.zhihu.com/question/{question_id}`
- **回答 (Answer)**: `https://www.zhihu.com/question/{question_id}/answer/{answer_id}` 或 `https://www.zhihu.com/answer/{answer_id}`
- **想法 (Pin)**: `https://www.zhihu.com/pin/{pin_id}`
- **用户主页 (People)**: `https://www.zhihu.com/people/{url_token}`

## 2. 配置

需要在 `.env` 文件或系统环境变量中配置知乎 Cookie 以绕过部分反爬限制及获取完整数据。

```env
ZHIHU_COOKIE="您的完整 Cookie 字符串 (包含 z_c0, _xsrf 等)"
```

## 3. 解析结果数据结构

适配器返回统一的 `ParsedContent` 对象，主要字段映射如下：

### 通用字段
- `platform`: "zhihu"
- `content_type`: "article", "question", "answer", "pin", "user_profile"
- `content_id`: 唯一 ID
- `title`: 标题（Pin 为截取的摘要）
- `description`: 正文内容（Markdown 格式）
- `author_name`: 作者昵称
- `author_id`: 作者 urlToken 或 ID
- `cover_url`: 封面图（文章题图、回答首图、Pin 首图、用户头像）
- `media_urls`: 正文中提取的所有图片 URL 列表
- `published_at`: 创建时间
- `tags`: 话题列表 (Topics)

### 统计字段 (stats)
| 字段 | 说明 | 适用类型 |
| --- | --- | --- |
| `voteup_count` | 赞同数 | Article, Answer, People |
| `comment_count` | 评论数 | All |
| `follower_count` | 关注者数 | Question, People |
| `visit_count` | 浏览量 | Question |
| `answer_count` | 回答数 | Question |
| `reaction_count`| 鼓掌/反应数 | Pin |
| `repin_count` | 转发数 | Pin |

### 原始数据
`raw_metadata` 字段包含从 `js-initialData` 中提取的完整原始 JSON 对象，供后续深度分析使用。

## 4. 前端展示适配

- **Article / Answer**: 使用 Markdown 排版渲染，支持侧边栏目录（TOC）。
- **Pin / Question**: 使用类似 Twitter/微博 的图文流展示布局，强调多图预览与短文阅读。
- **User Profile**: 展示用户头像、签名及基本统计信息。
