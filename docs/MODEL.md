# Local EN/KO statistical model

Tavi makes each decision locally with one immutable precomputed table. It does
not train at runtime, call a network service, load a neural runtime, or ask
`NSSpellChecker`. `StatisticalModel.shared` decodes the resource once for the
process; each `CompositionEngine` only holds its current bounded token and
personal-word view.

## Shipped data

`Sources/TaviCore/Resources/model-v2.dat.base64` is a base64 representation of
a 176,422-byte binary table (238,328 bytes as bundled text):

- 19,683 `UInt16` English character-trigram counts. The counts contain
  3,258,521 observations in 7,277 nonzero cells, generated from the explicit
  CC0 English sentence export from Tatoeba.
- 11,172 `UInt16` Korean syllable slots. 1,273 syllables have corpus counts
  derived from Tatoeba Korean sentences.
- A 32 KiB Bloom filter for 11,115 common English words and a 64 KiB Bloom
  filter for 41,941 known English words. The tiers come from SCOWL levels
  10/20 and 35, respectively.
- A 16 KiB Bloom filter for 6,656 Korean words occurring at least twice in the
  pinned Korean corpus table.

The complete resource is well below the 2 MiB release ceiling. Bloom filters
are score floors, not the sole classifier: ordinary unseen input still uses
the character/syllable probabilities. Their expected false-positive rates at
the shipped counts are about 0.06% (common English), 0.56% (known English),
and 0.11% (known Korean).

## Generation

Run:

```sh
python3 tools/generate_model.py --check
```

Without `--check`, the same tool rewrites the resource. Every input URL and
SHA-256 is declared in the script. A checksum mismatch is a hard failure, so a
rolling upstream export cannot silently change release bytes. The current
English CC0 export snapshot was retrieved on October 27, 2026. The SCOWL and
Korean derived tables are pinned through Araso commit
`7eddf6a175cd6c9acef6e03f0b1ca32b4b62fca3`.

The generator emits deterministic little-endian `TVM2` data:

1. trigram item count and capped `UInt16` counts;
2. Korean syllable item count and capped `UInt16` counts;
3. bit count plus bytes for each of the three four-probe FNV-1a Bloom filters.

The shipped base64 file has SHA-256
`2ef3148373a1e975d04a235cd2be1305e56486d532da3c8268e07acbe4028bda`.

## Decision mechanism

The engine always scores the literal Latin keys and the Dubeolsik composition.
English uses smoothed character-trigram log probability with SCOWL common and
known-word floors. Korean uses smoothed syllable log probability with a
corpus-word floor and explicit penalties for loose jamo. The previous committed
token contributes only a small language prior, so it can resolve close cases
without overruling a strong known-word result.

Segmentation is intentionally narrow and bounded to a maximum 64-key token:

- plausible English/acronym plus a Korean particle (`APIfmf` -> `API를`,
  `apifh` -> `api로`), preferring the longest recognized suffix;
- known English/acronym plus a Korean corpus word (`PDFvkdlf` -> `PDF파일`);
- known Korean corpus word plus known English or a confirmed personal spelling
  (`dkssud3xhaust` -> `안녕3Xhaust` after learning `3Xhaust`).

There is no generic beam search. URLs, paths, email-like strings, identifiers,
digits, acronyms, and camel-case code receive a literal floor. Whole valid
English remains literal. Ambiguous words remain fallible and are corrected via
candidate cycling, explicit input-source choice, or learned words.

## Confidence and learning

Each `Candidate` has a numeric `confidence`; `CompositionEngine.confidence`
copies the selected candidate's value. `automaticEligible` is true only when
the automatic result differs from the raw keys and confidence is at least
0.80. Host code must still perform all focus, selection, expected-text, and
composition-state mutation checks.

`sourceChanged(to:)` is an explicit user request. It chooses the full Korean or
Latin reading with confidence 1 and bypasses the inference threshold, but does
not bypass host mutation checks.

Personal words become automatic after three confirmations. One or two
observations do not affect candidate ranking or confidence. Confirmations keep
counting (up to 999); the learned score is `40 + min(log2(count), 8)`, so a
long-used spelling outranks newer learned rules. A contrary choice halves an
established count and replaces the spelling once it would fall below three.

When lowercase keys (or only `Q/W/E/R/T/O/P` shifts) read as complete Hangul
syllables, an English fragment inside them is treated as coincidence: splits
such as `ah을` or `ehoT나` rank below the whole Korean reading (`모을`, `됐나`)
and the switch key toggles between the whole Korean reading and the literal keys. Once a word displays as Korean, a weaker
mid-word Latin preference does not flip it back (no `안 → 아ss → 안녀`). Raw keys are matched
exactly so shifted Dubeolsik keys such as `Q/W/E/R/T/O/P` retain their distinct
jamo. Case-insensitive raw matching is allowed only when the raw form and the
learned output are both ASCII-letter spellings. Tavi never guesses a new output
casing.

`previousToken` is public so a host with validated local context can seed the
small context prior. A successful commit also updates it automatically.

## Tests and measurement

`CompositionTests`, `HangulTests`, and `ModelTests` cover unseen ordinary
English and Korean, mixed particles and words, explicit ambiguity, learned
nicknames and exact raw identity, punctuation/URLs/code, Dubeolsik clusters,
backspace recomposition, statistical separation, and the resource ceiling.

Latency is measured separately through the app's `--benchmark` entry point so
timing noise is not turned into a nondeterministic correctness test.

The October 27, 2026 release-build run on the development Apple M5 measured
10,000 warm core decisions and commits:

| Metric | Result |
| --- | ---: |
| p50 | 0.008583 ms |
| p95 | 0.020625 ms |
| p99 | 0.040083 ms |
| maximum | 0.417041 ms |

This passes the warm-decision p95 target of 1 ms. It is not a measurement of
cross-process Accessibility replacement latency. See
[verification](VERIFICATION.md) for stress, CPU, memory, and host-testing limits.
