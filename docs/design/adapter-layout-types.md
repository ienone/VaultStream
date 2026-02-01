# 适配器 Layout Type 配置文档

本文档记录各平台适配器的 `layout_type` 设置规则，方便查阅和修改。

## Layout Type 枚举值

| 值 | 说明 | 前端渲染 |
|---|---|---|
| `article` | 长文布局 | Markdown 渲染，带目录 |
| `video` | 视频布局 | 视频播放器（目前仅封面） |
| `gallery` | 画廊布局 | 图片轮播/网格 |
| `audio` | 音频布局 | 音频播放器（待实现） |
| `link` | 纯链接 | 链接卡片（待实现） |

---

## Bilibili 适配器

| 内容类型 | content_type | layout_type | 说明 |
|---------|-------------|-------------|------|
| 视频 | `video` | `gallery` | 当前只存封面，不存视频文件 |
| 专栏文章 | `article` | `article` | Markdown 长文渲染 |
| 动态 | `dynamic` | `gallery` / `article` | 智能判断：有标题且正文>500字为article，否则gallery |
| 番剧 | `bangumi` | `gallery` | 封面展示 |
| 直播 | `live` | `gallery` | 封面展示 |

---

## 微博适配器

| 内容类型 | content_type | layout_type | 说明 |
|---------|-------------|-------------|------|
| 微博状态 | `status` | `gallery` | 图片/视频为主 |
| 用户主页 | `user_profile` | `gallery` | 用户头像展示 |

---

## Twitter/X 适配器

| 内容类型 | content_type | layout_type | 说明 |
|---------|-------------|-------------|------|
| 推文 | `tweet` | `gallery` | 图片/短文为主 |

---

## 知乎适配器

| 内容类型 | content_type | layout_type | 说明 |
|---------|-------------|-------------|------|
| 回答 | `answer` | `article` | 长文 Markdown 渲染 |
| 文章 | `article` | `article` | 专栏文章 |
| 问题 | `question` | `article` | 问题描述 |
| 想法 | `pin` | `gallery` | 图片/短文为主 |
| 用户主页 | `user_profile` | `gallery` | 用户头像展示 |
| 专栏 | `column` | `article` | 专栏列表 |
| 收藏夹 | `collection` | `gallery` | 收藏内容列表 |

---

## 小红书适配器

| 内容类型 | content_type | layout_type | 说明 |
|---------|-------------|-------------|------|
| 笔记 | `note` | `gallery` | 图片/视频为主 |
| 用户主页 | `user_profile` | `gallery` | 用户头像展示 |

---

## 通用适配器 (UniversalAdapter)

通用适配器使用智能判断逻辑：

### 判断优先级

1. **有 video_url** → `video`
2. **有 audio_url** → `audio`
3. **图片 ≥ 2 且正文 < 500字** → `gallery`
4. **正文 > 1000字** → `article`
5. **LLM 检测结果**（作为参考）
6. **默认** → `article`

### LLM 提取字段

通用适配器的 LLM 提取 Schema 包含以下用于类型判断的字段：

```json
{
  "video_url": "主视频URL",
  "audio_url": "主音频URL", 
  "detected_type": "article|video|gallery|audio"
}
```

---

## 用户手动覆盖

用户可以通过以下方式覆盖系统检测的 layout_type：

1. **分享接收界面**：选择显示样式
2. **内容编辑界面**：修改布局类型
3. **详情页编辑**：调整布局类型

用户覆盖值存储在 `layout_type_override` 字段，优先级最高。

---

## 前端兼容回退

当后端未返回 layout_type 时，前端使用以下回退逻辑：

```dart
String _fallbackLayoutType() {
  if (isBilibili) {
    if (contentType == 'article' || contentType == 'opus') return 'article';
    return 'gallery';
  }
  if (isWeibo || isTwitter || isXiaohongshu) return 'gallery';
  if (isZhihu) {
    if (contentType == 'article' || contentType == 'answer') return 'article';
    if (contentType == 'pin') return 'gallery';
    return 'article';
  }
  return 'article';
}
```
