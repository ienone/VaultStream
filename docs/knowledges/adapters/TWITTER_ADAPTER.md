# Twitter / X 内容适配器

## 文档状态

active

## 适用范围

- 平台：Twitter / X
- 当前代码：`backend/app/adapters/twitter.py`
- 当前类：`TwitterAdapter`
- 测试：`backend/tests/test_adapters/test_twitter.py`

## 背景

Twitter / X 页面结构、公开接口和访问限制变化频繁，适配器文档需要把当前代码事实和旧方案设想分开记录。本文用于说明当前 `TwitterAdapter` 的解析边界、数据映射和已知限制，避免继续引用已经不存在的 FxTwitter 专用适配器路径。

## 当前事实

当前实现使用 `TwitterAdapter`，位于 `backend/app/adapters/twitter.py`。旧版文档曾描述过 FxTwitter 专用适配器命名和路径；该描述已过期，不应再作为代码事实引用。

适配器支持标准 Twitter/X status URL，并通过第三方公开接口和内部解析逻辑提取公开推文内容。具体可用性受上游服务、网络和代理配置影响。

## 支持的 URL

- `https://twitter.com/{user}/status/{id}`
- `https://x.com/{user}/status/{id}`
- `https://mobile.twitter.com/{user}/status/{id}`

## 数据映射

- `platform`: `twitter`
- `content_type`: 推文类型
- `title`: 基于作者和正文生成的预览标题
- `body`: 推文正文
- `author_name` / `author_id`: 作者显示名和 handle
- `published_at`: 推文发布时间
- `media_urls`: 推文图片、视频或动图媒体
- `extra_stats`: 浏览、点赞、转发、回复、收藏等平台统计
- `archive_metadata`: 平台原始数据和标准归档结构

## 与代码的关系

- 适配器注册：`backend/app/adapters/__init__.py`
- 解析输出：`backend/app/adapters/base.py` 的 `ParsedContent`
- 内容入库：`backend/app/services/content_service.py`
- 媒体归档：`backend/app/media/processor.py`

## 已知限制

- 公开接口和上游格式可能变化。
- 需要代理时依赖 `settings.http_proxy` / `settings.https_proxy`。
- 媒体归档是否执行取决于后端媒体配置。

## 2026-07-28 真实验证与字段修正

- 文本、图片、引用和视频四个真实样本均通过当前 FxTwitter 结构化接口解析。
- 布局按媒体事实选择：纯文本/引用为 `article`，图片为 `gallery`，视频为 `video`；纯文本不再用作者头像伪造封面。
- 引用推文映射为前端已有 contract `rich_payload.quoted_content`；投票原始结构保留在 `rich_payload.poll`。
- 原生媒体之外的外链缩略图可作为封面候选，但不会被误认为正文图片。
- hashtag 写入 `source_tags`；浏览、点赞、转发、回复进入通用统计，书签等平台统计保留在 `extra_stats`。

## 使用方式

这是平台知识库文档，不是开发计划。修改 Twitter 解析策略前，应先在 `../../plans/` 建立 plan，并同步更新测试。
