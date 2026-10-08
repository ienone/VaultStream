"""Remove duplicated archive text without dropping distinct source material."""


def compact_archive_text(metadata: dict, body: str | None) -> dict:
    """Retain distinct source text, omit exact copies of the current body."""
    metadata = dict(metadata)
    for name in ("archive", "processed_archive"):
        if not isinstance(metadata.get(name), dict):
            continue
        archive = dict(metadata[name])
        seen = {body} if body else set()
        for field in ("markdown", "plain_text", "html", "raw_html"):
            value = archive.get(field)
            if not isinstance(value, str):
                continue
            if not value or value in seen:
                archive.pop(field)
            else:
                seen.add(value)
        metadata[name] = archive
    return metadata
