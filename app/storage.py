"""存储后端（本地文件系统 + S3兼容）

目标：
- 为持久化衍生资产（图片/音频/视频）提供简单抽象
- 保持"存档与分享"分离：存储的资产引用仅用于私有存档

设计说明：
- 异步API接口，通过 asyncio.to_thread 实现阻塞SDK的异步调用
- 调用者建议使用基于内容寻址的key（基于sha256）
"""

from __future__ import annotations

import asyncio
import os
from dataclasses import dataclass
from typing import Optional, Literal

from app.config import settings
from app.logging import logger


StorageBackendType = Literal["local", "s3"]


@dataclass(frozen=True)
class StoredObject:
    key: str
    size: int
    sha256: Optional[str] = None
    content_type: Optional[str] = None
    url: Optional[str] = None


class StorageBackend:
    """存储后端基类"""
    async def put_bytes(self, *, key: str, data: bytes, content_type: str) -> StoredObject:
        """存储字节数据"""
        raise NotImplementedError

    async def exists(self, *, key: str) -> bool:
        """检查对象是否存在"""
        raise NotImplementedError

    def get_url(self, *, key: str) -> Optional[str]:
        """获取对象的访问URL"""
        return None


class LocalStorageBackend(StorageBackend):
    def __init__(self, root_dir: str, public_base_url: Optional[str] = None):
        self.root_dir = os.path.abspath(root_dir)
        self.public_base_url = public_base_url.strip().rstrip("/") if public_base_url else None

    def _full_path(self, key: str) -> str:
        safe_key = key.lstrip("/")
        return os.path.join(self.root_dir, safe_key)

    async def exists(self, *, key: str) -> bool:
        path = self._full_path(key)
        return os.path.exists(path)

    def get_url(self, *, key: str) -> Optional[str]:
        if not self.public_base_url:
            return None
        safe_key = key.lstrip("/")
        return f"{self.public_base_url}/{safe_key}"

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


class S3StorageBackend(StorageBackend):
    """S3兼容存储后端（支持MinIO等）"""
    def __init__(
        self,
        *,
        endpoint_url: str,
        bucket: str,
        access_key: str,
        secret_key: str,
        region: str = "us-east-1",
        public_base_url: Optional[str] = None,
        presign_urls: bool = False,
        presign_expires: int = 3600,
    ):
        # boto3 延迟导入，以便仅使用本地存储的部署不需要在导入时安装boto3
        try:
            import boto3  # type: ignore
            from botocore.config import Config  # type: ignore
        except Exception as e:  # pragma: no cover
            raise RuntimeError("S3存储后端需要安装 boto3") from e

        self.bucket = bucket
        self.public_base_url = public_base_url.strip().rstrip("/") if public_base_url else None
        self._presign_urls = bool(presign_urls)
        self._presign_expires = int(presign_expires) if presign_expires else 3600

        # MinIO通常需要签名版本v4；路径样式寻址避免DNS问题
        self._client = boto3.client(
            "s3",
            endpoint_url=endpoint_url,
            aws_access_key_id=access_key,
            aws_secret_access_key=secret_key,
            region_name=region,
            config=Config(signature_version="s3v4", s3={"addressing_style": "path"}),
        )

    async def ensure_bucket(self) -> None:
        """确保存储桶存在。（不存在则创建）
        本地 MinIO 使用，通常开始时是空实例
        """

        try:
            from botocore.exceptions import ClientError  # type: ignore
        except Exception:  # pragma: no cover
            ClientError = Exception  # type: ignore

        def ensure() -> None:
            try:
                self._client.head_bucket(Bucket=self.bucket)
                return
            except ClientError as e:  # type: ignore
                # NoSuchBucket often appears as 404/NoSuchBucket.
                code = None
                status = None
                try:
                    code = e.response.get("Error", {}).get("Code")
                    status = e.response.get("ResponseMetadata", {}).get("HTTPStatusCode")
                except Exception:
                    pass

                if code not in ("NoSuchBucket", "404", "NotFound") and status != 404:
                    raise

            # Create bucket if missing.
            try:
                self._client.create_bucket(Bucket=self.bucket)
            except ClientError as e:  # type: ignore
                # 某些 S3 实现要求非 us-east-1 区域必须指定 LocationConstraint。
                code = None
                try:
                    code = e.response.get("Error", {}).get("Code")
                except Exception:
                    pass
                if code in ("IllegalLocationConstraintException", "InvalidLocationConstraint"):
                    # 尽量使用指定区域创建桶。
                    self._client.create_bucket(
                        Bucket=self.bucket,
                        CreateBucketConfiguration={"LocationConstraint": (getattr(settings, "storage_s3_region", "us-east-1") or "us-east-1")},
                    )
                else:
                    raise

        await asyncio.to_thread(ensure)

    def get_url(self, *, key: str) -> Optional[str]:
        safe_key = key.lstrip("/")
        # 如果bucket是私有的，优先使用预签名URL。
        # 否则，如果配置了 public_base_url，则使用它。
        # 否则返回 None。
        if self._presign_urls:
            try:
                return self._client.generate_presigned_url(
                    ClientMethod="get_object",
                    Params={"Bucket": self.bucket, "Key": safe_key},
                    ExpiresIn=max(60, int(self._presign_expires)),
                )
            except Exception as e:
                # 预签名失败为非致命问题，记录日志便于排查并继续尝试其它访问方式
                logger.warning("generate_presigned_url failed: %s", e)

        if self.public_base_url:
            return f"{self.public_base_url}/{self.bucket}/{safe_key}"

        return None

    async def exists(self, *, key: str) -> bool:
        def head() -> bool:
            try:
                self._client.head_object(Bucket=self.bucket, Key=key)
                return True
            except Exception as e:
                # 将异常视作“对象不存在”并记录调试信息
                logger.debug("head_object check failed for %s: %s", key, e)
                return False

        return await asyncio.to_thread(head)

    async def put_bytes(self, *, key: str, data: bytes, content_type: str) -> StoredObject:
        def put() -> None:
            self._client.put_object(
                Bucket=self.bucket,
                Key=key,
                Body=data,
                ContentType=content_type,
            )

        await asyncio.to_thread(put)
        return StoredObject(key=key, size=len(data), content_type=content_type, url=self.get_url(key=key))


