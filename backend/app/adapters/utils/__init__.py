"""
Adapter utilities package
"""
from .text_utils import generate_title_from_text, ensure_title
from .anti_risk import (
    truncated_gaussian_delay,
    exponential_backoff,
    progressive_captcha_cooldown,
    merge_response_cookies,
)

__all__ = [
    "generate_title_from_text",
    "ensure_title",
    "truncated_gaussian_delay",
    "exponential_backoff",
    "progressive_captcha_cooldown",
    "merge_response_cookies",
]
