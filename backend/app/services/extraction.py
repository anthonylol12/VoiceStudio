"""Document text extraction: PDF (PyMuPDF + OCR fallback), Excel, CSV, HTML,
plain text and images."""

from __future__ import annotations

import csv
import io
from collections.abc import Callable
from pathlib import Path

from .providers import EngineUnavailable

IMAGE_EXT = {".jpg", ".jpeg", ".png", ".webp", ".bmp", ".tif", ".tiff"}


class ExtractionError(ValueError):
    pass


def _decode(data: bytes) -> str:
    for enc in ("utf-8-sig", "cp1252", "latin-1"):
        try:
            return data.decode(enc)
        except UnicodeDecodeError:
            continue
    return data.decode("utf-8", errors="replace")


def table_to_text(rows: list[list[str]], sheet: str | None = None) -> str:
    """Same reading format as the Flutter client: header-aware rows."""
    clean = [[(c or "").strip() for c in r] for r in rows]
    clean = [r for r in clean if any(r)]
    if not clean:
        return ""
    first = clean[0]

    def is_num(v: str) -> bool:
        try:
            float(v.replace(",", "."))
            return True
        except ValueError:
            return False

    header = len(clean) > 1 and sum(1 for c in first if c) >= 2 and all(not c or not is_num(c) for c in first)
    body = clean[1:] if header else clean
    out = [f"{sheet}."] if sheet else []
    for n, row in enumerate(body, start=1):
        parts = []
        for i, v in enumerate(row):
            if not v:
                continue
            h = f"{first[i]}: " if header and i < len(first) and first[i] else ""
            parts.append(f"{h}{v}")
        if parts:
            out.append(f"{'Fila ' + str(n) + '. ' if header else ''}{'; '.join(parts)}.")
    return "\n\n".join(out)


def html_to_text(html: str) -> tuple[str, str]:
    from bs4 import BeautifulSoup

    soup = BeautifulSoup(html, "html.parser")
    title = soup.title.get_text(strip=True) if soup.title else ""
    for tag in soup(["script", "style", "noscript", "nav", "footer", "header", "aside", "form", "iframe", "svg"]):
        tag.decompose()
    root = soup.find("article") or soup.find("main") or soup.body or soup
    blocks = []
    for el in root.find_all(["h1", "h2", "h3", "h4", "p", "li", "td", "th", "blockquote", "pre"]):
        if el.find_parent(["li", "td", "th", "blockquote"]) and el.name in ("p",):
            continue
        t = " ".join(el.get_text(" ", strip=True).split())
        if t:
            blocks.append(f"- {t}" if el.name == "li" else t)
    return title, "\n\n".join(blocks)


def extract(filename: str, data: bytes, ocr: Callable[[bytes], str] | None = None) -> dict:
    """Returns {"title", "kind", "pages": [{"number", "text"}]}."""
    ext = Path(filename).suffix.lower()
    title = Path(filename).stem
    pages: list[str]
    kind: str
    if ext == ".pdf":
        kind = "pdf"
        pages = _pdf(data, ocr)
    elif ext == ".xlsx":
        kind = "excel"
        from openpyxl import load_workbook

        wb = load_workbook(io.BytesIO(data), read_only=True, data_only=True)
        pages = []
        for ws in wb.worksheets:
            rows = [["" if v is None else str(v) for v in r] for r in ws.iter_rows(values_only=True)]
            t = table_to_text(rows, ws.title if len(wb.worksheets) > 1 else None)
            if t:
                pages.append(t)
    elif ext == ".xls":
        kind = "excel"
        import xlrd

        book = xlrd.open_workbook(file_contents=data)
        pages = []
        for sh in book.sheets():
            rows = [[str(sh.cell_value(r, c)) for c in range(sh.ncols)] for r in range(sh.nrows)]
            t = table_to_text(rows, sh.name if book.nsheets > 1 else None)
            if t:
                pages.append(t)
    elif ext == ".csv":
        kind = "csv"
        pages = [table_to_text(list(csv.reader(io.StringIO(_decode(data)))))]
    elif ext in (".html", ".htm"):
        kind = "web"
        t, text = html_to_text(_decode(data))
        title = t or title
        pages = [text]
    elif ext in (".txt", ".md"):
        kind = "text"
        pages = [_decode(data)]
    elif ext in IMAGE_EXT:
        kind = "image"
        if ocr is None:
            raise EngineUnavailable("OCR no disponible.")
        pages = [ocr(data)]
    else:
        raise ExtractionError(f"Formato no compatible: {ext or 'desconocido'}")
    pages = [p.strip() for p in pages]
    if not any(pages):
        raise ExtractionError("No se encontró texto legible en el documento.")
    return {"title": title, "kind": kind, "pages": [{"number": i + 1, "text": t} for i, t in enumerate(pages)]}


def _pdf(data: bytes, ocr: Callable[[bytes], str] | None) -> list[str]:
    import pymupdf

    try:
        doc = pymupdf.open(stream=data, filetype="pdf")
    except Exception as e:
        raise ExtractionError(f"PDF no válido: {e}") from e
    pages = []
    with doc:
        for page in doc:
            text = page.get_text("text", sort=True).strip()
            if not text and ocr is not None:
                # Scanned page: render at 200 dpi and OCR it.
                pix = page.get_pixmap(dpi=200)
                try:
                    text = ocr(pix.tobytes("png"))
                except EngineUnavailable:
                    text = ""
            pages.append(text)
    return pages
