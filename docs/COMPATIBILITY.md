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
