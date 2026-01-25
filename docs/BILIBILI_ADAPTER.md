# Bilibili 内容适配器文档

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
