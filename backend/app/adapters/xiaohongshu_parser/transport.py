"""Shared HTTP pacing and access-error boundaries for Xiaohongshu readers."""
from app.services.source_reading import source_reading
from app.adapters.errors import AuthRequiredAdapterError, NonRetryableAdapterError, RetryableAdapterError


def reading_hooks():
    hooks = source_reading.http_hooks("xiaohongshu")

    async def check_response(response):
        status = response.status_code
        location = response.headers.get("location", "")
        if status == 401:
            raise AuthRequiredAdapterError("小红书当前入口要求登录", details={"status": status})
        if status in (403, 461, 471) or "captcha" in location or "captcha" in str(response.url):
            raise NonRetryableAdapterError("小红书拒绝当前请求或要求验证", details={"status": status, "reason": "verification_required"})
        if status in (404, 410):
            raise NonRetryableAdapterError("小红书内容不可访问", details={"status": status})
        if status >= 400:
            raise RetryableAdapterError(f"小红书请求失败: HTTP {status}", details={"status": status})

    hooks["response"].append(check_response)
    return hooks
