# Compatibility policy

BinSchema follows Semantic Versioning for published MoonBit module releases.

## Public API

The generated `pkg.generated.mbti` files are the reviewable public API snapshot. CI runs
`moon info` and fails when generated interfaces differ from the committed snapshots.

Before 1.0, minor releases may contain intentional API changes, but they must be:

- listed in `CHANGELOG.md`;
- accompanied by a migration note when downstream source changes are required;
- reflected in the generated `.mbti` snapshots;
- covered by tests on every declared backend.

Patch releases should remain source-compatible and focus on fixes, diagnostics, documentation,
and performance changes that do not alter documented semantics.

## 0.3.0 migration notes

0.3.0 is a pre-1.0 minor release with intentional public-surface growth.

- `Codec[T]` now carries a `schema : SchemaNode` field. Downstream code should prefer
  `Codec::make` and combinators instead of constructing `Codec` values with struct literals.
- `Inspection` now contains `schema : SchemaNode`. Downstream code that manually constructs
  inspection reports must provide this field.
- The public `Format` enum gained `Bmff`, `Dns`, and `Elf`. Exhaustive downstream matches
  over `Format` need corresponding branches.
- New Decoder random-access APIs, incremental decoding APIs, Schema/Linter APIs, and the new
  format types are additive. `IncrementalDecoder::append` is also additive and lets callers
  batch tiny chunks before a retrying `poll()`.
- Fixed-width unsigned encoders now reject values that do not fit their wire width instead of
  silently truncating high bits.
- Byte-framed bit codecs now treat a partially used final byte as consumed only when its unread
  low bits are zero, matching encoder zero padding. Non-zero final padding bits are rejected.
- PNG and WAVE encoders now reject inconsistent public metadata instead of silently recomputing
  and ignoring conflicting values.

Existing canonical byte sequences produced by valid v0.2.0 core values are not intentionally
changed by this release; the tightened cases above concern previously ambiguous or invalid inputs.

## Backend support

The library module declares support for Wasm, Wasm-GC, JavaScript, and Native. Package-level
metadata narrows backend-specific deliverables:

- the core library and `formats` package support all four declared backends;
- `cmd/main` and `examples/custom_packet` are Native-only;
- `web/bridge` is Wasm-GC-only.

Changing the declared backend set is a compatibility change and must be documented in the
changelog.

## Binary behavior

For existing codecs, canonical encodings and accepted/rejected malformed inputs are treated as
observable behavior. Property-style roundtrip tests and the checked regression corpus protect
these contracts.

A release that intentionally changes canonical encoding or validation rules must call that out
explicitly in the changelog.
