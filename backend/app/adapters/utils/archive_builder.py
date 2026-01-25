"""
Archive Builder Utilities

Provides common utilities for building archive structures across all adapters.
This reduces code duplication and ensures consistency in archive format.
"""
from typing import Dict, Any, List, Optional


class ArchiveBuilder:
    """Unified archive structure builder for all platform adapters"""
    
    @staticmethod
    def create_base_archive(
        content_type: str,
        title: str = "",
        plain_text: str = "",
        markdown: str = "",
        version: int = 2
    ) -> Dict[str, Any]:
        """
        Create a base archive structure with common fields
        
        Args:
            content_type: Platform-specific content type (e.g., "bilibili_video", "weibo_status")
            title: Content title
            plain_text: Plain text representation for search/preview
            markdown: Markdown-formatted content (optional)
            version: Archive schema version
        
        Returns:
            Dict with standard archive fields
        
        Example:
            >>> archive = ArchiveBuilder.create_base_archive(
            ...     "bilibili_video",
            ...     title="My Video",
            ...     plain_text="Video description"
            ... )
        """
        return {
            "version": version,
            "type": content_type,
            "title": title,
            "plain_text": plain_text,
            "markdown": markdown,
            "images": [],
            "videos": [],
            "links": [],
            "mentions": [],
            "topics": [],
            "stored_images": [],  # Populated by media processing worker
            "stored_videos": [],  # Populated by media processing worker
        }
    
    @staticmethod
    def select_best_image_url(
        info: Dict[str, Any],
        prefer_order: Optional[List[str]] = None
    ) -> Optional[str]:
        """
        Select best quality image URL from multi-resolution dict
        
        This is commonly needed for Weibo and similar platforms that provide
        multiple resolutions (mw2000, largest, original, bmiddle, thumbnail).
        
        Args:
            info: Dictionary containing resolution keys like {"mw2000": {"url": "..."}}
            prefer_order: Priority list of resolution keys. Defaults to:
                         ['mw2000', 'largest', 'original', 'bmiddle', 'thumbnail']
        
        Returns:
            Best quality URL found, or None if no valid URL exists
        
        Example:
            >>> pic_info = {
            ...     "largest": {"url": "https://wx1.sinaimg.cn/large/123.jpg"},
            ...     "mw2000": {"url": "https://wx1.sinaimg.cn/mw2000/123.jpg"}
            ... }
            >>> url = ArchiveBuilder.select_best_image_url(pic_info)
            >>> assert "mw2000" in url  # Prefers mw2000 over largest
        """
        if not isinstance(info, dict):
            return None
        
        if prefer_order is None:
            prefer_order = ['mw2000', 'largest', 'original', 'bmiddle', 'thumbnail']
        
        for key in prefer_order:
            if key in info and isinstance(info[key], dict):
                url = info[key].get('url')
                if url and isinstance(url, str):
                    return url.strip()
        
        return None
    
    @staticmethod
    def add_image(
        archive: Dict[str, Any],
        url: str,
        width: Optional[int] = None,
        height: Optional[int] = None,
        **extra_fields
    ) -> None:
        """
        Add an image entry to archive
        
        Args:
            archive: Archive dict (will be modified in-place)
            url: Image URL
            width: Optional image width
            height: Optional image height
            **extra_fields: Additional fields (e.g., type="avatar")
        """
        if not url:
            return
        
        img_entry = {"url": url}
        if width is not None:
            img_entry["width"] = width
        if height is not None:
            img_entry["height"] = height
        img_entry.update(extra_fields)
        
        archive.setdefault("images", []).append(img_entry)
    
    @staticmethod
    def add_video(
        archive: Dict[str, Any],
        url: str,
        cover: Optional[str] = None,
        **extra_fields
    ) -> None:
        """
        Add a video entry to archive
        
        Args:
            archive: Archive dict (will be modified in-place)
            url: Video URL
            cover: Optional cover/thumbnail URL
            **extra_fields: Additional fields (e.g., duration, width, height)
        """
        if not url:
            return
        
        vid_entry = {"url": url}
        if cover:
            vid_entry["cover"] = cover
        vid_entry.update(extra_fields)
        
        archive.setdefault("videos", []).append(vid_entry)
    
    @staticmethod
    def validate_archive(archive: Dict[str, Any]) -> bool:
        """
        Validate that archive has required fields
        
        Args:
            archive: Archive dict to validate
        
        Returns:
            True if valid, raises ValueError otherwise
        """
        required = ["type", "title", "plain_text"]
        for field in required:
            if field not in archive:
                raise ValueError(f"Archive missing required field: {field}")
        
        # Validate list fields
        list_fields = ["images", "videos", "links"]
        for field in list_fields:
            if field in archive and not isinstance(archive[field], list):
                raise ValueError(f"Archive field '{field}' must be a list")
        
        return True
