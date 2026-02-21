"""
NapCat push test: iterate over various render_config combinations.

Usage (from backend/):
    python tests/test_napcat_render_configs.py

Requires:
    - NapCat running with HTTP API enabled
    - NAPCAT_API_BASE / NAPCAT_BOT_UIN / NAPCAT_ACCESS_TOKEN in .env
    - Bot is a member of the target group
"""
import asyncio
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.push.napcat import NapcatPushService

TARGET_GROUP = "group:1070760473"

SAMPLE_CONTENT = {
    "id": 9999,
    "title": "### **Markdown** Title Test",
    "description": (
        "### Section Heading\n"
        "This is **bold** and *italic* text.\n"
        "> A blockquote line\n"
        "![image](https://example.com/img.png)\n"
        "[Click here](https://example.com)\n"
        "`inline code` and ~~strikethrough~~\n"
        "---\n"
        "Normal paragraph."
    ),
    "platform": "bilibili",
    "author_name": "TestAuthor",
    "author_id": "UID_12345",
    "clean_url": "https://example.com/content/123",
    "url": "https://example.com/content/123?tracker=1",
    "canonical_url": "https://example.com/content/123",
    "tags": ["tech", "test", "demo"],
    "cover_url": None,
    "archive_metadata": {
        "archive": {
            "images": [
                {"url": "file:///C:/Users/86138/Documents/coding/VaultStream/data/test.png"},
            ]
        }
    },
}

RENDER_CONFIGS = [
    {
        "name": "1. Default (all visible)",
        "config": {},
    },
    {
        "name": "2. media_mode=none",
        "config": {"media_mode": "none"},
    },
    {
        "name": "3. media_mode=cover",
        "config": {"media_mode": "cover"},
    },
    {
        "name": "4. author_mode=none",
        "config": {"author_mode": "none"},
    },
    {
        "name": "5. author_mode=name (no ID)",
        "config": {"author_mode": "name"},
    },
    {
        "name": "6. content_mode=hidden",
        "config": {"content_mode": "hidden"},
    },
    {
        "name": "7. content_mode=full",
        "config": {"content_mode": "full"},
    },
    {
        "name": "8. link_mode=none",
        "config": {"link_mode": "none"},
    },
    {
        "name": "9. link_mode=original",
        "config": {"link_mode": "original"},
    },
    {
        "name": "10. show_title=false",
        "config": {"show_title": False},
    },
    {
        "name": "11. show_tags=true",
        "config": {"show_tags": True},
    },
    {
        "name": "12. show_platform_id=false",
        "config": {"show_platform_id": False},
    },
    {
        "name": "13. header + footer",
        "config": {
            "header_text": "=== Daily Picks {{date}} ===",
            "footer_text": "--- End of {{title}} ---",
        },
    },
    {
        "name": "14. Minimal (platform+author+cover only)",
        "config": {
            "show_title": False,
            "show_tags": False,
            "show_platform_id": True,
            "author_mode": "full",
            "content_mode": "hidden",
            "media_mode": "cover",
            "link_mode": "none",
        },
    },
    {
        "name": "15. Full verbose (everything on)",
        "config": {
            "show_title": True,
            "show_tags": True,
            "show_platform_id": True,
            "author_mode": "full",
            "content_mode": "full",
            "media_mode": "auto",
            "link_mode": "clean",
        },
    },
]


async def main():
    svc = NapcatPushService()
    passed = 0
    failed = 0

    for i, case in enumerate(RENDER_CONFIGS):
        content = {**SAMPLE_CONTENT}
        content["render_config"] = case["config"]
        label = case["name"]

        try:
            msg_id = await svc.push(content, TARGET_GROUP)
            if msg_id:
                print(f"  PASS  {label} -> msg_id={msg_id}")
                passed += 1
            else:
                print(f"  FAIL  {label} -> no msg_id returned")
                failed += 1
        except Exception as e:
            print(f"  ERROR {label} -> {e}")
            failed += 1

        await asyncio.sleep(1.5)

    print(f"\n{'='*50}")
    print(f"Results: {passed} passed, {failed} failed, {len(RENDER_CONFIGS)} total")

    # Bonus: test merged forward with mixed configs
    print(f"\n{'='*50}")
    print("Merged forward test: 3 nodes with different configs")
    nodes = []
    for cfg in RENDER_CONFIGS[:3]:
        c = {**SAMPLE_CONTENT, "render_config": cfg["config"]}
        c["author_name"] = cfg["name"]
        nodes.append(c)

    try:
        msg_id = await svc.push_forward(
            nodes, TARGET_GROUP,
            use_author_name=True,
            summary="Render Config Test Digest",
        )
        if msg_id:
            print(f"  PASS  Forward -> msg_id={msg_id}")
        else:
            print(f"  FAIL  Forward -> no msg_id")
    except Exception as e:
        print(f"  ERROR Forward -> {e}")

    await svc.close()


if __name__ == "__main__":
    asyncio.run(main())
