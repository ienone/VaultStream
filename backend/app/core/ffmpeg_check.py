"""
ffmpeg 可用性检查模块

在应用启动时检查 ffmpeg 是否可用，并记录到日志
"""

import subprocess
from typing import Optional
from app.core.logging import logger


def check_ffmpeg_available() -> bool:
    """检查 ffmpeg 是否可用
    
    Returns:
        True if ffmpeg is available, False otherwise
    """
    try:
        result = subprocess.run(
            ["ffmpeg", "-version"],
            capture_output=True,
            timeout=5,
            check=False
        )
        return result.returncode == 0
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return False


def get_ffmpeg_version() -> Optional[str]:
    """获取 ffmpeg 版本号
    
    Returns:
        Version string like "N-00000-g00000000" or None if ffmpeg not available
    """
    try:
        result = subprocess.run(
            ["ffmpeg", "-version"],
            capture_output=True,
            timeout=5,
            check=False,
            text=True
        )
        if result.returncode == 0:
            # 第一行通常是: ffmpeg version ...
            first_line = result.stdout.split('\n')[0] if result.stdout else ""
            return first_line.strip()
        return None
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return None


def log_ffmpeg_status():
    """在应用启动时记录 ffmpeg 可用性状态"""
    available = check_ffmpeg_available()
    version = get_ffmpeg_version() if available else None
    
    if available:
        logger.info(
            "ffmpeg is available for media transcoding (GIF animation 25x faster)",
            extra={
                "ffmpeg_available": True,
                "ffmpeg_version": version,
                "performance_boost": "25x for animated GIF"
            }
        )
    else:
        logger.warning(
            "ffmpeg is not available. GIF animation transcoding will be slow. "
            "See https://github.com/ienone/VaultStream/blob/main/FFMPEG_SETUP.md",
            extra={
                "ffmpeg_available": False,
                "recommendation": "install ffmpeg for 25x GIF transcoding speedup"
            }
        )
