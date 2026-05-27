"""Naive recursive chunker. Splits on paragraph, then sentence, then char."""
import re
from typing import List

# Rough char-per-token heuristic. Good enough for v1, will swap for tiktoken later.
_CHARS_PER_TOKEN = 4


def chunk_text(
    text: str, max_tokens: int = 800, overlap_tokens: int = 100
) -> List[str]:
    """Chunk text into approximately max_tokens-sized pieces with overlap."""
    if not text or not text.strip():
        return []

    max_chars = max_tokens * _CHARS_PER_TOKEN
    overlap_chars = overlap_tokens * _CHARS_PER_TOKEN

    if len(text) <= max_chars:
        return [text.strip()]

    chunks: List[str] = []
    paragraphs = re.split(r"\n\s*\n", text)
    current = ""

    for para in paragraphs:
        para = para.strip()
        if not para:
            continue

        if len(para) > max_chars:
            if current:
                chunks.append(current.strip())
                current = ""
            sentences = re.split(r"(?<=[.!?])\s+", para)
            for sent in sentences:
                if len(current) + len(sent) + 1 > max_chars:
                    if current:
                        chunks.append(current.strip())
                    if len(sent) > max_chars:
                        step = max_chars - overlap_chars
                        for i in range(0, len(sent), step):
                            chunks.append(sent[i : i + max_chars].strip())
                        current = ""
                    else:
                        current = sent
                else:
                    current += (" " + sent) if current else sent
        else:
            if len(current) + len(para) + 2 > max_chars:
                chunks.append(current.strip())
                tail = current[-overlap_chars:] if overlap_chars > 0 else ""
                current = (tail + "\n\n" + para).strip() if tail else para
            else:
                current += ("\n\n" + para) if current else para

    if current.strip():
        chunks.append(current.strip())

    return [c for c in chunks if c]
