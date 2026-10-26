"""Document text for the renderer: the same rules the Earshot app uses.

Mirrors lib/services/extract.dart, segmenter.dart and cast.dart, so a document
splits into the same paragraphs, sentences and cast lines in both places.
"""
from __future__ import annotations

import os
import re
import zipfile
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field

SUPPORTED = (".pdf", ".docx", ".txt", ".md", ".markdown", ".text")
MAX_CHUNK = 320

# ------------------------------------------------------------------ decoding


def decode_text(b: bytes) -> str:
    if b.startswith(b"\xef\xbb\xbf"):
        return b[3:].decode("utf-8", errors="replace")
    if b.startswith(b"\xff\xfe"):
        return b[2:].decode("utf-16-le", errors="replace")
    if b.startswith(b"\xfe\xff"):
        return b[2:].decode("utf-16-be", errors="replace")
    head = b[:2000]
    n = len(head) & ~1
    if n >= 8:
        even = sum(1 for i in range(0, n, 2) if head[i] == 0)
        odd = sum(1 for i in range(1, n, 2) if head[i] == 0)
        if odd > n / 4 and even == 0:
            return b.decode("utf-16-le", errors="replace")
        if even > n / 4 and odd == 0:
            return b.decode("utf-16-be", errors="replace")
    return b.decode("utf-8", errors="replace")


# ------------------------------------------------------------------ extraction


def extract_text(path: str) -> str:
    ext = os.path.splitext(path)[1].lower()
    if ext == ".pdf":
        text = _pdf(path)
    elif ext == ".docx":
        text = docx_text(path)
    elif ext in (".md", ".markdown"):
        raw = decode_text(open(path, "rb").read())
        text = raw if has_cast_header(raw) else markdown_text(raw)
    else:
        text = plain_text(decode_text(open(path, "rb").read()))
    if not text.strip():
        raise ValueError("No readable text found" + (" (it may be a scanned PDF)." if ext == ".pdf" else "."))
    return text


def plain_text(s: str) -> str:
    t = s.replace("\r\n", "\n")
    if re.search(r"\n\s*\n", t):
        return t
    lines = [l for l in t.split("\n") if l.strip()]
    if not lines:
        return ""
    avg = sum(len(l) for l in lines) / len(lines)
    return "\n\n".join(lines) if avg > 90 else t


def markdown_text(s: str) -> str:
    out, buf, in_code = [], [], False

    def flush():
        if buf:
            out.append(" ".join(buf).strip())
        buf.clear()

    for line in s.replace("\r\n", "\n").split("\n"):
        st = line.strip()
        if st.startswith("```") or st.startswith("~~~"):
            in_code = not in_code
            flush()
            continue
        if in_code:
            continue
        if not st or re.fullmatch(r"(-{3,}|\*{3,}|_{3,})", st):
            flush()
            continue
        if re.match(r"^\|?\s*:?-{3,}", st):
            continue
        block = re.match(r"^(#{1,6}\s+|[-*+]\s+|\d+[.)]\s+|>\s?)", st)
        if block:
            flush()
            line = st[block.end():]
        line = re.sub(r"!\[([^\]]*)\]\([^)]*\)", r"\1", line)
        line = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", line)
        line = re.sub(r"[*_`]{1,3}", "", line).replace("|", ", ")
        buf.append(line.strip())
        if block and block.group(0).startswith("#"):
            flush()
    flush()
    return "\n\n".join(p for p in out if p)


W = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"


def docx_text(path: str) -> str:
    try:
        with zipfile.ZipFile(path) as z:
            xml = z.read("word/document.xml")
    except (zipfile.BadZipFile, KeyError) as e:
        raise ValueError("This doesn't look like a Word (.docx) file.") from e
    root = ET.fromstring(xml)
    paragraphs: list[str] = []
    buf: list[str] = []

    def walk(node):
        for child in node:
            tag = child.tag
            if tag == W + "p":
                if buf:
                    paragraphs.append("".join(buf))
                buf.clear()
                walk(child)
                if buf:
                    paragraphs.append("".join(buf))
                buf.clear()
            elif tag == W + "t":
                buf.append(child.text or "")
            elif tag in (W + "tab", W + "br", W + "cr"):
                buf.append(" ")
            elif tag in (W + "del", W + "instrText"):
                continue
            else:
                walk(child)

    walk(root)
    return "\n\n".join(p.strip() for p in paragraphs if p.strip())


def _pdf(path: str) -> str:
    from pypdf import PdfReader

    pages = [(p.extract_text() or "").split("\n") for p in PdfReader(path).pages]
    return pdf_lines_to_text(pages)


