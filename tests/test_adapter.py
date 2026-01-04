"""测试脚本 - 测试B站适配器和完整流程"""

import os
import sys


# Make `import app.*` work when running this file from `tests/`.
PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)


import asyncio
import hashlib
import json
import shutil
import subprocess

from app.adapters.bilibili import BilibiliAdapter


async def test_bilibili_adapter():
    """测试B站适配器"""
    adapter = BilibiliAdapter()

    # 测试URL列表
    test_urls = [
        "https://www.bilibili.com/video/BV1xx411c7XD",  # 视频
        "https://www.bilibili.com/read/cv12345678",  # 专栏
        "https://www.bilibili.com/opus/1150580721704763430",  # 动态
    ]

    for url in test_urls:
        print(f"\n{'='*60}")
        print(f"测试URL: {url}")
        print(f"{'='*60}")

        try:
            # 检测内容类型
            content_type = await adapter.detect_content_type(url)
            print(f"✅ 内容类型: {content_type}")

            # 净化URL
            clean_url = await adapter.clean_url(url)
            print(f"✅ 净化URL: {clean_url}")

            # 解析内容（可能会失败，因为ID是示例）
            try:
                parsed = await adapter.parse(url)
                print(f"✅ 标题: {parsed.title}")
                print(f"✅ 作者: {parsed.author_name}")
                print(f"✅ 描述: {parsed.description[:100] if parsed.description else 'N/A'}...")
                print(f"✅ 封面: {parsed.cover_url}")
            except Exception as e:
                print(f"⚠️  解析失败（预期，因为是示例ID）: {e}")

        except Exception as e:
            print(f"❌ 错误: {e}")


async def test_real_url():
    """测试真实URL（需要手动提供）"""
    adapter = BilibiliAdapter()

    # 这里放一个真实的B站URL
    try:
        real_url = input("\n请输入一个真实的B站URL进行测试（直接回车跳过）: ").strip()
    except EOFError:
        real_url = ""

    if not real_url:
        print("跳过真实URL测试")
        return

    try:
        print(f"\n{'='*60}")
        print(f"解析真实URL: {real_url}")
        print(f"{'='*60}")

        parsed = await adapter.parse(real_url)

        print(f"\n📊 解析结果:")
        print(f"  平台: {parsed.platform}")
        print(f"  类型: {parsed.content_type}")
        print(f"  ID: {parsed.content_id}")
        print(f"  标题: {parsed.title}")
        print(f"  作者: {parsed.author_name} (ID: {parsed.author_id})")
        print(f"  描述: {parsed.description[:200] if parsed.description else 'N/A'}...")
        print(f"  封面: {parsed.cover_url}")
        print(f"  媒体数: {len(parsed.media_urls)}")
        print(f"\n  元数据:")
        for key, value in parsed.raw_metadata.items():
            print(f"    {key}: {value}")

        print(f"\n✅ 解析成功！")

    except Exception as e:
        print(f"❌ 解析失败: {e}")
        import traceback

        traceback.print_exc()


async def test_opus_archive():
    """功能测试：opus 图文归档清洗。

    使用方式：
    1) 环境变量：BILIBILI_TEST_OPUS_URL='https://www.bilibili.com/opus/xxxx' 直接跑
    2) 或运行后按提示输入
    """

    adapter = BilibiliAdapter()

    url = (os.getenv("BILIBILI_TEST_OPUS_URL") or "").strip()
    if not url:
        try:
            url = input("\n请输入一个 B站 opus 动态 URL（用于归档测试，回车跳过）: ").strip()
        except EOFError:
            url = ""
    if not url:
        print("跳过 opus 归档测试")
        return

    parsed = await adapter.parse(url)
    archive = (parsed.raw_metadata or {}).get("archive") or {}

    print("\n📦 Opus 归档清洗结果:")
    print(f"  标题: {archive.get('title')!r}")
    print(f"  plain_text_len: {len(str(archive.get('plain_text') or ''))}")
    print(f"  markdown_len: {len(str(archive.get('markdown') or ''))}")
    print(f"  blocks: {len(archive.get('blocks') or [])}")
    print(f"  images: {len(archive.get('images') or [])}")
    print(f"  links: {len(archive.get('links') or [])}")
    print(f"  mentions: {len(archive.get('mentions') or [])}")
    print(f"  topics: {len(archive.get('topics') or [])}")

    # 预览前 200 字
    preview = str(archive.get("plain_text") or "")
    if preview:
        print("\n  plain_text_preview:")
        print("  " + preview[:200].replace("\n", "\\n") + ("..." if len(preview) > 200 else ""))


