import unittest
from unittest.mock import patch, MagicMock
from datetime import datetime, timezone, timedelta
import sys
import os

# Add backend directory to path
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from app.adapters.weibo import WeiboAdapter
from app.adapters.base import ParsedContent

class TestWeiboAdapter(unittest.IsolatedAsyncioTestCase):

    def setUp(self):
        self.adapter = WeiboAdapter()
        self.sample_url = "https://weibo.com/7751385439/QmsEAti7w"
        
        # Captured JSON from network analysis (simplified for test)
        self.sample_json = {
            "ok": 1,
            "created_at": "Sat Jan 10 13:38:10 +0800 2026",
            "id": 5253533646981170,
            "idstr": "5253533646981170",
            "mid": "5253533646981170",
            "mblogid": "QmsEAti7w",
            "user": {
                "id": 7751385439,
                "idstr": "7751385439",
                "screen_name": "纸不纸道",
                "profile_image_url": "https://tvax4.sinaimg.cn/crop.0.0.960.960.50/008sA1rNly8i8k5mhq4nqj30qo0qojtj.jpg",
                "avatar_large": "https://tvax4.sinaimg.cn/crop.0.0.960.960.180/008sA1rNly8i8k5mhq4nqj30qo0qojtj.jpg"
            },
            "text": "颜安这是怎么了，图上说他和男明星谈恋爱获得资源<img src=\"...\" />[哆啦A梦害怕]，不进组非去追寻自己的爱豆梦...",
            "pic_ids": ["008sA1rNgy1i95ky8eun0j30wi1awtlm", "008sA1rNgy1i95ky8b8ssj30zu0nqae6"],
            "pic_infos": {
                "008sA1rNgy1i95ky8eun0j30wi1awtlm": {
                    "thumbnail": {"url": "https://wx1.sinaimg.cn/wap180/008sA1rNgy1i95ky8eun0j30wi1awtlm.jpg"},
                    "largest": {"url": "https://wx1.sinaimg.cn/large/008sA1rNgy1i95ky8eun0j30wi1awtlm.jpg"},
                    "mw2000": {"url": "https://wx1.sinaimg.cn/mw2000/008sA1rNgy1i95ky8eun0j30wi1awtlm.jpg"}
                },
                "008sA1rNgy1i95ky8b8ssj30zu0nqae6": {
                    "thumbnail": {"url": "https://wx2.sinaimg.cn/wap180/008sA1rNgy1i95ky8b8ssj30zu0nqae6.jpg"},
                    "largest": {"url": "https://wx2.sinaimg.cn/large/008sA1rNgy1i95ky8b8ssj30zu0nqae6.jpg"}
                }
            },
            "reposts_count": 5,
            "comments_count": 46,
            "attitudes_count": 116
        }

    @patch("app.adapters.weibo.requests.get")
    async def test_parse_success(self, mock_get):
        # Mock response
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.json.return_value = self.sample_json
        mock_get.return_value = mock_response

        # Execute
        result = await self.adapter.parse(self.sample_url)

        self.assertIsInstance(result, ParsedContent)
        self.assertEqual(result.platform, "weibo")
        self.assertEqual(result.content_id, "QmsEAti7w")
        self.assertEqual(result.author_name, "纸不纸道")
        self.assertEqual(result.author_id, "7751385439")
        
        # Check Media
        # Should pick mw2000 for first, largest for second
        expected_urls = [
            "https://wx1.sinaimg.cn/mw2000/008sA1rNgy1i95ky8eun0j30wi1awtlm.jpg",
            "https://wx2.sinaimg.cn/large/008sA1rNgy1i95ky8b8ssj30zu0nqae6.jpg"
        ]
        self.assertEqual(result.media_urls, expected_urls)
        self.assertEqual(result.cover_url, expected_urls[0])

        # Check Description (Text cleaning)
        # The simple regex in adapter just removes tags.
        # "颜安这是怎么了，图上说他和男明星谈恋爱获得资源<img src=\"...\" />[哆啦A梦害怕]，不进组非去追寻自己的爱豆梦..."
        # Should become "颜安这是怎么了，图上说他和男明星谈恋爱获得资源[哆啦A梦害怕]，不进组非去追寻自己的爱豆梦..."
        self.assertIn("颜安这是怎么了", result.description)
        self.assertNotIn("<img", result.description)

        # Check Date
        # "Sat Jan 10 13:38:10 +0800 2026"
        # 2026-01-10 13:38:10 +08:00
        expected_dt = datetime(2026, 1, 10, 13, 38, 10, tzinfo=timezone(timedelta(hours=8)))
        self.assertEqual(result.published_at, expected_dt)

        # Check Stats
        self.assertEqual(result.stats["repost"], 5)
        self.assertEqual(result.stats["reply"], 46)
        self.assertEqual(result.stats["like"], 116)

    @patch("app.adapters.weibo.requests.get")
    async def test_parse_video(self, mock_get):
        video_json = self.sample_json.copy()
        video_json["page_info"] = {
            "type": "video",
            "page_pic": {"url": "http://example.com/poster.jpg"},
            "media_info": {
                "mp4_720p_mp4": "http://example.com/video.mp4",
                "duration": 60,
                "width": 1280,
                "height": 720
            }
        }
        
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.json.return_value = video_json
        mock_get.return_value = mock_response

        result = await self.adapter.parse("https://weibo.com/123/AbCdEfGhI")
        
        # Check Archive
        archive = result.raw_metadata.get("archive")
        self.assertIsNotNone(archive)
        self.assertEqual(len(archive["videos"]), 1)
        self.assertEqual(archive["videos"][0]["url"], "http://example.com/video.mp4")
        
        # Check Standard Fields
        # Cover should prioritize images (if any) or video cover
        # In this sample_json, we have images, so cover is first image.
        # Let's remove images to test video cover fallback
        video_json_no_img = video_json.copy()
        video_json_no_img["pic_ids"] = []
        video_json_no_img["pic_infos"] = {}
        mock_response.json.return_value = video_json_no_img
        
        result_no_img = await self.adapter.parse("https://weibo.com/123/AbCdEfGhJ")
        self.assertEqual(result_no_img.cover_url, "http://example.com/poster.jpg")

    async def test_clean_url(self):
        url1 = "https://weibo.com/7751385439/QmsEAti7w?type=comment"
        cleaned1 = await self.adapter.clean_url(url1)
        self.assertEqual(cleaned1, "https://weibo.com/7751385439/QmsEAti7w")

        url2 = "https://weibo.com/detail/QmsEAti7w"
        cleaned2 = await self.adapter.clean_url(url2)
        self.assertEqual(cleaned2, "https://weibo.com/detail/QmsEAti7w")

if __name__ == "__main__":
    unittest.main()
