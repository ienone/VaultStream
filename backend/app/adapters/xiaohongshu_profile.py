from __future__ import annotations

from xhshow import CryptoConfig

DEFAULT_XHS_USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36"
)

DEFAULT_XHS_SIGNATURE_DATA_TEMPLATE = {
    "x0": "4.2.6",
    "x1": "xhs-pc-web",
    "x2": "macOS",
    "x3": "",
    "x4": "",
}

DEFAULT_XHS_SIGNATURE_XSCOMMON_TEMPLATE = {
    "s0": 5,
    "s1": "",
    "x0": "1",
    "x1": "4.2.6",
    "x2": "macOS",
    "x3": "xhs-pc-web",
    "x4": "4.86.0",
    "x5": "",
    "x6": "",
    "x7": "",
    "x8": "",
    "x9": -596800761,
    "x10": 0,
    "x11": "normal",
}


def build_xhs_crypto_config(user_agent: str = DEFAULT_XHS_USER_AGENT) -> CryptoConfig:
    return CryptoConfig().with_overrides(
        PUBLIC_USERAGENT=user_agent,
        SIGNATURE_DATA_TEMPLATE=DEFAULT_XHS_SIGNATURE_DATA_TEMPLATE,
        SIGNATURE_XSCOMMON_TEMPLATE=DEFAULT_XHS_SIGNATURE_XSCOMMON_TEMPLATE,
    )