async def test_opus_archive_from_curl_fixture():
    """离线功能测试：使用 curl_opus.txt 的响应 JSON 构建归档。

    目的：不依赖网络/风控/登录，确保 _build_opus_archive 对 module_content.paragraphs 结构可用。
    """

    fixture_path = (os.getenv("BILIBILI_OPUS_CURL_FIXTURE") or "curl_opus.txt").strip()
    if not fixture_path:
        print("跳过离线 opus fixture 测试（未提供 fixture 路径）")
        return

    if not os.path.exists(fixture_path):
        print(f"跳过离线 opus fixture 测试（文件不存在）: {fixture_path}")
        return

    raw = ""
    with open(fixture_path, "r", encoding="utf-8", errors="ignore") as f:
        raw = f.read()

    start = raw.find("{")
    end = raw.rfind("}")
    if start < 0 or end < 0 or end <= start:
        print(f"跳过离线 opus fixture 测试（未找到 JSON）: {fixture_path}")
        return

    payload = json.loads(raw[start : end + 1])
    item = (((payload or {}).get("data") or {}).get("item") or {})

    adapter = BilibiliAdapter()
    archive = adapter._build_opus_archive(item)

    print("\n🧷 离线 Opus fixture 归档清洗结果:")
    print(f"  标题: {archive.get('title')!r}")
    print(f"  plain_text_len: {len(str(archive.get('plain_text') or ''))}")
    print(f"  markdown_len: {len(str(archive.get('markdown') or ''))}")
    print(f"  blocks: {len(archive.get('blocks') or [])}")
    print(f"  images: {len(archive.get('images') or [])}")
    print(f"  links: {len(archive.get('links') or [])}")

    preview = str(archive.get("plain_text") or "")
    if preview:
        print("\n  plain_text_preview:")
        print("  " + preview[:200].replace("\n", "\\n") + ("..." if len(preview) > 200 else ""))

    # 导出：Markdown/JSON（用于人工核对“保存是否完善”）
    export_dir = (os.getenv("VS_EXPORT_DIR") or "exports").strip() or "exports"
    export_md = (os.getenv("VS_EXPORT_MARKDOWN") or "1").strip().lower() not in ("0", "false", "no")
    export_pdf = (os.getenv("VS_EXPORT_PDF") or "0").strip().lower() in ("1", "true", "yes")
    export_webp = (os.getenv("VS_EXPORT_WEBP") or "0").strip().lower() in ("1", "true", "yes")

    if export_md:
        os.makedirs(export_dir, exist_ok=True)
        base = "opus_fixture"
        md_path = os.path.join(export_dir, f"{base}.md")
        json_path = os.path.join(export_dir, f"{base}.archive.json")

        md_text = str(archive.get("markdown") or "")

        if export_webp:
            try:
                import httpx
            except Exception:
                httpx = None

            try:
                from PIL import Image  # type: ignore
            except Exception:
                Image = None

            if httpx is None or Image is None:
                print("\n⚠️  VS_EXPORT_WEBP=1 需要额外依赖：Pillow（以及网络下载能力）。")
            else:
                assets_dir = os.path.join(export_dir, "assets")
                os.makedirs(assets_dir, exist_ok=True)

                url_to_rel: dict[str, str] = {}

                async with httpx.AsyncClient(timeout=30.0) as client:  # 下载并转码图片为 WebP
                    for img in (archive.get("images") or []):
                        if not isinstance(img, dict):
                            continue
                        url = img.get("url")
                        if not isinstance(url, str) or not url.strip():
                            continue
                        url = url.strip()
                        if url in url_to_rel:
                            continue

                        digest = hashlib.sha1(url.encode("utf-8")).hexdigest()[:16]
                        filename = f"{digest}.webp"
                        out_path = os.path.join(assets_dir, filename)
                        rel_path = os.path.join("assets", filename).replace("\\", "/")  # 兼容 Windows 路径

                        if os.path.exists(out_path):
                            url_to_rel[url] = rel_path
                            continue

                        try:
                            resp = await client.get(url)
                            resp.raise_for_status()
                            data = resp.content
                        except Exception as e:
                            print(f"\n⚠️  下载图片失败，跳过：{url} ({type(e).__name__}: {e})")
                            continue

                        try:
                            from io import BytesIO

                            with Image.open(BytesIO(data)) as im:
                                # 统一转为可写 webp 的模式
                                if im.mode in ("P", "LA"):
                                    im = im.convert("RGBA")
                                elif im.mode not in ("RGB", "RGBA"):
                                    im = im.convert("RGB")

                                im.save(out_path, format="WEBP", quality=80, method=6)
                            url_to_rel[url] = rel_path
                        except Exception as e:
                            print(f"\n⚠️  转码 webp 失败，跳过：{url} ({type(e).__name__}: {e})")
                            continue

                # 更新 Markdown：把远程图片链接替换成本地 assets 路径
                for src_url, rel in url_to_rel.items():
                    md_text = md_text.replace(f"]({src_url})", f"]({rel})")

                print(f"\n🖼️  已导出并转码图片到：{assets_dir}")

        with open(md_path, "w", encoding="utf-8") as f:
            f.write(md_text)
        with open(json_path, "w", encoding="utf-8") as f:
            json.dump(archive, f, ensure_ascii=False, indent=2)

        print(f"\n📝 已导出 Markdown：{md_path}")
        print(f"🗃️  已导出 Archive JSON：{json_path}")

        if export_pdf:
            pandoc = shutil.which("pandoc")
            if not pandoc:
                print("\n⚠️  VS_EXPORT_PDF=1 需要系统已安装 pandoc，当前未找到 pandoc。")
            else:
                pdf_path = os.path.join(export_dir, f"{base}.pdf")
                try:
                    # 使用 pandoc 将 md 转 PDF（包含图片时会引用本地 assets）
                    subprocess.run([pandoc, md_path, "-o", pdf_path], check=False)
                    print(f"\n📄 已尝试导出 PDF：{pdf_path}")
                except Exception as e:
                    print(f"\n⚠️  导出 PDF 失败：{type(e).__name__}: {e}")


