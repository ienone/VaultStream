# Twitter 适配器文档

## 功能概述

VaultStream 的 Twitter 适配器使用 FxTwitter API 解析和获取推文内容，无需认证即可获取公开推文的完整信息。

### 核心功能

- 无需认证 - 不需要 Twitter 账号、cookies 或 API 密钥
- 自动解析 - 自动识别和处理各种 Twitter URL 格式
- 完整数据 - 获取推文文本、作者、媒体、统计数据等所有信息
- 媒体支持 - 支持图片、视频、GIF 等多种媒体类型
- 统一存储 - 自动映射到统一的数据模型

## 支持的内容类型

- ✅ 纯文本推文
- ✅ 带图片的推文（单图/多图）
- ✅ 带视频的推文
- ✅ 带 GIF 的推文
- ✅ 图文混合推文

## URL 格式支持

适配器支持所有常见的 Twitter/X URL 格式：

```
https://twitter.com/user/status/123456
https://x.com/user/status/123456
https://x.com/user/status/123456?s=20
https://mobile.twitter.com/user/status/123456
```

## 返回的数据字段

### 基本信息

- `platform`: "twitter"
- `content_type`: "tweet"
- `content_id`: 推文 ID
- `clean_url`: 标准化后的 URL

### 内容信息

- `title`: 格式化的标题（@用户名 + 内容预览）
- `description`: 完整推文文本
- `author_name`: 作者显示名称
- `author_id`: 作者用户名
- `published_at`: 发布时间

### 媒体资源

- `cover_url`: 封面图（第一张图片或作者头像）
- `media_urls`: 所有媒体文件的 URL 列表

### 统计数据

- `stats.view`: 浏览次数
- `stats.like`: 点赞数
- `stats.share`: 转发数
- `stats.reply`: 评论数

### 元数据

`raw_metadata` 包含完整的 API 响应和扩展信息：

| 字段路径 | 说明 |
|---------|------|
| author.followers | 粉丝数 |
| author.following | 关注数 |
| author.verified | 认证状态 |
| author.banner_url | 横幅图 |
| author.description | 作者简介 |
| media[] | 完整媒体信息（尺寸、类型等） |
| poll | 投票数据（如有） |
| quote | 引用推文（如有） |
| lang | 语言代码 |

## 数据存储映射

### 字段映射表

| Twitter 字段 | 数据库字段 | 说明 |
|-------------|-----------|------|
| author.name | author_name | 作者显示名称 |
| author.screen_name | author_id | 作者用户名 |
| id | platform_id | 推文 ID |
| text | description | 推文文本 |
| created_at | published_at | 发布时间 |
| views | view_count | 浏览次数 |
| likes | like_count | 点赞数 |
| retweets | share_count | 转发数 |
| replies | comment_count | 评论数 |
| media[].url | media_urls | 媒体 URL 列表 |
| media[0].url | cover_url | 封面图 |

### Archive 结构

媒体文件会被处理并存储到归档结构中：

```json
{
  "archive": {
    "version": "1",
    "images": [
      {
        "url": "https://pbs.twimg.com/media/xxx.jpg",
        "width": 1920,
        "height": 1080,
        "stored_key": "vaultstream/blobs/sha256/ab/cd/...",
        "stored_url": "http://storage/path/to/image.webp",
        "sha256": "abcd1234...",
        "size": 123456,
        "content_type": "image/webp"
      }
    ]
  }
}
```

## 媒体处理

### 自动处理流程

当启用媒体处理时（`ENABLE_ARCHIVE_MEDIA_PROCESSING=True`），系统会：

1. 下载原始媒体文件
2. 转换为 WebP 格式（图片）
3. 计算内容哈希（SHA256）
4. 存储到对象存储（MinIO/S3）
5. 更新 archive 元数据

### 存储结构

- Content-addressed: 使用 SHA256 哈希作为文件名
- 路径格式: `vaultstream/blobs/sha256/ab/cd/abcd1234...webp`
- 去重: 相同内容只存储一次

## 配置选项

### 代理配置

如果需要通过代理访问 FxTwitter API：

```bash
# .env
HTTP_PROXY=http://127.0.0.1:7890
HTTPS_PROXY=http://127.0.0.1:7890
```

### 媒体处理配置

```bash
# .env
ENABLE_ARCHIVE_MEDIA_PROCESSING=True
ARCHIVE_IMAGE_WEBP_QUALITY=85
ARCHIVE_IMAGE_MAX_COUNT=20
```

## API 实现

### FxTwitter API

适配器使用 FxTwitter 的公开 API：

```
https://api.fxtwitter.com/{username}/status/{tweet_id}
```

### 时间格式

FxTwitter 返回的时间格式：
```
Sat Jan 03 02:37:01 +0000 2026
```

适配器会自动解析为 Python `datetime` 对象。

### 错误处理

适配器会处理以下错误情况：

| 错误类型 | 说明 | 处理方式 |
|---------|------|---------|
| 404 | 推文不存在或已删除 | 抛出 NonRetryableAdapterError |
| 429 | API 请求频率限制 | 抛出 RetryableAdapterError |
| 5xx | 服务器错误 | 抛出 RetryableAdapterError |
| 网络错误 | 超时、连接失败 | 抛出 RetryableAdapterError |

## 使用示例

### Python 代码

```python
from app.adapters.twitter_fx import TwitterFxAdapter

# 创建适配器
adapter = TwitterFxAdapter()

# 解析推文
url = "https://x.com/username/status/123456"
result = await adapter.parse(url)

print(f"作者: {result.author_name}")
print(f"内容: {result.description}")
print(f"媒体: {len(result.media_urls)} 个")
print(f"点赞: {result.stats['like']}")
```

### Telegram Bot 使用

发送推文链接到 Bot，系统会自动：
1. 识别为 Twitter 链接
2. 调用 FxTwitter 适配器解析
3. 下载并处理媒体
4. 存储到数据库
5. 发送到指定频道

## 测试

运行测试脚本验证功能：

```bash
python tests/test_twitter_fx.py
```

## 故障排查

### 403 错误

原因: User-Agent 或请求头不正确  
解决: 适配器已自动配置，检查网络或代理设置

### 404 错误

原因: 推文不存在、已删除或账号被封禁  
解决: 确认推文 URL 正确且推文仍然存在

### 超时错误

原因: 网络连接问题或服务响应慢  
解决: 
- 检查网络连接
- 配置代理（如需要）
- 增加超时时间（默认 30 秒）

### 数据未正确存储

原因: 统计数据字段映射问题  
解决: 检查 `raw_metadata` 中的完整数据，确认字段名称

## 注意事项

### 服务依赖

- 第三方服务: 依赖 FxTwitter 服务可用性
- 公开数据: 仅能获取公开推文，无法访问私密内容
- 请求频率: 建议合理控制请求频率

### 数据时效性

- 统计数据（点赞、转发等）为获取时的快照
- 推文内容可能被作者修改或删除
- 建议定期更新数据


## 参考资源

- [FxTwitter GitHub](https://github.com/FixTweet/FxTwitter)
- [FxTwitter API 文档](https://github.com/FixTweet/FxTwitter/wiki/API)
- [VaultStream 项目文档](../README.md)
