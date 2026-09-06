"""存储后端（本地文件系统）

目标：
- 为持久化衍生资产（图片/音频/视频）提供简单抽象
- 保持"存档与分享"分离：存储的资产引用仅用于私有存档

设计说明：
- 异步API接口，通过 asyncio.to_thread 实现阻塞SDK的异步调用
- 调用者建议使用基于内容寻址的key（基于sha256）
"""

from __future__ import annotations

import asyncio
import hashlib
import os
import uuid
from contextlib import asynccontextmanager
from dataclasses import dataclass
from typing import AsyncIterable, Optional, Literal

from app.core.config import settings
from app.core.logging import logger


StorageBackendType = Literal["local"]


@dataclass(frozen=True)
class StoredObject:
    key: str
    size: int
    sha256: Optional[str] = None
    content_type: Optional[str] = None
    url: Optional[str] = None


class StorageObjectTooLargeError(ValueError):
    def __init__(self, max_bytes: int):
        self.max_bytes = max_bytes
        super().__init__(f"Object exceeds {max_bytes} bytes")


class StorageObjectEmptyError(ValueError):
    pass


class LocalStorageBackend:
    def __init__(self, root_dir: str, public_base_url: Optional[str] = None):
        self.root_dir = os.path.abspath(root_dir)
        self.public_base_url = public_base_url.strip().rstrip("/") if public_base_url else None

    def _full_path(self, key: str) -> str:
        """将key转换为分片路径（支持sha256:前缀）"""
        safe_key = key.lstrip("/")
        
        # 如果是sha256格式，进行2级目录分片
        if safe_key.startswith("sha256:"):
            hash_val = safe_key.split(":", 1)[1]
            # sha256:abcdef... -> ab/cd/abcdef...
            return os.path.join(self.root_dir, hash_val[:2], hash_val[2:4], hash_val)
        
        return os.path.join(self.root_dir, safe_key)

    async def exists(self, *, key: str) -> bool:
        path = self._full_path(key)
        return os.path.exists(path)
        
    def get_local_path(self, *, key: str) -> Optional[str]:
        path = self._full_path(key)
        if os.path.exists(path):
            return path
        return None

    async def get_bytes(self, key: str) -> bytes:
        path = self._full_path(key)

        def read_file() -> bytes:
            with open(path, "rb") as f:
                return f.read()

        try:
            return await asyncio.to_thread(read_file)
        except Exception as e:
            logger.error(f"Read object failed: {key}, {e}")
            raise

    def get_url(self, *, key: str) -> Optional[str]:
        if not self.public_base_url:
            return None
        safe_key = key.lstrip("/")
        return f"{self.public_base_url}/{safe_key}"

    async def delete(self, *, key: str) -> bool:
        """删除存储对象，返回是否成功删除"""
        path = self._full_path(key)

        def remove_file() -> bool:
            if os.path.exists(path):
                os.remove(path)
                return True
            return False

        try:
            return await asyncio.to_thread(remove_file)
        except Exception as e:
            logger.error(f"Delete object failed: {key}, {e}")
            return False

    async def put_bytes(self, *, key: str, data: bytes, content_type: str) -> StoredObject:
        path = self._full_path(key)
        os.makedirs(os.path.dirname(path), exist_ok=True)

        tmp_path = path + ".tmp"

        def write_atomic() -> None:
            with open(tmp_path, "wb") as f:
                f.write(data)
                f.flush()
                os.fsync(f.fileno())
            os.replace(tmp_path, path)

        await asyncio.to_thread(write_atomic)
        return StoredObject(key=key, size=len(data), content_type=content_type, url=self.get_url(key=key))

    @asynccontextmanager
    async def stage_stream(
        self,
        *,
        chunks: AsyncIterable[bytes],
        content_type: str,
        max_bytes: int,
    ):
        """Stage an upload until the enclosing capture batch has validated."""
        incoming_dir = os.path.join(self.root_dir, ".incoming")
        await asyncio.to_thread(os.makedirs, incoming_dir, exist_ok=True)
        temp_path = os.path.join(incoming_dir, f"{uuid.uuid4().hex}.tmp")
        stream = await asyncio.to_thread(open, temp_path, "wb")
        digest = hashlib.sha256()
        total = 0

        try:
            async for chunk in chunks:
                if not chunk:
                    continue
                total += len(chunk)
                if total > max_bytes:
                    raise StorageObjectTooLargeError(max_bytes)
                digest.update(chunk)
                await asyncio.to_thread(stream.write, chunk)

            if total == 0:
                raise StorageObjectEmptyError("Object cannot be empty")

            def sync_and_close() -> None:
                stream.flush()
                os.fsync(stream.fileno())
                stream.close()

            await asyncio.to_thread(sync_and_close)
            checksum = digest.hexdigest()
            key = f"sha256:{checksum}"
            yield StoredObject(
                key=key,
                size=total,
                sha256=checksum,
                content_type=content_type,
                url=self.get_url(key=key),
            ), temp_path
        finally:
            if not stream.closed:
                await asyncio.to_thread(stream.close)
            if os.path.exists(temp_path):
                await asyncio.to_thread(os.remove, temp_path)

    async def publish_staged(self, stored: StoredObject, temp_path: str) -> bool:
        """Publish without replacing an existing shared content-addressed file."""
        destination = self._full_path(stored.key)

        def publish() -> bool:
            os.makedirs(os.path.dirname(destination), exist_ok=True)
            try:
                os.link(temp_path, destination)
            except FileExistsError:
                return False
            return True

        return await asyncio.to_thread(publish)


_backend_singleton: LocalStorageBackend | None = None


def get_storage_backend() -> LocalStorageBackend:
    """获取基于配置的单例存储后端。

    配置项:
    - storage_backend: local (仅支持本地文件系统)
    - storage_local_root
    - storage_public_base_url (optional)
    """

    global _backend_singleton
    if _backend_singleton is not None:
        return _backend_singleton

    backend = getattr(settings, "storage_backend", "local")
    public_base_url_raw = getattr(settings, "storage_public_base_url", None)
    public_base_url = (public_base_url_raw or "").strip() or None

    root = getattr(settings, "storage_local_root", "data/storage")
    _backend_singleton = LocalStorageBackend(root_dir=root, public_base_url=public_base_url)
    logger.info("存储后端: local (root_dir={})", os.path.abspath(root))
    return _backend_singleton
