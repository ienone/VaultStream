# Bilibili 内容适配器文档

## 文档状态

active

## 适用范围

- 平台：Bilibili
- 当前代码：`backend/app/adapters/bilibili.py`
- 当前类：`BilibiliAdapter`
- 测试：`backend/tests/test_adapters/test_bilibili.py`

## 背景

Bilibili 内容类型包含视频、动态、专栏、番剧、直播等多种 URL 形态。该文档记录平台 URL、字段映射和解析策略知识，不代表新增开发计划。

## 当前事实

2026-09-13 新增 `favorites/bilibili_fetcher.py`，读取已保存 SESSDATA，通过 nav 验证当前账号，发现本人创建的视频收藏夹并按固定 20 项页面续接。游标包含 mid、收藏夹 ID、页码和页内偏移，防止切换账号后误用旧进度。只覆盖视频收藏夹，不包含收藏的他人合集、课程或其他平台收藏类型。不可用/非视频项在同步结果中明确跳过，不删除本地内容。

契约参考作者发布的 [bpi-rs 收藏夹结构](https://docs.rs/bpi-rs/latest/src/bpi_rs/fav/info.rs.html)、[内容分页实现](https://docs.rs/bpi-rs/latest/src/bpi_rs/fav/list.rs.html)、[nav 结构](https://docs.rs/bpi-rs/latest/src/bpi_rs/login/login_info/nav.rs.html)。无登录公开请求验证：示例用户 7792521 的 created/list-all 与示例收藏夹 1052622027 的 resource/list 均返回 HTTP 200/code=0；内容页明确包含 medias/has_more 和 bvid/fav_time/upper 等字段，匿名 nav 返回 -101。私人收藏与长期账号态未进行真实账号验收。

已导入内容按规范视频 URL 去重，并在来源上下文保留收藏夹 ID/标题。完整扫描到末页后清空游标，下轮重新从首页扫描新增收藏；分页是实时列表，平台并发增删时不是一致性快照，下一轮扫描负责补齐，不能宣称平台级增量快照保证。

当前适配器由 `BilibiliAdapter` 实现，并通过 `ParsedContent` 输出标准内容结构。下文平台细节来源于迁移前 adapter 文档，作为知识库参考；如与代码不一致，以当前代码和测试为准。

## 与代码的关系

- 适配器注册：`backend/app/adapters/__init__.py`
- 解析实现：`backend/app/adapters/bilibili.py`
- 解析器辅助：`backend/app/adapters/bilibili_parser/*`
- 测试样本：`backend/tests/data/bilibili/`

## 使用方式

开发或修复 Bilibili 解析前，先阅读本知识库和现有测试；涉及行为变更时应先在 `../../plans/` 建 plan，并同步更新 adapter 测试。

## 已知限制

2026-09-10：视频解析新增按 URL 的分 P 选择 cid，读取 player/playurl 的单段 MP4 来源、player/v2 的章节及字幕。字幕由不含平台 Cookie 的独立客户端经 safe_fetch 下载，限 4 MiB；ai-zh 明确标注平台 AI 字幕。媒体及时间片按 `bilibili:{bvid}:{cid}` 关联。可选接口失败或不支持的分段流写入 rich_payload.media_status，不伪装成完整成功。真实样本已得到一个视频候选、10 个章节、661 条字幕；正式入库、远端播放失效刷新、浏览器播放和时间点搜索仍待验收。

同日正式入库复核发现旧 player/v2 返回过不相干的字幕，已替换为 player/wbi/v2，并校验 bvid/cid 与 view 声明的字幕轨 ID。内容 16 已完成正式导入、视频归档、正确字幕及时间点搜索；浏览器播放仍待验收。字幕以可读时间段进入 chunks，并在每段 cues 中保留原始逐条时间与文字，避免把数百条短字幕逐条调用 embedding。

- 平台接口和动态结构可能变化。
- Cookie、代理和反爬策略可能影响真实抓取。
- 下文部分平台细节可能随 Bilibili 上游变更而过期，需要以测试样本和当前代码复核。

VaultStream 的 Bilibili 适配器支持解析视频、专栏文章、动态（Opus）、番剧、直播等多种内容类型。它主要通过 Bilibili 官方 API 获取结构化数据。

---

## 1. 支持的 URL 类型

适配器会自动识别并净化以下 URL 模式（包含 `b23.tv` 短链解析）：

| 类型 | URL 模式 | 示例 |
| :--- | :--- | :--- |
| 视频 (Video) | `bilibili.com/video/BV...` 或 `av...` | `https://www.bilibili.com/video/BV1xxxxxxx` |
| 专栏文章 (Article) | `bilibili.com/read/cv...` | `https://www.bilibili.com/read/cv123456` |
| 动态/图文 (Dynamic/Opus) | `bilibili.com/opus/...` 或 `t.bilibili.com/...` | `https://www.bilibili.com/opus/123456789` |
| 番剧 (Bangumi) | `bilibili.com/bangumi/play/ss...` 或 `ep...` | `https://www.bilibili.com/bangumi/play/ss123` |
| 直播 (Live) | `live.bilibili.com/{room_id}` | `https://live.bilibili.com/123` |
| 课程 (Cheese) | `bilibili.com/cheese/ss...` 或 `ep...` | `https://www.bilibili.com/cheese/ss123` |

---

## 2. 解析策略

Bilibili 适配器主要依赖官方 Web API，但在处理动态时使用了更先进的 Polymer 接口以获取最完整的图文内容。

### 2.1 接口概览

| 内容类型 | 主要 API 端点 | 说明 |
| :--- | :--- | :--- |
| 视频 | `x/web-interface/view` | 获取视频基础信息及互动统计 |
| 专栏 | `x/article/viewinfo` | 获取文章摘要及基本信息 |
| 动态/图文 | `x/polymer/web-dynamic/v1/opus/detail` | **Polymer 接口**：支持提取完整的富文本和高清图片 |
| 番剧 | `pgc/view/web/season` | 获取 PGC 内容（番剧、电视剧、电影） |
| 直播 | `xlive/web-room/v1/index/getRoomBaseInfo` | 支持通过房间号/短号获取实时信息 |

### 2.2 动态解析优势 (Opus)

针对新版 Bilibili 动态（Opus），我们实现了深层递归解析：
- 结构化提取：识别 Heading、Paragraph、Image、Quote、Separator 等多种富文本块。
- 文本清洗：自动去除零宽字符（\u200b）、还原 HTML 转义字符、压缩多余换行。
- Markdown 转换：将解析出的富文本块自动转换为标准的 Markdown 格式，便于存档和搜索。

### 2.3 Opus 布局判定与结构差异

Bilibili Opus 接口返回的数据结构存在差异，直接决定了前端展示形态 (`layout_type`)：

| Opus 类型 | 典型来源 | 接口特征 (Polymer API) | 布局类型 | 前端展示 |
| :--- | :--- | :--- | :--- | :--- |
| **Opus 文章** | 专栏文章 (`read/cv`) 重定向 | 正文图片**嵌入**在 `MODULE_TYPE_CONTENT` 的段落 (`paragraphs`) 中。 | `ARTICLE` | 长文排版 (左侧文本) |
| **Opus 动态** | 手机端发布的九宫格图文 | 图片位于 **`MODULE_TYPE_TOP`** 的相册组件 (`display.album.pics`) 中，正文仅含文本。 | `GALLERY` | 画廊排版 (左侧图片) |

**解析逻辑**：
适配器会优先检查 `module_content` 的段落中是否包含嵌入图片。若有，则判定为文章；否则检查 `module_top` 是否有相册图片，若有则判定为画廊。

---

## 3. 回退逻辑与安全性

### 3.1 短链还原
遇到 `b23.tv` 格式的短链时，适配器会自动发起一次 HEAD 请求以还原真实 URL，确保后续解析准确。

### 3.2 数据裁剪 (Pruning)
为了防止数据库空间浪费，对于大型合辑 (UGC Season) 或长番剧，适配器会自动裁剪冗余的列表数据（如仅保留前 10 个视频/剧集的信息），只记录总数。

### 3.3 错误处理分类
- 403/-403: `AuthRequiredAdapterError`（需要配置 Cookie 或内容受限）
- 404/-404: `NonRetryableAdapterError`（内容不存在或已删除）
- 其他网络/API 错误: `RetryableAdapterError`

---

## 4. 存档内容详解

### 4.1 通用字段映射

| 字段 | 说明 | 来源 |
| :--- | :--- | :--- |
| `platform` | 固定为 `\"bilibili\"` | 常量 |
| `content_type` | `video`, `article`, `dynamic`, `bangumi`, `live` | 检测结果 |
| `content_id` | 唯一 ID（如 BV号、cv号） | URL/API |
| `title` | 标题 | API 标题字段 |
| `description` | 简介/正文 | API 描述或 Opus 段落 |
| `published_at` | 发布时间 | API 时间戳转换 |
| `stats` | 互动统计（如下表） | API 统计对象 |

### 4.2 统计字段 (stats)

| 统计项 | Video | Article | Opus | Bangumi | Live |
| :--- | :---: | :---: | :---: | :---: | :---: |
| `view` (播放/浏览) | ✅ | ✅ | ✅ | ✅ | ✅ (人气) |
| `like` (点赞) | ✅ | ✅ | ✅ | ✅ | - |
| `coin` (投币) | ✅ | ✅ | - | ✅ | - |
| `favorite` (收藏) | ✅ | ✅ | - | ✅ | - |
| `reply` (评论) | ✅ | ✅ | ✅ | ✅ | - |
| `danmaku` (弹幕) | ✅ | - | - | ✅ | - |
| `share` (分享) | ✅ | ✅ | ✅ | ✅ | - |

---

## 5. 配置与权限

### 5.1 Cookie 配置（可选）
某些内容（如 1080P+ 资源元数据、私密视频、会员番剧）需要有效的 Bilibili Cookie。

```env
# .env 文件
BILIBILI_COOKIE=\"SESSDATA=...; bili_jct=...; buid=...\"
```

### 5.2 代理配置
如果部署环境无法直接访问 Bilibili API，建议配置 HTTP 代理。

---

## 6. 开发者参考

### 6.1 核心组件
- `bilibili.py`: 核心适配层，负责 API 调用和数据分发。
- `detect_content_type`: 使用正则和短链还原技术识别类型。
- `_render_markdown`: 将复杂的 Opus 块结构扁平化为 Markdown。

### 6.2 扩展建议
- 增加音频 (Audio) 类型的完整支持。
- 完善动态中的投票 (Vote) 和外链跳转 (Link) 解析。

## 7. 2026-07-28 真实验证与字段修正

- 真实视频、番剧、直播样本均通过只读解析接口。
- 视频和直播使用 `video` 布局；视频时长写入 `extra_stats.duration_seconds`，分区名写入 `source_tags`。
- 直播映射开播时间、父/子分区和标签；封面优先 `cover`，其次 `background`。本次直播样本这两个字段均为空，因此不伪造封面；当前房间接口也未返回主播头像。
- 番剧本次保持 `gallery`；后续若需要播放型布局，应先明确“只有封面”与“可播放媒体”的前端 contract。

视频 canonical 使用 `https://www.bilibili.com/video/{视频ID}/`；默认 p=1 省略，其他正整数分 P 保留并去掉前导零。网页/移动域名、尾斜杠、追踪参数不再使同一分 P 重复收藏，无效分 P 明确报错。该规则不实现 AV/BV 互转，其他历史库的旧 canonical 需单独核对。

多分 P 视频标题包含平台分集序号和 pages.part 名称，单分 P 保持原视频标题；rich_payload 同时保存 video_page、video_page_title、video_page_count。真实 BV1Gr4y187aS 前两节分别显示“P1 课程简介”“P2 01 线性方程组”，时长 82/631 秒，媒体 cid 分别 710789626/31541103270；没有将合集总时长误用为当前分 P 时长。

2026-09-13 后续已获账号授权，Bilibili 本人收藏实际读取两条并返回续接游标及集合身份；此小批正向验收不等于全量或长期会话验收。
