"""
性能基准测试：多种图片格式转码对比

测试格式：
- PNG: https://blog.ienone.top/anime/anime-rating-criteria/featured_hu_90db38e006de2711.png
- GIF (动画): https://zqdongtuhs.duoduocdn.com/wenzitu/mw690/20260201033045_156.gif
- JPG: 在线 JPG 示例
"""

import asyncio
import httpx
import time
from pathlib import Path
from io import BytesIO
from PIL import Image


async def download_image(url: str) -> bytes:
    """下载图片"""
    async with httpx.AsyncClient(timeout=30.0, follow_redirects=True) as client:
        resp = await client.get(url)
        resp.raise_for_status()
        return resp.content


def transcode_pillow(data: bytes, quality: int = 80) -> tuple[float, int, str]:
    """Pillow 转码"""
    start = time.time()
    
    try:
        with Image.open(BytesIO(data)) as im:
            width, height = im.size
            is_animated = hasattr(im, 'n_frames') and im.n_frames > 1
            orig_format = im.format
            
            if is_animated:
                # 动画 GIF
                frames = []
                durations = []
                for frame_idx in range(im.n_frames):
                    im.seek(frame_idx)
                    frame = im.convert("RGBA") if im.mode in ("P", "LA") else im.convert("RGB")
                    frames.append(frame)
                    duration = im.info.get('duration', 100)
                    durations.append(duration)
                
                out = BytesIO()
                frames[0].save(
                    out,
                    format="WEBP",
                    quality=int(quality),
                    method=6,
                    save_all=True,
                    append_images=frames[1:],
                    duration=durations,
                    loop=0
                )
                result = out.getvalue()
            else:
                # 静态图片
                if im.mode in ("P", "LA"):
                    im = im.convert("RGBA")
                elif im.mode not in ("RGB", "RGBA"):
                    im = im.convert("RGB")
                
                out = BytesIO()
                im.save(out, format="WEBP", quality=int(quality), method=6)
                result = out.getvalue()
        
        elapsed = time.time() - start
        return elapsed, len(result), orig_format
    except Exception as e:
        return -1, 0, str(e)


def transcode_ffmpeg(data: bytes, quality: int = 80) -> tuple[float, int, str]:
    """ffmpeg 转码"""
    import subprocess
    import tempfile
    import os
    
    start = time.time()
    
    with tempfile.NamedTemporaryFile(delete=False) as tmp_in:
        tmp_in.write(data)
        tmp_in_path = tmp_in.name
    
    with tempfile.NamedTemporaryFile(suffix=".webp", delete=False) as tmp_out:
        tmp_out_path = tmp_out.name
    
    try:
        crf = max(0, min(63, int(80 - quality / 100 * 30)))
        
        result_proc = subprocess.run(
            [
                "ffmpeg",
                "-i", tmp_in_path,
                "-c:v", "libwebp",
                "-quality", str(100),
                "-crf", str(crf),
                "-loop", "0",
                "-y",
                tmp_out_path
            ],
            capture_output=True,
            timeout=120,
            check=False
        )
        
        if result_proc.returncode != 0:
            err = result_proc.stderr.decode()
            return -1, 0, err
        
        with open(tmp_out_path, "rb") as f:
            result = f.read()
        
        elapsed = time.time() - start
        return elapsed, len(result), "WebP"
    except Exception as e:
        return -1, 0, str(e)
    finally:
        os.unlink(tmp_in_path)
        os.unlink(tmp_out_path)


async def test_format(name: str, url: str):
    """测试单个格式"""
    print("\n" + "="*60)
    print("[TEST] " + name)
    print("="*60)
    print("[DOWNLOAD] " + url)
    
    try:
        data = await download_image(url)
        print("[OK] Size: {:.2f} KB".format(len(data) / 1024))
        
        # 获取图片信息
        with Image.open(BytesIO(data)) as img:
            frames = getattr(img, 'n_frames', 1)
            print("[INFO] Format: {}, Size: {}x{}, Frames: {}".format(
                img.format, img.size[0], img.size[1], frames
            ))
        
        # Pillow 转码
        print("\n[BENCH] Pillow...")
        t_pillow, size_pillow, fmt_pillow = transcode_pillow(data)
        if t_pillow > 0:
            print("[RESULT] {:.3f}s -> {:.2f} KB (format: {})".format(
                t_pillow, size_pillow / 1024, fmt_pillow
            ))
        else:
            print("[ERROR] " + fmt_pillow)
        
        # ffmpeg 转码
        print("[BENCH] ffmpeg...")
        t_ffmpeg, size_ffmpeg, fmt_ffmpeg = transcode_ffmpeg(data)
        if t_ffmpeg > 0:
            print("[RESULT] {:.3f}s -> {:.2f} KB (format: {})".format(
                t_ffmpeg, size_ffmpeg / 1024, fmt_ffmpeg
            ))
            if t_pillow > 0:
                speedup = t_pillow / t_ffmpeg
                print("[SPEEDUP] ffmpeg is {:.1f}x faster".format(speedup))
        else:
            print("[ERROR] " + str(fmt_ffmpeg))
    
    except Exception as e:
        print("[ERROR] " + str(e))


async def main():
    tests = [
        ("PNG (Static)", "https://blog.ienone.top/anime/anime-rating-criteria/featured_hu_90db38e006de2711.png"),
        ("GIF (Animated)", "https://zqdongtuhs.duoduocdn.com/wenzitu/mw690/20260201033045_156.gif"),
    ]
    
    # 检查 ffmpeg
    import subprocess
    try:
        subprocess.run(["ffmpeg", "-version"], capture_output=True, timeout=5, check=True)
        print("[OK] ffmpeg available")
    except:
        print("[WARN] ffmpeg not available")
    
    for name, url in tests:
        try:
            await test_format(name, url)
        except Exception as e:
            print("[ERROR] Test failed: " + str(e))


if __name__ == "__main__":
    asyncio.run(main())
