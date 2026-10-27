# Contributing

Use Xcode and Swift 6 or later on macOS 14 or later.

```sh
swift test
bash scripts/build.sh
dist/Tavi.app/Contents/MacOS/Tavi --benchmark
```

Keep runtime dependencies at zero. Do not introduce polling, synchronous network
inference, runtime corpus training, per-key file loads or unbounded caches.
Report model bytes and warm latency when changing the classifier.

Add regression cases to the existing Swift tests. Cover both intended corrections
and valid words that must not change. Never publish private typing samples,
personal dictionaries or full documents in issues or fixtures.

Editor integrations require real composition tests, including the next key
after a correction. A pure core test does not qualify an application as supported.
Preserve per-client composition ownership, shortcut pass-through, and the absence
of accessibility replacement, clipboard or synthetic-backspace fallbacks.

Model changes must document source URLs, immutable revisions, checksums and data
licenses in the model documentation and third-party notices. Generated resources
must be reproducible independently of a contributor's personal dictionary.
