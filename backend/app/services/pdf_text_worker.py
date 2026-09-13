"""Local PDF text extraction. Invoked in a killable subprocess, never as an API."""

from hashlib import sha256
from io import BytesIO
import json
from pathlib import Path
import sys

from pypdf import PdfReader

MAX_FILE_BYTES = 64 * 1024 * 1024
MAX_PAGES = 500
MAX_TEXT_CHARS = 2_000_000


def extract_pdf(path: Path, expected_checksum: str | None) -> dict:
    # Read and hash the same bounded snapshot that the parser consumes.
    with path.open("rb") as stream:
        data = stream.read(MAX_FILE_BYTES + 1)
    if len(data) > MAX_FILE_BYTES:
        return {"status": "limit_exceeded"}
    checksum = sha256(data).hexdigest()
    if expected_checksum and checksum != expected_checksum:
        return {"status": "source_changed"}
    if not data.startswith(b"%PDF-"):
        return {"status": "invalid_pdf"}
    try:
        reader = PdfReader(BytesIO(data))
        if reader.is_encrypted:
            return {"status": "encrypted"}
        count = len(reader.pages)
        if count > MAX_PAGES:
            return {"status": "limit_exceeded"}
        pages = []
        total = 0
        for number, page in enumerate(reader.pages, 1):
            # Layout mode interleaves left/right columns on each output line.
            # Preserve PDF content-stream reading order for textual evidence.
            text = page.extract_text(extraction_mode="plain").strip() if "/Contents" in page else ""
            total += len(text)
            if total > MAX_TEXT_CHARS:
                return {"status": "limit_exceeded"}
            pages.append({"page_number": number, "text": text})
        text_pages = sum(bool(page["text"]) for page in pages)
        return {
            "status": "ready" if text_pages == count and count else "partial" if text_pages else "no_text",
            "page_count": count,
            "text_page_count": text_pages,
            "checksum": checksum,
            "pages": pages,
        }
    except Exception:
        # Parser diagnostics may contain file data; do not expose them.
        return {"status": "invalid_pdf"}


if __name__ == "__main__":
    try:
        result = extract_pdf(Path(sys.argv[1]), sys.argv[2] or None)
    except OSError:
        result = {"status": "missing"}
    print(json.dumps(result, ensure_ascii=False))
