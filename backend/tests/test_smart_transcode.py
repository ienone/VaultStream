"""
测试智能转码策略：自动选择 Pillow 还是 ffmpeg

验证修复后的 _image_to_webp() 函数
"""

import asyncio
import sys
from pathlib import Path

# 添加 backend 到 path
sys.path.insert(0, str(Path(__file__).parent.parent))

import httpx
from io import BytesIO
from PIL import Image
from app.media.processor import _image_to_webp


async def download_image(url: str) -> bytes:
    """下载图片"""
    async with httpx.AsyncClient(timeout=30.0, follow_redirects=True) as client:
        resp = await client.get(url)
        resp.raise_for_status()
        return resp.content


async def test_transcode(name: str, url: str):
    """测试转码"""
    print("\n" + "="*60)
    print("[TEST] " + name)
    print("="*60)
    
    try:
        print("[DOWNLOAD] " + url)
        data = await download_image(url)
        print("[OK] Size: {:.2f} KB".format(len(data) / 1024))
        
        # 获取原始信息
        with Image.open(BytesIO(data)) as img:
            is_anim = hasattr(img, 'n_frames') and img.n_frames > 1
            frames = getattr(img, 'n_frames', 1)
            print("[INFO] Format: {}, Size: {}x{}, Frames: {}, Animated: {}".format(
                img.format, img.size[0], img.size[1], frames, is_anim
            ))
        
        # 调用智能转码
        print("[TRANSCODE] 调用 _image_to_webp()...")
        import time
        start = time.time()
        webp_data, width, height = _image_to_webp(data, quality=80)
        elapsed = time.time() - start
        
        print("[RESULT] {:.3f}s -> {:.2f} KB, Size: {}x{}".format(
            elapsed, len(webp_data) / 1024, width, height
        ))
        
        # 验证输出
        with Image.open(BytesIO(webp_data)) as img:
            out_frames = getattr(img, 'n_frames', 1)
            print("[VERIFY] Output frames: {}, Animated: {}".format(
                out_frames, out_frames > 1
            ))
            
            # 检查动画是否保留
            if is_anim:
                if out_frames > 1:
                    print("[OK] 动画保留成功")
                else:
                    print("[ERROR] 动画丢失")
    
    except Exception as e:
        print("[ERROR] " + str(e))
        import traceback
        traceback.print_exc()


async def main():
    tests = [
        ("PNG (Static Image)", "https://blog.ienone.top/anime/anime-rating-criteria/featured_hu_90db38e006de2711.png"),
        ("GIF (Animated)", "https://zqdongtuhs.duoduocdn.com/wenzitu/mw690/20260201033045_156.gif"),
    ]
    
    for name, url in tests:
        try:
            await test_transcode(name, url)
        except Exception as e:
            print("[ERROR] Test failed: " + str(e))
            import traceback
            traceback.print_exc()


if __name__ == "__main__":
    asyncio.run(main())
