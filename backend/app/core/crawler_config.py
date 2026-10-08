"""Per-domain browser render delays."""

from urllib.parse import urlsplit


DEFAULT_DELAY = 5.0

_DELAY_RULES: tuple[tuple[float, tuple[str, ...]], ...] = (
    (
        20.0,
        (
            "twitter.com",
            "x.com",
            "t.co",
            "instagram.com",
            "facebook.com",
            "fb.com",
            "reddit.com",
            "tiktok.com",
            "tumblr.com",
            "pinterest.com",
            "youtube.com",
            "youtu.be",
            "twitch.tv",
            "vimeo.com",
        ),
    ),
    (
        15.0,
        (
            "github.com",
            "githubusercontent.com",
            "medium.com",
            "dev.to",
            "stackoverflow.com",
            "google.com",
            "blogger.com",
            "blogspot.com",
            "telegram.org",
            "t.me",
            "discord.com",
            "discord.gg",
            "flickr.com",
        ),
    ),
)


def get_delay_for_url(url: str) -> float:
    try:
        domain = (urlsplit(url).hostname or "").lower().removeprefix("www.")
    except ValueError:
        return DEFAULT_DELAY

    for delay, patterns in _DELAY_RULES:
        if any(
            domain == pattern or domain.endswith(f".{pattern}")
            for pattern in patterns
        ):
            return delay
    return DEFAULT_DELAY
