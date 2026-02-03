"""
性能基准测试：Pillow vs ffmpeg GIF 转码

测试同一个 GIF 的转码速度对比
"""

import asyncio
import httpx
import time
from pathlib import Path
from io import BytesIO
from PIL import Image


async def download_gif(url: str) -> bytes:
    """下载 GIF"""
    async with httpx.AsyncClient(timeout=30.0, follow_redirects=True) as client:
        resp = await client.get(url)
        resp.raise_for_status()
        return resp.content


def bench_pillow(data: bytes, quality: int = 80) -> tuple[float, int]:
    """基准：Pillow 转码（包括动画）"""
    start = time.time()
    
    with Image.open(BytesIO(data)) as im:
        width, height = im.size
        is_animated = hasattr(im, 'n_frames') and im.n_frames > 1
        
        if is_animated:
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
            if im.mode in ("P", "LA"):
                im = im.convert("RGBA")
            elif im.mode not in ("RGB", "RGBA"):
                im = im.convert("RGB")
            
            out = BytesIO()
            im.save(out, format="WEBP", quality=int(quality), method=6)
            result = out.getvalue()
    
    elapsed = time.time() - start
    return elapsed, len(result)


def bench_ffmpeg(data: bytes, quality: int = 80) -> tuple[float, int]:
    """基准：ffmpeg 转码"""
    import subprocess
    import tempfile
    import os
    
    start = time.time()
    
    with tempfile.NamedTemporaryFile(suffix=".gif", delete=False) as tmp_in:
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
            return -1, 0
        
        with open(tmp_out_path, "rb") as f:
            result = f.read()
        
        elapsed = time.time() - start
        return elapsed, len(result)
    finally:
        os.unlink(tmp_in_path)
        os.unlink(tmp_out_path)


async def main():
    test_url = "https://zqdongtuhs.duoduocdn.com/wenzitu/mw690/20260201033045_156.gif"
    
    print("[DOWNLOAD] GIF: " + test_url)
    gif_data = await download_gif(test_url)
    print("[OK] GIF size: {:.2f} KB".format(len(gif_data) / 1024))
    
    with Image.open(BytesIO(gif_data)) as img:
        print("[INFO] Size: {}x{}, Frames: {}".format(
            img.size[0], img.size[1], getattr(img, 'n_frames', 1)
        ))
    
    # 检查 ffmpeg 可用性
    import subprocess
    ffmpeg_available = False
    try:
        subprocess.run(["ffmpeg", "-version"], capture_output=True, timeout=5, check=True)
        ffmpeg_available = True
    except:
        pass
    
    # Pillow 基准
    print("\n[BENCH] Pillow (fast, fallback)...")
    t_pillow, size_pillow = bench_pillow(gif_data)
    print("[RESULT] Pillow: {:.3f}s, Output: {:.2f} KB".format(t_pillow, size_pillow / 1024))
    
    # ffmpeg 基准（如果可用）
    if ffmpeg_available:
        print("\n[BENCH] ffmpeg (fast, libwebp)...")
        t_ffmpeg, size_ffmpeg = bench_ffmpeg(gif_data)
        if t_ffmpeg > 0:
            print("[RESULT] ffmpeg: {:.3f}s, Output: {:.2f} KB".format(t_ffmpeg, size_ffmpeg / 1024))
            speedup = t_pillow / t_ffmpeg
            print("\n[SPEEDUP] ffmpeg is {:.1f}x faster than Pillow".format(speedup))
        else:
            print("[ERROR] ffmpeg 转码失败")
    else:
        print("\n[WARN] ffmpeg 不可用（会自动降级到 Pillow）")


if __name__ == "__main__":
    asyncio.run(main())