_backend_singleton: StorageBackend | None = None


def get_storage_backend() -> StorageBackend:
    """获取基于配置的单例存储后端。

    配置项：
    - storage_backend: local | s3
    - storage_local_root
    - storage_public_base_url (optional)
    - storage_s3_endpoint, storage_s3_bucket, storage_s3_access_key, storage_s3_secret_key, storage_s3_region
    """

    global _backend_singleton
    if _backend_singleton is not None:
        return _backend_singleton

    backend = getattr(settings, "storage_backend", "local")
    public_base_url_raw = getattr(settings, "storage_public_base_url", None)
    public_base_url = (public_base_url_raw or "").strip() or None

    if backend == "s3":
        endpoint = (getattr(settings, "storage_s3_endpoint", None) or "").strip()
        bucket = (getattr(settings, "storage_s3_bucket", None) or "").strip()
        access_key_obj = getattr(settings, "storage_s3_access_key", None)
        secret_key_obj = getattr(settings, "storage_s3_secret_key", None)
        region = (getattr(settings, "storage_s3_region", "us-east-1") or "us-east-1").strip()

        access_key = access_key_obj.get_secret_value().strip() if access_key_obj else ""
        secret_key = secret_key_obj.get_secret_value().strip() if secret_key_obj else ""

        if not endpoint or not bucket or not access_key or not secret_key:
            raise RuntimeError("选择了S3存储后端，但S3配置不完整")

        _backend_singleton = S3StorageBackend(
            endpoint_url=endpoint,
            bucket=bucket,
            access_key=access_key,
            secret_key=secret_key,
            region=region,
            public_base_url=public_base_url,
            presign_urls=bool(getattr(settings, "storage_s3_presign_urls", False)),
            presign_expires=int(getattr(settings, "storage_s3_presign_expires", 3600) or 3600),
        )
        logger.info("存储后端: s3 (bucket={})", bucket)
        return _backend_singleton

    root = getattr(settings, "storage_local_root", "data/storage")
    _backend_singleton = LocalStorageBackend(root_dir=root, public_base_url=public_base_url)
    logger.info("存储后端: local (root_dir={})", os.path.abspath(root))
    return _backend_singleton
