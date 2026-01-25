# 小红书内容适配器文档

VaultStream 的小红书适配器通过调用小红书内部 API（配合 `xhshow` 库进行签名）或解析网页 SSR 数据，支持抓取笔记（Note）、视频（Video）以及用户主页（User Profile）。

---

## 1. 支持的 URL 模式

| 模式 | 示例 | 备注 |
| :--- | :--- | :--- |
| 笔记详情 (Web) | `xiaohongshu.com/explore/{note_id}` | 支持 `discover/item` 兼容 |
| 短链接 (APP 分享) | `xhslink.com/{code}` | 自动解析还原 |
| 用户主页 | `xiaohongshu.com/user/profile/{user_id}` | 需要 `xsec_token` |

---

## 2. 解析逻辑与策略

由于小红书的接口安全性较高，适配器采用了双重兜底解析逻辑：

### 2.1 签名 API 请求 (Hybrid)
适配器集成了 `xhshow` 库来生成必要的签名头（如 `x-s`）。
- 主要接口: `/api/sns/web/v1/feed` (笔记)、`/api/sns/web/v1/user/otherinfo` (用户信息)。
- 优势: 返回数据结构最完整，包含高清视频流、互动数等。

### 2.2 SSR 数据提取 (Fallback)
当 API 被风控或签名校验失败时，适配器会尝试访问网页原文，并从 `window.__INITIAL_STATE__` 中提取 JSON 数据。
- 作用: 提高解析笔记的成功率。

---

## 3. 核心功能特性

### 3.1 媒体获取
- 多图抓取: 自动识别图文笔记中的所有图片，并优先选择高清、无水印版本。
- 视频解析: 支持获取小红书原生视频的最高清晰度 MP4 流，并提取封面。
- WebP 转化: 适配系统媒体处理层，自动本地化缓存图片。

### 3.2 文本净化
- 标题隔离: 自动区分笔记标题与正文。
- 标签剥离: 识别 `#话题#` 格式并将其提取到 `source_tags`，同时在正文中净化掉这些干扰字符。
- Markdown 渲染: 自动将图文分布渲染为结构化的 Markdown 存档。

---

## 4. 数据映射 (stats)

| 统一字段 | 对应小红书字段 | 说明 |
| :--- | :--- | :--- |
| `like` | `liked_count` | 点赞数 |
| `collect` | `collected_count` | 收藏数 |
| `comment` | `comment_count` | 评论数 |
| `share` | `share_count` | 分享数 |

---

## 5. 配置说明

### 5.1 Cookie 配置 (必需)
小红书适配器必须配置登录状态下的 Cookie 才能稳定解析。

```env
# .env 文件
XIAOHONGSHU_COOKIE="webId=...; gid=...; a1=...; web_session=...;"
```

---

## 6. 开发者参考

- 核心代码: `backend/app/adapters/xiaohongshu.py`
- 主要逻辑: 
    - `_fetch_note`: 优先 API，失败则回退至 SSR。
    - `_build_note_archive`: 跨平台通用的归档模型构建流程。
