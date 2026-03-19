from typing import Optional

import bbcode


_BBCodeParser: Optional["bbcode.Parser"] = None


def _get_parser() -> "bbcode.Parser":
    global _BBCodeParser
    if _BBCodeParser is not None:
        return _BBCodeParser

    parser = bbcode.Parser(
        install_defaults=True,
        escape_html=False,
        replace_links=False,
        replace_cosmetic=False,
    )
    _BBCodeParser = parser
    return parser


def convert_bbcode_to_html(text: str) -> str:
    if not isinstance(text, str) or not text:
        return text

    parser = _get_parser()
    return parser.format(text)
