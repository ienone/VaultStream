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

2026-09-13 实现选择：移除独立 CLI 认证与无游标桥接后，新增 `favorites/twitter_fetcher.py` 和共享 `twitter_web.py`。用户在账号页显式保存 auth_token/ct0；浏览器只注入这份服务端会话，不自动读取用户浏览器。个人书签使用当前 X 网页发出的 Bookmarks 请求，沿用网页 query ID、features 和请求头，仅以固定 count=50 和已保存 cursor 续页；页内偏移避免调小批量时漏项。私有收藏夹尚未接入。

| 方案 | 依据与取舍 |
| --- | --- |
| 官方 OAuth API | [官方书签说明](https://docs.x.com/x-api/posts/bookmarks/introduction)要求用户 OAuth；授权流程尚未建立，未把它设为唯一路线。 |
| 独立 CLI | [作者实现](https://raw.githubusercontent.com/public-clis/twitter-cli/main/twitter_cli/client.py)包含独立登录和浏览器凭据提取，不符合统一持久会话；旧桥接已删除。 |
| 固定 GraphQL 客户端 | [Twikit](https://github.com/d60/twikit)提供 Bookmarks 游标与公开协议线索，但硬编码查询和请求特征需要持续跟踪。 |
| 当前网页请求 | 本轮采用；服务端浏览器加载 X 自身请求，挑战、失效或响应结构变化明确停止，不切换替代接口。 |

已保存登录时，`TwitterAdapter` 与书签共用网页会话及条件刷新写入。正文、note_tweet、引用、图片、MP4 和统计进入既有 ParsedContent；读取失败不退回匿名 FxTwitter。未配置登录时仍使用原公开解析入口。两种已发布 Bookmarks/TweetDetail 时间线协议各自显式验证，未知或同时出现的根结构失败；这不是字段猜测或异常吞掉。

本轮真实浏览器匿名访问已得到登录跳转和 auth_required；成功账号分页、长期会话以及私有推文尚未实测。隔离数据库与协议回归覆盖页内续接、账号切换、坏分页、密钥脱敏、长正文与视频映射、已登录失败不降级。网页方案仍受服务端浏览器安装、网络和平台访问限制影响。

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

## 已保存会话实测与二维码登录调查

用户随后保存 X Cookie，并授权核验。实际检查 auth_token/ct0 均非空；未发现无等号片段、重复必需字段或粘连的 Cookie 赋值。真实书签读取两批各两条，续接后 ID 无重叠；同一网页登录解析一条推文获得正文。无需修正或重新拼接用户凭据，未输出账号标识或收藏正文。

[X 官方 Passkey 文档](https://help.x.com/en/managing-your-account/how-to-use-passkey)说明以 WebAuthn 公私钥验证登录，需要先在账号设备启用 Passkey。[X 个人二维码](https://help.x.com/en/using-x/qr-codes)用于打开个人资料，不是登录授权码。[FIDO 跨设备认证](https://fidoalliance.org/passkeys/)要求通过 BLE 验证物理接近。因此不能把远程无头浏览器的 Passkey 二维码包装为通用服务器扫码登录；若实现本机交互式登录，需要由本机真实浏览器/系统完成 Passkey，再保存成功会话。尚未核实微博式独立二维码创建/手机确认/服务端轮询流程，不能宣称已实现。
