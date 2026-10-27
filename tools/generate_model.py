#!/usr/bin/env python3
"""Rebuild Tavi's compact immutable statistical model.

The source archives are checksum locked. If an upstream rolling export changes,
the script stops instead of silently producing different shipped bytes.
"""

from __future__ import annotations

import argparse
import base64
import bz2
import hashlib
import re
import struct
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = ROOT / "Sources/TaviCore/Resources/model-v2.dat.base64"
ARASO_COMMIT = "7eddf6a175cd6c9acef6e03f0b1ca32b4b62fca3"
ARASO_DATA = (
    f"https://raw.githubusercontent.com/nyttastudio/araso/{ARASO_COMMIT}"
    "/Sources/ArasoCore/Data/"
)

SOURCES = {
    "english_corpus": (
        "https://downloads.tatoeba.org/exports/per_language/eng/"
        "eng_sentences_CC0.tsv.bz2",
        "a144a0c52f8be13bee7cc30eb109eb5836803f22128a8ef8376c1ca5c6c5cf8a",
    ),
    "english_words": (
        ARASO_DATA + "english_words.txt",
        "73cded4c79da7817c65bc845859862671aa0c9f17f55440a0cfac5bbfbc44c40",
    ),
    "korean_syllables": (
        ARASO_DATA + "korean_syllables.txt",
        "33010d8adf17703c9ff22ac6e2373fc2efded588141b2775ce48946d725e3e9e",
    ),
    "korean_words": (
        ARASO_DATA + "korean_words.txt",
        "558d273fe48103f31acdc5342c4fe22244e8ef0f4a1c706be3e7f8ce802ec6ef",
    ),
}

WORD_RE = re.compile(r"[A-Za-z]+(?:'[A-Za-z]+)?")
ASCII_WORD_RE = re.compile(r"[a-z]+")
SYMBOLS = 27
TRIGRAM_ITEMS = SYMBOLS**3
HANGUL_ITEMS = 11_172


def download(name: str) -> bytes:
    url, expected = SOURCES[name]
    request = urllib.request.Request(url, headers={"User-Agent": "Tavi model generator"})
    with urllib.request.urlopen(request, timeout=60) as response:
        data = response.read()
    actual = hashlib.sha256(data).hexdigest()
    if actual != expected:
        raise RuntimeError(
            f"{name} checksum changed: expected {expected}, received {actual}"
        )
    return data


def english_trigrams(corpus: bytes) -> list[int]:
    counts = [0] * TRIGRAM_ITEMS
    for line in bz2.decompress(corpus).decode("utf-8").splitlines():
        fields = line.split("\t")
        text = fields[2] if len(fields) >= 3 else fields[-1]
        for token in WORD_RE.findall(text):
            word = token.lower().replace("'", "")
            codes = [0, 0, *(ord(character) - 96 for character in word), 0]
            for index in range(2, len(codes)):
                position = (
                    (codes[index - 2] * SYMBOLS + codes[index - 1]) * SYMBOLS
                    + codes[index]
                )
                counts[position] += 1
    return counts


def english_floors(source: bytes) -> tuple[set[str], set[str]]:
    common: set[str] = set()
    known: set[str] = set()
    for line in source.decode("utf-8").splitlines():
        try:
            raw_word, raw_level = line.split("\t")
            level = int(raw_level)
        except ValueError:
            continue
        word = raw_word.lower().replace("'", "")
        if level > 35 or len(word) > 40 or not ASCII_WORD_RE.fullmatch(word):
            continue
        known.add(word)
        if level <= 20:
            common.add(word)
    return common, known


def korean_counts(source: bytes) -> list[int]:
    counts = [0] * HANGUL_ITEMS
    for line in source.decode("utf-8").splitlines():
        try:
            syllable, raw_count = line.split("\t")
            count = int(raw_count)
        except ValueError:
            continue
        if len(syllable) == 1 and 0xAC00 <= ord(syllable) <= 0xD7A3:
            counts[ord(syllable) - 0xAC00] = min(count, 65_535)
    return counts


def korean_words(source: bytes) -> set[str]:
    words: set[str] = set()
    for line in source.decode("utf-8").splitlines():
        try:
            word, raw_count = line.split("\t")
            count = int(raw_count)
        except ValueError:
            continue
        if count >= 2 and len(word) <= 16:
            words.add(word)
        if len(words) >= 12_000:
            break
    return words


def fnv1a(value: bytes, seed: int) -> int:
    result = seed
    for byte in value:
        result = ((result ^ byte) * 16_777_619) & 0xFFFF_FFFF
    return result


def bloom(words: set[str], bit_count: int) -> bytes:
    result = bytearray(bit_count // 8)
    for word in words:
        encoded = word.encode("utf-8")
        first = fnv1a(encoded, 2_166_136_261)
        step = fnv1a(encoded, 16_777_619) | 1
        for round_index in range(4):
            position = (first + round_index * step) % bit_count
            result[position >> 3] |= 1 << (position & 7)
    return bytes(result)


def build() -> tuple[bytes, dict[str, int]]:
    corpus = download("english_corpus")
    word_source = download("english_words")
    syllable_source = download("korean_syllables")
    korean_word_source = download("korean_words")

    trigrams = english_trigrams(corpus)
    common, known = english_floors(word_source)
    syllables = korean_counts(syllable_source)
    korean = korean_words(korean_word_source)

    common_filter = bloom(common, 1 << 18)
    known_filter = bloom(known, 1 << 19)
    korean_filter = bloom(korean, 1 << 17)

    output = bytearray(b"TVM2")
    output += struct.pack("<I", len(trigrams))
    output += struct.pack(f"<{len(trigrams)}H", *(min(value, 65_535) for value in trigrams))
    output += struct.pack("<I", len(syllables))
    output += struct.pack(f"<{len(syllables)}H", *syllables)
    for bit_count, data in (
        (1 << 18, common_filter),
        (1 << 19, known_filter),
        (1 << 17, korean_filter),
    ):
        output += struct.pack("<I", bit_count)
        output += data

    return bytes(output), {
        "binary_bytes": len(output),
        "english_common": len(common),
        "english_known": len(known),
        "korean_known": len(korean),
        "trigram_mass": sum(trigrams),
        "nonzero_trigrams": sum(bool(value) for value in trigrams),
    }


def encoded_model(binary: bytes) -> str:
    encoded = base64.b64encode(binary).decode("ascii")
    return "\n".join(encoded[index : index + 76] for index in range(0, len(encoded), 76)) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--check", action="store_true")
    arguments = parser.parse_args()

    binary, metrics = build()
    encoded = encoded_model(binary)
    if arguments.check:
        if not arguments.output.exists() or arguments.output.read_text(encoding="ascii") != encoded:
            print(f"generated model differs from {arguments.output}", file=sys.stderr)
            return 1
    else:
        arguments.output.parent.mkdir(parents=True, exist_ok=True)
        arguments.output.write_text(encoded, encoding="ascii", newline="\n")

    digest = hashlib.sha256(encoded.encode("ascii")).hexdigest()
    print(" ".join(f"{key}={value}" for key, value in metrics.items()))
    print(f"base64_bytes={len(encoded.encode('ascii'))} sha256={digest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
