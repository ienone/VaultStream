from __future__ import annotations

from dataclasses import dataclass
from typing import Any


@dataclass(slots=True)
class FavoritesFetchError(Exception):
    """Structured favorites fetch failure with user-facing hint."""

    code: str
    message: str
    hint: str
    retryable: bool = False
    auth_required: bool = False
    details: dict[str, Any] | None = None

    def __str__(self) -> str:
        return self.message

    def as_dict(self) -> dict[str, Any]:
        data: dict[str, Any] = {
            "error_code": self.code,
            "error_message": self.message,
            "error_hint": self.hint,
            "retryable": self.retryable,
            "auth_required": self.auth_required,
        }
        if self.details:
            data["error_details"] = self.details
        return data

