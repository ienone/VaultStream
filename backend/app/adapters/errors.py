"""Adapter error taxonomy.

M2 requirement: adapters must classify errors so the pipeline can decide whether to retry,
fail fast, or request credentials.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Optional


@dataclass
class AdapterError(Exception):
    """Base class for adapter errors."""

    message: str
    retryable: bool = False
    auth_required: bool = False
    details: Optional[dict[str, Any]] = None

    def __str__(self) -> str:  # pragma: no cover
        return self.message


class RetryableAdapterError(AdapterError):
    def __init__(self, message: str, *, details: Optional[dict[str, Any]] = None):
        super().__init__(message=message, retryable=True, auth_required=False, details=details)


class NonRetryableAdapterError(AdapterError):
    def __init__(self, message: str, *, details: Optional[dict[str, Any]] = None):
        super().__init__(message=message, retryable=False, auth_required=False, details=details)


class AuthRequiredAdapterError(AdapterError):
    def __init__(self, message: str, *, details: Optional[dict[str, Any]] = None):
        super().__init__(message=message, retryable=False, auth_required=True, details=details)
