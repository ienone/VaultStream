# Weibo API Analysis & Implementation

## 1. API Overview

Weibo content is primarily accessed via the AJAX interface used by the web frontend. The analysis of the "Hot/Visitor" feed reveals the following key endpoints.

### Feed Endpoint (Hot/Recommended)

*   **URL**: `https://weibo.com/ajax/feed/hottimeline`
*   **Method**: `GET`
*   **Parameters**:
    *   `since_id`: `0` (Initial)
    *   `refresh`: `0` (Initial), `2` (Load More)
    *   `group_id`: `102803` (Hot/Recommended group)
    *   `containerid`: `102803`
    *   `extparam`: `discover|new_feed`
    *   `max_id`: `0`, `1`, `2`... (Increments by 1 for each page/scroll)
    *   `count`: `10`

### Single Status Endpoint

*   **URL**: `https://weibo.com/ajax/statuses/show`
*   **Method**: `GET`
*   **Parameters**:
    *   `id`: The `mblogid` (e.g., `QmsEAti7w`) or numeric ID (e.g., `5253533646981170`). Note: The adapter uses `id={mblogid}`.

## 2. Data Structure (JSON)

Both the Feed and Single Status endpoints share a common `status` object structure.

```json
{
  "created_at": "Sat Jan 10 13:38:10 +0800 2026", // Date format
  "id": 5253533646981170,          // Numeric ID
  "mblogid": "QmsEAti7w",          // String ID (used in URLs)
  "text": "...",                   // HTML Content
  "user": {
    "id": 7751385439,
    "screen_name": "Username",
    "profile_image_url": "..."
  },
  "pic_ids": ["pid1", "pid2"],     // List of Picture IDs
  "pic_infos": {                   // Dictionary of Picture Details
    "pid1": {
      "thumbnail": { "url": "..." },
      "large": { "url": "..." },
      "original": { "url": "..." }, // High res
      "mw2000": { "url": "..." }    // Max width 2000 (Very High res)
    }
  },
  "page_info": {                   // Video/Article Info (Optional)
    "type": "video",
    "media_info": { ... },
    "page_pic": { "url": "..." }
  },
  "reposts_count": 5,
  "comments_count": 46,
  "attitudes_count": 116           // Like count
}
```

## 3. Parsing Logic (Adapter)

The `WeiboAdapter` (`backend/app/adapters/weibo.py`) implements the parsing of this structure.

### Field Mapping

| Database Field | Source Field (JSON) | Notes |
| :--- | :--- | :--- |
| `platform_id` | `mblogid` | e.g., "QmsEAti7w" |
| `description` | `text` | HTML tags are stripped. |
| `author_name` | `user.screen_name` | |
| `author_id` | `user.id` | |
| `created_at` | `created_at` | Parsed from `%a %b %d %H:%M:%S %z %Y`. |
| `media_urls` | `pic_infos` | Prioritizes `mw2000` > `largest` > `original`. |
| `cover_url` | `pic_infos`[0] or `page_info.page_pic` | First image or video thumbnail. |
| `extra_stats` | `reposts_count`, `comments_count`, `attitudes_count` | |

### URL Handling

*   **Input**: `https://weibo.com/u/7751385439` (User Profile) - *Not currently supported for single status parsing.*
*   **Input**: `https://weibo.com/7751385439/QmsEAti7w` (Status) - *Supported.*
*   **Input**: `https://weibo.com/detail/QmsEAti7w` (Status) - *Supported.*

## 4. Archiving Strategy

1.  **Fetch**: The adapter requests `https://weibo.com/ajax/statuses/show?id={mblogid}` using the standard headers (User-Agent, Referer).
2.  **Parse**: Extract metadata, media URLs, and stats.
3.  **Store**: The generic `Content` model in `backend/app/models.py` stores the parsed data.
    *   `media_urls` JSON column stores all image/video links.
    *   `raw_metadata` stores the original JSON response for future-proofing.

## 5. Implementation Notes

*   **Cookie**: While some endpoints require login cookies, the `ajax/statuses/show` and `ajax/feed/hottimeline` often work with just a Visitor Cookie (or sometimes even without one for public posts, though less reliable). The adapter supports injecting `settings.weibo_cookie`.
*   **Video**: Video playback URLs in Weibo often expire or require specific Referer/Signature. The current implementation extracts the video entry but may require a proxy to play (handled by `api.py` `/proxy/media` if downloaded, or frontend proxy).
