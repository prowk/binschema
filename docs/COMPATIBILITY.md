# Compatibility policy

BinSchema follows Semantic Versioning for published MoonBit module releases.

## Toolchain support

BinSchema requires `moonc >= 0.10.20`. CI installs the latest official release, records
`moon version --all`, and checks, builds and tests the supported targets on Ubuntu and Windows
on push, PR, weekly schedule and manual runs. The Ubuntu job rejects older compilers.
Raising the minimum supported compiler version is a compatibility change and
must be documented in the changelog and README.

## 2026-11-12 compatibility audit

```text
moon 0.1.20261104 (940aa18 2026-11-04)
moonc v0.10.20+65efd5b93 (2026-11-05)
moonrun 0.1.20261104 (940aa18 2026-11-04)
Feature flags enabled: rr_moon_mod,rr_moon_pkg
```

- Installed from the [official download instructions](https://www.moonbitlang.com/download/) using the Windows PowerShell installer with `MOONBIT_INSTALL_VERSION=latest`.
- Local environment: Windows x86-64, MSVC 2022 (14.41), Windows SDK 10.0.22621.0; Node.js 22.14.0 for JS tests and temporary Node.js 24.22.3 for actual Wasm-GC export validation.
- Retained compatible pins: `moonbitlang/x@0.5.5`, isolated `moonbitlang/async@0.22.3`. No dependency API or manifest migration was needed.
- `moon fmt` migrated trailing `derive(...)` to `#derive(...)`, integer aliases to explicit `Int32`/`UInt32`, and optional parameter declarations to the current syntax. Generated `.mbti` changes reflect these spellings, derived traits and qualified JSON types; codec behavior and wire encodings are unchanged.
- `moon check --target all --deny-warn` and `moon build --target all --release --deny-warn` passed. Tests passed: Wasm 109, Wasm-GC 114, JS 109, Native 123; executable README 2.
- Native custom packet output matched `42 53 01 e5 8e 26 07 00`; demo protocol reported 3 messages, 24 bytes and 23 trace fields; TCP completed all six scenarios.
- Six-format CLI file workflows and the actual Wasm-GC artifact are checked by `scripts/compatibility-smoke.py` and `web/check-wasm.mjs` (Node.js 24).
- Native benchmark compilation, 512-iteration mutation smoke, API docs and publish package audit passed. Clean Native coverage: core 1018/1221, formats 1823/2126. Use `moon coverage report` after instrumented tests to consume their results without rerunning tests. Old pre-upgrade trace metadata required `moon clean`; `moon coverage clean` alone did not remove it.
- `async@0.22.3` emits an upstream MSVC C4005 `EINVAL` redefinition warning; it does not block compilation, `--deny-warn` MoonBit checks, or TCP execution.
- Linux system reference/resource scripts remain Ubuntu CI gates and were not executed in this Windows audit. macOS is not covered by this local verification. The web bridge requires Wasm-GC plus JS string builtins/imported string constants; Node.js 22.14.0 could not instantiate it, while Node.js 24.22.3 passed.

## Public API

The generated `pkg.generated.mbti` files are the reviewable public API snapshot. CI runs
`moon info --target all` followed by `python scripts/sync-interfaces.py` and fails when
generated interfaces differ from the committed snapshots. The helper copies the actual backend
interfaces for packages whose sole supported target differs from the module preferred target;
current `moon info` only writes canonical preferred-target snapshots.

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
- `cmd/main`, `examples/custom_packet`, `examples/demo_protocol`, and the isolated TCP example module are Native-only;
- `web/bridge` is Wasm-GC-only.

Changing the declared backend set is a compatibility change and must be documented in the
changelog.

## Binary behavior

For existing codecs, canonical encodings and accepted/rejected malformed inputs are treated as
observable behavior. Property-style roundtrip tests and the checked regression corpus protect
these contracts.

A release that intentionally changes canonical encoding or validation rules must call that out
explicitly in the changelog.
