"""
content_type 数据校验与迁移脚本

扫描 contents 表中的所有记录，校验 content_type 字段是否为其 platform 的合法值。
支持 dry-run（默认）和 --fix 模式。

Usage:
    python scripts/migrate_content_type.py          # 仅报告
    python scripts/migrate_content_type.py --fix    # 报告并修复
    python scripts/migrate_content_type.py --db path/to/db.sqlite  # 指定数据库
"""

import argparse
import asyncio
import json
import re
import sys
from pathlib import Path
from typing import Optional

try:
    import aiosqlite
except ImportError:
    print("错误: 需要 aiosqlite 库。请运行: pip install aiosqlite")
    sys.exit(1)

# ── 每个平台的合法 content_type 值 ──────────────────────────────────────────

VALID_CONTENT_TYPES: dict[str, set[str]] = {
    "bilibili": {"video", "article", "dynamic", "bangumi", "audio", "live", "cheese"},
    "twitter": {"tweet", "thread"},
    "xiaohongshu": {"note", "video"},
    "weibo": {"weibo", "status"},
    "zhihu": {"answer", "article", "question", "pin", "column", "collection"},
    "douyin": {"video", "note"},
    "ku_an": {"app"},
    "universal": {"link", "page"},
}

# ── 从 URL 推断 content_type ────────────────────────────────────────────────

URL_INFER_RULES: dict[str, list[tuple[str, str]]] = {
    "bilibili": [
        (r"bilibili\.com/video/|b23\.tv/(BV|av)", "video"),
        (r"bilibili\.com/read/cv", "article"),
        (r"bilibili\.com/opus/|t\.bilibili\.com/", "dynamic"),
        (r"bilibili\.com/bangumi/play/", "bangumi"),
        (r"bilibili\.com/audio/au", "audio"),
        (r"live\.bilibili\.com/", "live"),
        (r"bilibili\.com/cheese/", "cheese"),
    ],
    "twitter": [
        (r"(twitter\.com|x\.com)/\w+/status/", "tweet"),
    ],
    "xiaohongshu": [
        (r"xiaohongshu\.com/(explore|discovery/item)/", "note"),
    ],
    "weibo": [
        (r"weibo\.(com|cn)/", "weibo"),
    ],
    "zhihu": [
        (r"zhuanlan\.zhihu\.com/p/", "article"),
        (r"zhihu\.com/question/\d+/answer/|zhihu\.com/answer/", "answer"),
        (r"zhihu\.com/question/\d+(?!\S*answer)", "question"),
        (r"zhihu\.com/pin/", "pin"),
        (r"zhihu\.com/column/|zhuanlan\.zhihu\.com/(?!p/)", "column"),
        (r"zhihu\.com/collection/", "collection"),
    ],
}


def infer_from_url(platform: str, url: str) -> Optional[str]:
    """根据 URL 模式推断 content_type"""
    for pattern, content_type in URL_INFER_RULES.get(platform, []):
        if re.search(pattern, url):
            return content_type
    return None


def infer_from_metadata(platform: str, raw_metadata: Optional[dict]) -> Optional[str]:
    """根据 raw_metadata 中的字段推断 content_type"""
    if not raw_metadata:
        return None

    # 通用: 直接检查 content_type / type 字段
    for key in ("content_type", "type"):
        val = raw_metadata.get(key)
        if isinstance(val, str):
            val_lower = val.lower()
            if platform in VALID_CONTENT_TYPES and val_lower in VALID_CONTENT_TYPES[platform]:
                return val_lower

    # bilibili: tname / tid 等暗示视频
    if platform == "bilibili":
        if raw_metadata.get("bvid") or raw_metadata.get("aid"):
            return "video"
        if raw_metadata.get("cvid"):
            return "article"

    # xiaohongshu: note_type 字段
    if platform == "xiaohongshu":
        note_type = raw_metadata.get("note_type") or raw_metadata.get("type")
        if isinstance(note_type, str) and note_type.lower() in ("video",):
            return "video"
        return "note"  # 小红书默认 note

    return None


# ── 主逻辑 ──────────────────────────────────────────────────────────────────