async def test_archive_media_processing_local_from_fixture():
    """离线验证：存储抽象 + 图片转 WebP 落到 storage（LocalFS）。

    目的：验证 app.media_processing.store_archive_images_as_webp + app.storage.LocalStorageBackend 可用，
    并且会把结果写回 archive（stored_key/stored_sha256/stored_images 等）。

    启用方式：
    - VS_TEST_STORAGE_MEDIA=1
    - 可选：VS_TEST_STORAGE_ROOT=exports/storage_test
    - 可选：VS_TEST_PUBLIC_BASE_URL=http://localhost:9000 （用于替换 markdown 中图片链接）
    """

    enabled = (os.getenv("VS_TEST_STORAGE_MEDIA") or "0").strip().lower() in ("1", "true", "yes")
    if not enabled:
        return

    fixture_path = (os.getenv("BILIBILI_OPUS_CURL_FIXTURE") or "curl_opus.txt").strip()
    if not fixture_path or not os.path.exists(fixture_path):
        print(f"跳过 storage/webp 离线验证（fixture 不存在）: {fixture_path}")
        return

    raw = ""
    with open(fixture_path, "r", encoding="utf-8", errors="ignore") as f:
        raw = f.read()
    start = raw.find("{")
    end = raw.rfind("}")
    if start < 0 or end < 0 or end <= start:
        print(f"跳过 storage/webp 离线验证（未找到 JSON）: {fixture_path}")
        return

    payload = json.loads(raw[start : end + 1])
    item = (((payload or {}).get("data") or {}).get("item") or {})

    adapter = BilibiliAdapter()
    archive = adapter._build_opus_archive(item)

    images = archive.get("images") or []
    print("\n🧪 离线验证：storage + WebP")
    print(f"  fixture_images: {len(images)}")
    if not images:
        print("  ⚠️  fixture 不包含图片，无法验证转码/存储")
        return

    # Local storage backend (no dependency on .env/settings)
    from app.media_processing import store_archive_images_as_webp
    from app.storage import LocalStorageBackend

    storage_root = (os.getenv("VS_TEST_STORAGE_ROOT") or "exports/storage_test").strip() or "exports/storage_test"
    public_base_url = (os.getenv("VS_TEST_PUBLIC_BASE_URL") or "").strip() or None
    quality = int((os.getenv("VS_TEST_WEBP_QUALITY") or "80").strip() or 80)
    max_images_env = (os.getenv("VS_TEST_MAX_IMAGES") or "").strip()
    max_images = int(max_images_env) if max_images_env else None

    storage = LocalStorageBackend(root_dir=storage_root, public_base_url=public_base_url)

    await store_archive_images_as_webp(
        archive=archive,
        storage=storage,
        namespace="vaultstream",
        quality=quality,
        max_images=max_images,
    )

    stored_images = archive.get("stored_images") or []
    print(f"  stored_images: {len(stored_images)}")

    # 检查实际文件是否落盘
    existing = 0
    for it in stored_images[:5]:
        key = (it or {}).get("key")
        if not isinstance(key, str) or not key:
            continue
        full_path = os.path.join(storage_root, key.lstrip("/"))
        if os.path.exists(full_path):
            existing += 1
    print(f"  stored_files_exist(sample_5): {existing}/5")
    print(f"  storage_root: {storage_root}")

    # 导出处理后的 archive，便于人工核对 stored_* 字段
    export_dir = (os.getenv("VS_EXPORT_DIR") or "exports").strip() or "exports"
    os.makedirs(export_dir, exist_ok=True)
    out_path = os.path.join(export_dir, "opus_fixture.archive.processed.json")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(archive, f, ensure_ascii=False, indent=2)
    print(f"  🗃️  已导出 processed archive：{out_path}")


if __name__ == "__main__":
    print("🧪 VaultStream - B站适配器测试")
    print("=" * 60)

    # 运行测试：先跑离线 fixture，避免被交互/网络影响
    try:
        asyncio.run(test_opus_archive_from_curl_fixture())
    except KeyboardInterrupt:
        print("\n⚠️  已中断离线 fixture 测试")

    try:
        asyncio.run(test_archive_media_processing_local_from_fixture())
    except KeyboardInterrupt:
        print("\n⚠️  已中断 storage/webp 离线验证")

    try:
        asyncio.run(test_bilibili_adapter())
    except KeyboardInterrupt:
        print("\n⚠️  已中断基础适配器测试")

    try:
        asyncio.run(test_real_url())
    except KeyboardInterrupt:
        print("\n⚠️  已中断真实 URL 测试")

    try:
        asyncio.run(test_opus_archive())
    except KeyboardInterrupt:
        print("\n⚠️  已中断 opus 归档测试")

    print("\n✨ 测试完成！")
