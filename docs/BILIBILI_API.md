# Bilibili API Reference

本文档记录了 BetterShare 中使用的 Bilibili API 接口及其数据结构。

## 1. 视频信息 (Video)
- **Endpoint**: `https://api.bilibili.com/x/web-interface/view`
- **Method**: GET
- **Params**: `bvid` (BV号) 或 `aid` (av号)
- **Key Fields**:
  - `title`: 标题
  - `desc`: 简介
  - `owner.name`: 作者名
  - `stat`: 互动数据 (view, like, favorite, coin, reply, danmaku)
  - `pubdate`: 发布时间戳

## 2. 专栏文章 (Article)
- **Endpoint**: `https://api.bilibili.com/x/article/view`
- **Method**: GET
- **Params**: `id` (cv号，不带cv前缀)
- **Key Fields**:
  - `title`: 标题
  - `summary`: 摘要
  - `author.name`: 作者名
  - `stats`: 互动数据 (view, like, favorite, coin, reply, share)
  - `publish_time`: 发布时间戳
  - `image_urls`: 图片列表

## 3. 番剧/电影 (Bangumi/PGC)
- **Endpoint**: `https://api.bilibili.com/pgc/view/web/season`
- **Method**: GET
- **Params**: `season_id` (ss号数字) 或 `ep_id` (ep号数字)
- **Key Fields**:
  - `title`: 标题
  - `evaluate`: 简介
  - `stat`: 互动数据 (views, likes, favorites, coins, reply, share, danmakus)
  - `cover`: 封面图
  - `type_desc`: 类型描述 (如 "番剧", "电影")

## 4. 动态 (Dynamic) - *Planned*
- **Endpoint**: `https://api.bilibili.com/x/polymer/web-dynamic/v1/detail`
- **Method**: GET
- **Params**: `id` (动态ID)

## 5. 音频 (Audio) - *Planned*
- **Endpoint**: `https://www.bilibili.com/audio/music-service-c/web/song/info`
- **Method**: GET
- **Params**: `sid` (au号数字)

## 6. 直播 (Live) - *Planned*
- **Endpoint**: `https://api.live.bilibili.com/room/v1/Room/get_info`
- **Method**: GET
- **Params**: `room_id` (房间号)