async def run(db_path: str, fix: bool) -> None:
    db_file = Path(db_path)
    if not db_file.exists():
        print(f"错误: 数据库文件不存在: {db_file.resolve()}")
        print("提示: 使用 --db 指定正确的数据库路径，或先启动后端创建数据库。")
        sys.exit(0)

    async with aiosqlite.connect(str(db_file)) as db:
        db.row_factory = aiosqlite.Row

        cursor = await db.execute(
            "SELECT id, platform, content_type, url, raw_metadata FROM contents"
        )
        rows = await cursor.fetchall()

    total = len(rows)
    valid = 0
    null_ct = []
    invalid_ct = []
    fixes: list[tuple[int, str, str]] = []  # (id, field_desc, new_value)

    for row in rows:
        rid = row["id"]
        platform = row["platform"]
        content_type = row["content_type"]
        url = row["url"] or ""
        raw_meta_raw = row["raw_metadata"]

        raw_metadata = None
        if isinstance(raw_meta_raw, str):
            try:
                raw_metadata = json.loads(raw_meta_raw)
            except (json.JSONDecodeError, TypeError):
                pass
        elif isinstance(raw_meta_raw, dict):
            raw_metadata = raw_meta_raw

        allowed = VALID_CONTENT_TYPES.get(platform, set())

        if content_type is None:
            # 尝试推断
            inferred = infer_from_url(platform, url) or infer_from_metadata(platform, raw_metadata)
            null_ct.append({
                "id": rid,
                "platform": platform,
                "url": url[:80],
                "inferred": inferred,
            })
            if inferred:
                fixes.append((rid, f"NULL → {inferred}", inferred))
        elif content_type.lower() in allowed:
            if content_type != content_type.lower():
                # 大小写不规范
                invalid_ct.append({
                    "id": rid,
                    "platform": platform,
                    "content_type": content_type,
                    "issue": "casing",
                })
                fixes.append((rid, f"{content_type} → {content_type.lower()}", content_type.lower()))
            else:
                valid += 1
        else:
            invalid_ct.append({
                "id": rid,
                "platform": platform,
                "content_type": content_type,
                "issue": "unknown",
            })

    # ── 输出报告 ────────────────────────────────────────────────────────

    print("=" * 60)
    print("  content_type 校验报告")
    print("=" * 60)
    print(f"  总记录数:        {total}")
    print(f"  合法 (valid):    {valid}")
    print(f"  NULL:            {len(null_ct)}")
    print(f"  异常 (invalid):  {len(invalid_ct)}")
    print(f"  可修复:          {len(fixes)}")
    print("=" * 60)

    if null_ct:
        print("\n── NULL content_type 记录 ──")
        for item in null_ct:
            inferred_str = f" → 可推断: {item['inferred']}" if item["inferred"] else " → 无法推断"
            print(f"  id={item['id']:>6}  platform={item['platform']:<14} url={item['url']}{inferred_str}")

    if invalid_ct:
        print("\n── 异常 content_type 记录 ──")
        for item in invalid_ct:
            issue = "大小写不规范" if item["issue"] == "casing" else "未知值"
            print(f"  id={item['id']:>6}  platform={item['platform']:<14} content_type={item['content_type']!r}  ({issue})")

    if fixes:
        print(f"\n── 修复计划 ({len(fixes)} 条) ──")
        for rid, desc, _ in fixes:
            print(f"  id={rid:>6}  {desc}")

    # ── 执行修复 ────────────────────────────────────────────────────────

    if fix and fixes:
        print(f"\n正在应用 {len(fixes)} 条修复...")
        async with aiosqlite.connect(str(db_file)) as db:
            for rid, desc, new_value in fixes:
                await db.execute(
                    "UPDATE contents SET content_type = ? WHERE id = ?",
                    (new_value, rid),
                )
            await db.commit()
        print("✓ 修复完成。")
    elif fix and not fixes:
        print("\n无需修复。")
    else:
        if fixes:
            print("\n提示: 使用 --fix 参数实际应用修复。")

    print()


def main() -> None:
    parser = argparse.ArgumentParser(
        description="content_type 数据校验与迁移脚本",
    )
    parser.add_argument(
        "--fix",
        action="store_true",
        help="实际应用修复（默认仅报告）",
    )
    parser.add_argument(
        "--db",
        default="backend/data/vaultstream.db",
        help="数据库路径（默认: backend/data/vaultstream.db）",
    )
    args = parser.parse_args()

    asyncio.run(run(args.db, args.fix))


if __name__ == "__main__":
    main()
