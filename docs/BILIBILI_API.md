# Bilibili API Reference

本文档记录了 BetterShare 中使用的 Bilibili API 接口及其数据结构。

## 1. 视频信息 (Video)
- Endpoint: `https://api.bilibili.com/x/web-interface/view`
- Method: GET
- Params: `bvid` (BV号) 或 `aid` (av号)
- Key Fields:
  - `title`: 标题
  - `desc`: 简介
  - `pic`: 封面图 URL
  - `owner.name`: 作者名
  - `owner.mid`: 作者 UID
  - `stat`: 互动数据 (`view`, `like`, `favorite`, `coin`, `share`, `reply`, `danmaku`)
  - `pubdate`: 发布时间戳

## 2. 专栏文章 (Article)
- Endpoint: `https://api.bilibili.com/x/article/view`
- Method: GET
- Params: `id` (cv号，不带cv前缀)
- Key Fields:
  - `title`: 标题
  - `summary`: 摘要
  - `banner_url`: 文章横幅图
  - `author.name`: 作者名
  - `author.mid`: 作者 UID
  - `stats`: 互动数据 (`view`, `like`, `favorite`, `coin`, `reply`, `share`)
  - `publish_time`: 发布时间戳
  - `image_urls`: 图片列表

## 3. 番剧/电影 (Bangumi/PGC)
- Endpoint: `https://api.bilibili.com/pgc/view/web/season`
- Method: GET
- Params: `season_id` (ss号数字) 或 `ep_id` (ep号数字)
- Key Fields:
  - `title`: 标题
  - `evaluate`: 简介
  - `cover`: 封面图
  - `stat`: 互动数据 (`views`, `likes`, `favorites`, `coins`, `reply`, `share`, `danmakus`)
  - `type_desc`: 类型描述 (如 "番剧", "电影")

## 4. 动态 (Dynamic/Opus)
- Endpoint: `https://api.bilibili.com/x/polymer/web-dynamic/v1/opus/detail`
- Method: GET
- Params: 
  - `id`: 动态 ID
  - `features`: 大概率需要包含特定的功能标识字符串（如 `onlyfansVote,onlyfansAssetsV2...`）以获取完整数据
- Data Structure (Polymer API):
  - `item.basic`: 基础信息回退 (`title`, `uid`)
  - `item.modules`: 模块化列表，需映射为 `module_xxx` 结构
    - `module_author`: 作者信息 (`name`, `mid`, `pub_ts`)
    - `module_dynamic.major.opus`: 内容主体 (`title`, `content.paragraphs`, `pics`)
    - `module_stat`: 互动数据 (`like.count`, `comment.count`, `forward.count`)
    - `module_title`: 标题模块 (`text`)
- Fallback Logic:
  - 标题: `opus.title` -> `module_title.text` -> `basic.title`
  - 作者ID: `module_author.mid` -> `basic.uid`

## 5. 音频 (Audio) - *Planned*
- Endpoint: `https://www.bilibili.com/audio/music-service-c/web/song/info`
- Method: GET
- Params: `sid` (au号数字)

## 6. 直播 (Live)
- Endpoint: `https://api.live.bilibili.com/xlive/web-room/v1/index/getRoomBaseInfo`
- Method: GET
- Params: `room_ids` (房间号，支持短号)
- Key Fields:
  - `title`: 直播间标题
  - `description`: 直播间描述
  - `uname`: 主播名
  - `uid`: 主播 UID
  - `online`: 人气值
  - `live_status`: 直播状态 (0:未开播, 1:直播中, 2:轮播中)
  - `cover`: 封面图