def pdf_lines_to_text(pages: list[list[str]]) -> str:
    paragraphs: list[str] = []
    buf = ""

    def flush():
        nonlocal buf
        if buf.strip():
            paragraphs.append(buf.strip())
        buf = ""

    ends = re.compile(r"""[.!?:]["'”’)]*$""")
    for raw in pages:
        lines = [l.strip() for l in raw]
        widths = sorted(len(l) for l in lines if l)
        typical = widths[min(int(len(widths) * 0.8), len(widths) - 1)] if widths else 0
        for line in lines:
            if not line:
                flush()
                continue
            if re.fullmatch(r"(page\s*)?\d+(\s*(of|/)\s*\d+)?", line, re.I):
                continue
            prev = buf
            if prev.endswith("-") and re.match(r"^[a-z]", line):
                buf = prev[:-1] + line
            else:
                buf = (buf + " " + line) if buf else line
            ends_sentence = bool(ends.search(line))
            heading = (not prev and not ends_sentence and line and len(line) < typical * 0.6
                       and re.match(r"^[A-Z0-9]", line))
            if heading or (ends_sentence and len(line) < typical * 0.75):
                flush()
        if ends.search(buf):
            flush()
    flush()
    return "\n\n".join(paragraphs)


# ------------------------------------------------------------------ voices

# Earshot's Kokoro voices: id -> (name, sid). Mirrors lib/voices.dart.
VOICES = {
    "af_heart": "Heart", "af_bella": "Bella", "af_nicole": "Nicole", "am_michael": "Michael",
    "am_fenrir": "Fenrir", "bf_emma": "Emma", "bm_george": "George", "bm_fable": "Fable",
    "af_aoede": "Aoede", "af_kore": "Kore", "af_sarah": "Sarah", "af_nova": "Nova",
    "af_alloy": "Alloy", "af_sky": "Sky", "af_jessica": "Jessica", "af_river": "River",
    "am_puck": "Puck", "am_echo": "Echo", "am_eric": "Eric", "am_liam": "Liam", "am_onyx": "Onyx",
    "am_adam": "Adam", "bf_isabella": "Isabella", "bf_alice": "Alice", "bf_lily": "Lily",
    "bm_lewis": "Lewis", "bm_daniel": "Daniel",
}


def find_voice(name_or_id: str) -> str | None:
    n = name_or_id.strip().lower()
    for vid, name in VOICES.items():
        if vid == n or name.lower() == n:
            return vid
    return None


def describe_voice(vid: str) -> str:
    """A plain description of a Kokoro voice, for Qwen when the cast gives none."""
    accent = "British" if vid.startswith("b") else "American"
    who = "woman" if vid[1] == "f" else "man"
    return f"An adult {accent} {who} with a clear, natural voice"


# ------------------------------------------------------------------ cast


@dataclass
class CastLine:
    text: str
    speaker: str | None = None
    voice: str | None = None
    description: str | None = None
    delivery: str = ""
    pause_ms: int = 0


def _header(lines: list[str]):
    """Returns (first body line, {name: (voice id, description)}) or None."""
    i = 0
    while i < len(lines) and not lines[i].strip():
        i += 1
    if i >= len(lines) or lines[i].strip() != "---":
        return None
    i += 1
    while i < len(lines) and not lines[i].strip():
        i += 1
    if i >= len(lines) or lines[i].strip().lower() != "voices:":
        return None
    i += 1
    cast: dict[str, tuple[str, str | None]] = {}
    while i < len(lines):
        l = lines[i].strip()
        if l == "---":
            return i + 1, cast
        m = re.match(r"^(.+?)\s*:\s*([^|]+?)\s*(?:\|\s*(.+))?$", l)
        if m:
            vid = find_voice(m.group(2))
            if vid:
                cast[m.group(1).strip().lower()] = (vid, (m.group(3) or "").strip() or None)
        i += 1
    return None


def has_cast_header(text: str) -> bool:
    return _header(text.replace("\r\n", "\n").split("\n")) is not None


