"""File types accepted by capture and account synchronization."""


def is_pdf_attachment(filename: str | None, mime: str | None) -> bool:
    return (filename or "").lower().endswith(".pdf") or (mime or "").partition(";")[0].strip().lower() in {
        "application/pdf", "application/x-pdf",
    }
