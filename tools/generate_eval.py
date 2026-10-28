#!/usr/bin/env python3
"""Rebuild Tavi's fixed accuracy set from the model generator's pinned sources.

Every word is held out of the model's word lists (its Bloom-filter floors), though
the character and syllable statistics come from the same corpora. Sampling orders
words by SHA-256, so the set changes only when this script or its sources do.
"""

from __future__ import annotations

import argparse
import hashlib
import sys
from pathlib import Path

sys.dont_write_bytecode = True
from generate_model import ASCII_WORD_RE, download, english_floors, korean_words

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = ROOT / "Tests/Accuracy/eval-v1.tsv"
PER_CATEGORY = 1_000
PARTICLES = ["은", "는", "이", "가", "을", "를", "에", "의", "로", "으로", "에서", "도"]


def ordered(words: set[str]) -> list[str]:
    return sorted(words, key=lambda word: hashlib.sha256(word.encode("utf-8")).hexdigest())


def held_out_english(source: bytes) -> list[str]:
    _, known = english_floors(source)
    words: set[str] = set()
    for line in source.decode("utf-8").splitlines():
        try:
            word, level = line.split("\t")
        except ValueError:
            continue
        if level in ("40", "50") and 3 <= len(word) <= 12 and ASCII_WORD_RE.fullmatch(word):
            words.add(word)
    return ordered(words - known)


def held_out_korean(source: bytes) -> list[str]:
    known = korean_words(source)
    words: set[str] = set()
    for line in source.decode("utf-8").splitlines():
        word = line.split("\t")[0]
        if 2 <= len(word) <= 8 and all(0xAC00 <= ord(c) <= 0xD7A3 for c in word):
            words.add(word)
    return ordered(words - known)


def build() -> str:
    english = held_out_english(download("english_words"))
    korean = held_out_korean(download("korean_words"))
    rows = [("english", word) for word in english[:PER_CATEGORY]]
    rows += [("korean", word) for word in korean[:PER_CATEGORY]]
    # Disjoint from the English rows; particles cycle in a fixed order.
    mixed = english[PER_CATEGORY : 2 * PER_CATEGORY]
    rows += [("mixed", word + PARTICLES[index % len(PARTICLES)]) for index, word in enumerate(mixed)]
    header = "# Tavi accuracy set v1: tools/generate_eval.py. category<TAB>expected text\n"
    return header + "".join(f"{category}\t{text}\n" for category, text in rows)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--check", action="store_true")
    arguments = parser.parse_args()

    encoded = build()
    if arguments.check:
        if not arguments.output.exists() or arguments.output.read_text(encoding="utf-8") != encoded:
            print(f"generated set differs from {arguments.output}", file=sys.stderr)
            return 1
    else:
        arguments.output.parent.mkdir(parents=True, exist_ok=True)
        arguments.output.write_text(encoded, encoding="utf-8", newline="\n")

    digest = hashlib.sha256(encoded.encode("utf-8")).hexdigest()
    print(f"rows={encoded.count(chr(10)) - 1} sha256={digest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
