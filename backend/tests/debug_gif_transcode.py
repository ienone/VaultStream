"""
调试脚本：测试 GIF → WebP 转码效果

问题诊断：为什么转码后的 WebP 是静态的？
答案：当前 _image_to_webp() 只保存了 GIF 的第一帧，没有保存所有帧和帧延迟

此脚本对比：
1. 当前逻辑（静态WebP）
2. 改进逻辑（动态WebP）
"""

import asyncio
import httpx
from pathlib import Path
from io import BytesIO
from PIL import Image


async def download_gif(url: str) -> bytes:
    """下载 GIF"""
    async with httpx.AsyncClient(timeout=30.0, follow_redirects=True) as client:
        resp = await client.get(url)
        resp.raise_for_status()
        return resp.content


def image_to_webp_current(data: bytes, quality: int = 80) -> tuple[bytes, int, int]:
    """当前逻辑：只保存第一帧（导致动画丢失）"""
    with Image.open(BytesIO(data)) as im:
        width, height = im.size
        if im.mode in ("P", "LA"):
            im = im.convert("RGBA")
        elif im.mode not in ("RGB", "RGBA"):
            im = im.convert("RGB")

        out = BytesIO()
        im.save(out, format="WEBP", quality=int(quality), method=6)
        # ❌ 问题：只保存了当前帧（第一帧）
        return out.getvalue(), width, height


def image_to_webp_with_animation(data: bytes, quality: int = 80) -> tuple[bytes, int, int]:
    """改进逻辑：保留所有帧和动画"""
    with Image.open(BytesIO(data)) as im:
        width, height = im.size
        
        # 检查是否是动画图像（多帧）
        is_animated = hasattr(im, 'n_frames') and im.n_frames > 1
        
        if is_animated:
            # 提取所有帧和持续时间
            frames = []
            durations = []
            
            for frame_idx in range(im.n_frames):
                im.seek(frame_idx)
                
                # 转换颜色模式
                frame = im.convert("RGBA") if im.mode in ("P", "LA") else im.convert("RGB")
                frames.append(frame)
                
                # 获取帧延迟（毫秒）
                duration = im.info.get('duration', 100)
                durations.append(duration)
            
            # 保存为动态 WebP
            out = BytesIO()
            frames[0].save(
                out,
                format="WEBP",
                quality=int(quality),
                method=6,
                save_all=True,
                append_images=frames[1:],
                duration=durations,
                loop=0  # 无限循环
            )
            return out.getvalue(), width, height
        else:
            # 单帧图像，正常转换
            if im.mode in ("P", "LA"):
                im = im.convert("RGBA")
            elif im.mode not in ("RGB", "RGBA"):
                im = im.convert("RGB")
            
            out = BytesIO()
            im.save(out, format="WEBP", quality=int(quality), method=6)
            return out.getvalue(), width, height


async def main():
    test_url = "https://zqdongtuhs.duoduocdn.com/wenzitu/mw690/20260201033045_156.gif"
    
    print("[DOWNLOAD] GIF: " + test_url)
    gif_data = await download_gif(test_url)
    print("[OK] GIF size: {:.2f} KB".format(len(gif_data) / 1024))
    
    # 检查 GIF 信息
    with Image.open(BytesIO(gif_data)) as img:
        print("\n[GIF INFO]")
        print("   Size: {}x{}".format(img.size[0], img.size[1]))
        print("   Frames: {}".format(getattr(img, 'n_frames', 1)))
        print("   Format: {}".format(img.format))
        if hasattr(img, 'n_frames') and img.n_frames > 1:
            print("   Animated: YES")
        else:
            print("   Animated: NO")
    
    # 测试当前逻辑
    print("\n[CURRENT LOGIC - STATIC]")
    webp_static, w, h = image_to_webp_current(gif_data)
    print("Output size: {:.2f} KB".format(len(webp_static) / 1024))
    print("Compression: {:.1f}%".format(len(webp_static) / len(gif_data) * 100))
    with Image.open(BytesIO(webp_static)) as img:
        print("Frames: {}".format(getattr(img, 'n_frames', 1)))
        print("[WARNING] Only first frame saved, animation lost")
    
    # 测试改进逻辑
    print("\n[IMPROVED LOGIC - ANIMATED]")
    webp_animated, w, h = image_to_webp_with_animation(gif_data)
    print("Output size: {:.2f} KB".format(len(webp_animated) / 1024))
    print("Compression: {:.1f}%".format(len(webp_animated) / len(gif_data) * 100))
    with Image.open(BytesIO(webp_animated)) as img:
        print("Frames: {}".format(getattr(img, 'n_frames', 1)))
        if hasattr(img, 'n_frames') and img.n_frames > 1:
            print("[OK] Animation preserved")
        else:
            print("[ERROR] Animation lost")
    
    # 保存到文件供检查
    out_dir = Path(__file__).parent / "outputs"
    out_dir.mkdir(exist_ok=True)
    
    with open(out_dir / "test_static.webp", "wb") as f:
        f.write(webp_static)
    print("\n[SAVE] Static WebP: {}".format(out_dir / 'test_static.webp'))
    
    with open(out_dir / "test_animated.webp", "wb") as f:
        f.write(webp_animated)
    print("[SAVE] Animated WebP: {}".format(out_dir / 'test_animated.webp'))


if __name__ == "__main__":
    asyncio.run(main())