def parse_cast(text: str) -> list[CastLine] | None:
    lines = text.replace("\r\n", "\n").split("\n")
    h = _header(lines)
    if h is None:
        return None
    start, cast = h
    narrator = cast.get("narrator")
    out: list[CastLine] = []
    for raw in lines[start:]:
        line = raw.strip()
        if not line:
            continue
        pause = re.fullmatch(r"\[\s*pause\s*([\d.]+)\s*(ms|s)?\s*\]", line, re.I)
        if pause:
            n = float(pause.group(1))
            ms = n if (pause.group(2) or "").lower() == "ms" else n * 1000
            out.append(CastLine(text="", pause_ms=int(min(max(ms, 0), 30000))))
            continue
        speaker, delivery = None, ""
        b = re.match(r"^\[([^\]]+)\]\s*(.*)$", line)
        if b:
            parts = b.group(1).split(",")
            first = parts[0].strip()
            if first.lower() in cast:
                speaker, delivery = first, ",".join(parts[1:]).strip()
            else:
                delivery = b.group(1).strip()
            line = b.group(2).strip()
        else:
            c = re.match(r"^([^:()\[\]]{1,40}?)\s*(?:\(([^)]*)\))?\s*:\s*(.+)$", line)
            if c and c.group(1).strip().lower() in cast:
                speaker, delivery, line = c.group(1).strip(), (c.group(2) or "").strip(), c.group(3).strip()
        p = re.match(r"^\(([^)]*)\)\s*(.*)$", line)
        if p:
            delivery = ", ".join(x for x in (delivery, p.group(1).strip()) if x)
            line = p.group(2).strip()
        if not line:
            continue
        who = cast.get(speaker.lower()) if speaker else narrator
        out.append(CastLine(text=line, speaker=speaker, voice=who[0] if who else None,
                            description=who[1] if who else None, delivery=delivery))
    return out


# ------------------------------------------------------------------ sentences

ABBREVIATIONS = {
    "e.g", "i.e", "mr", "mrs", "ms", "dr", "vs", "etc", "fig", "no", "st", "jr", "sr", "inc", "ltd",
    "approx", "dept", "est", "cf", "al", "vol", "p", "pp", "ch", "sec", "min", "max", "jan", "feb",
    "mar", "apr", "jun", "jul", "aug", "sep", "sept", "oct", "nov", "dec",
}


def split_sentences(p: str) -> list[str]:
    result, start = [], 0
    for m in re.finditer(r"""[.!?…]+["'”’)\]]*(?=\s+["'“‘(\[]?[A-Z0-9])""", p):
        before = p[start:m.start()]
        lw = re.search(r"([A-Za-z.]+)$", before)
        w = (lw.group(1) if lw else "").lower()
        if m.group(0).startswith(".") and (w in ABBREVIATIONS or (len(w) == 1 and w.isalpha()) or "." in w):
            continue
        result.append(p[start:m.end()].strip())
        start = m.end()
    rest = p[start:].strip()
    if rest:
        result.append(rest)
    return result


def limit(s: str) -> list[str]:
    out, rest = [], s
    while len(rest) > MAX_CHUNK:
        window, cut = rest[:MAX_CHUNK], -1
        for sep in ("; ", ": ", ", ", " – ", " - ", " "):
            i = window.rfind(sep)
            if i > MAX_CHUNK // 3:
                cut = i + len(sep)
                break
        if cut < 0:
            cut = MAX_CHUNK
        out.append(rest[:cut].strip())
        rest = rest[cut:].strip()
    if rest:
        out.append(rest)
    return out


def for_speech(s: str) -> str:
    t = re.sub(r"https?://(?:www\.)?([^/\s]+)\S*", r"link to \1", s)
    t = re.sub(r"[•▪●◦■□►▶※†‡§¶|*_#~`^<>{}\[\]\\]", " ", t)
    t = t.replace("&", " and ")
    t = re.sub(r"\s+", " ", t).strip()
    if not re.search(r"[A-Za-z]", t) and not re.search(r"\d{2,}", t):
        return ""
    return t


@dataclass
class Segment:
    paragraph: int
    text: str
    label: str | None = None
    voice: str | None = None
    description: str | None = None
    delivery: str = ""
    pause_ms: int = 0
    cast: bool = False
    extra: dict = field(default_factory=dict)


def segment(text: str) -> list[Segment]:
    cast = parse_cast(text)
    out: list[Segment] = []
    if cast is not None:
        for pi, l in enumerate(cast):
            if l.pause_ms:
                out.append(Segment(pi, "", pause_ms=l.pause_ms, cast=True))
                continue
            first = True
            for s in split_sentences(re.sub(r"\s+", " ", l.text)):
                for c in limit(s):
                    out.append(Segment(pi, c, label=l.speaker if first else None, voice=l.voice,
                                       description=l.description, delivery=l.delivery, cast=True))
                    first = False
        return out
    paragraphs = [re.sub(r"\s+", " ", p).strip() for p in re.split(r"\n\s*\n", text.replace("\r\n", "\n"))]
    for pi, p in enumerate(x for x in paragraphs if x):
        for s in split_sentences(p):
            for c in limit(s):
                out.append(Segment(pi, c))
    return out
