"""
NapCat push test: iterate over all platforms in the database.

Picks one content item per platform and pushes it to verify:
- Text rendering (markdown stripped)
- Media extraction & local file resolution
- Platform label display

Usage (from backend/):
    python tests/test_napcat_platforms.py

Requires:
    - NapCat running with HTTP API enabled
    - NAPCAT_API_BASE / NAPCAT_BOT_UIN / NAPCAT_ACCESS_TOKEN in .env
    - Bot is a member of the target group
"""
import asyncio
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import select, func
from app.core.database import AsyncSessionLocal
from app.models import Content
from app.push.napcat import NapcatPushService
from app.utils.text_formatters import strip_markdown

TARGET_GROUP = "group:1070760473"

RENDER_CONFIG = {
    "show_platform_id": True,
    "show_title": True,
    "show_tags": True,
    "author_mode": "full",
    "content_mode": "summary",
    "media_mode": "auto",
    "link_mode": "clean",
}


def build_payload(content: Content) -> dict:
    return {
        "id": content.id,
        "title": content.title,
        "platform": content.platform.value if content.platform else None,
        "cover_url": content.cover_url,
        "raw_metadata": content.raw_metadata,
        "canonical_url": content.canonical_url,
        "tags": content.tags,
        "is_nsfw": content.is_nsfw,
        "description": content.description,
        "summary": getattr(content, "summary", None),
        "author_name": content.author_name,
        "author_id": content.author_id,
        "clean_url": content.clean_url,
        "url": content.url,
        "view_count": content.view_count,
        "like_count": content.like_count,
        "collect_count": content.collect_count,
        "share_count": content.share_count,
        "comment_count": content.comment_count,
        "extra_stats": content.extra_stats or {},
        "content_type": content.content_type,
        "render_config": RENDER_CONFIG,
    }


async def main():
    svc = NapcatPushService()
    passed = 0
    failed = 0
    all_payloads = []

    async with AsyncSessionLocal() as session:
        # Get distinct platforms
        result = await session.execute(
            select(Content.platform, func.count(Content.id))
            .group_by(Content.platform)
        )
        platform_counts = result.all()
        print(f"Platforms in DB: {', '.join(f'{p.value}({c})' for p, c in platform_counts)}")
        print("=" * 60)

        # Pick one content per platform (prefer ones with images)
        for platform_enum, count in platform_counts:
            platform_val = platform_enum.value

            # Try to find one with stored media first
            result = await session.execute(
                select(Content)
                .where(Content.platform == platform_enum)
                .order_by(Content.created_at.desc())
                .limit(5)
            )
            candidates = result.scalars().all()

            # Prefer content with stored images
            chosen = None
            for c in candidates:
                meta = c.raw_metadata or {}
                imgs = (meta.get("archive") or {}).get("images", [])
                has_stored = any(i.get("stored_key") for i in imgs)
                if has_stored:
                    chosen = c
                    break
            if not chosen:
                chosen = candidates[0] if candidates else None

            if not chosen:
                print(f"  SKIP  {platform_val}: no content found")
                continue

            payload = build_payload(chosen)
            all_payloads.append(payload)

            # Diagnostic: check markdown stripping
            desc = chosen.description or ""
            stripped = strip_markdown(desc)
            md_changed = desc != stripped
            md_tag = " [MD stripped]" if md_changed else ""

            # Diagnostic: check media resolution
            meta = chosen.raw_metadata or {}
            imgs = (meta.get("archive") or {}).get("images", [])
            vids = (meta.get("archive") or {}).get("videos", [])
            stored_count = sum(1 for i in imgs if i.get("stored_key"))

            print(f"  [{platform_val}] id={chosen.id} author={chosen.author_name}")
            print(f"    imgs={len(imgs)}(stored={stored_count}) vids={len(vids)}{md_tag}")

            # Push single message
            try:
                msg_id = await svc.push(payload, TARGET_GROUP)
                if msg_id:
                    print(f"    PASS  single push -> msg_id={msg_id}")
                    passed += 1
                else:
                    print(f"    FAIL  single push -> no msg_id")
                    failed += 1
            except Exception as e:
                print(f"    ERROR single push -> {e}")
                failed += 1

            await asyncio.sleep(2)

    # Merged forward: one node per platform
    print("\n" + "=" * 60)
    print(f"Merged forward test: {len(all_payloads)} platforms in one forward message")

    if len(all_payloads) >= 2:
        try:
            msg_id = await svc.push_forward(
                all_payloads,
                TARGET_GROUP,
                use_author_name=True,
                summary=f"VaultStream All-Platform Digest ({len(all_payloads)} platforms)",
            )
            if msg_id:
                print(f"  PASS  forward -> msg_id={msg_id}")
                passed += 1
            else:
                print(f"  FAIL  forward -> no msg_id")
                failed += 1
        except Exception as e:
            print(f"  ERROR forward -> {e}")
            failed += 1
    else:
        print("  SKIP  not enough platforms for forward test")

    print(f"\n{'='*60}")
    print(f"Results: {passed} passed, {failed} failed")

    await svc.close()


if __name__ == "__main__":
    asyncio.run(main())
