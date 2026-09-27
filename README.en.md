<div align="center">

<h1>BinSchema</h1>
<p><strong>Safe, composable, and explainable binary protocol tooling for MoonBit</strong></p>
<p>
  <a href="https://github.com/prowk/binschema/releases/latest"><img alt="Release" src="https://img.shields.io/github/v/release/prowk/binschema?display_name=tag&amp;sort=semver&amp;style=flat-square"></a>
  <a href="https://github.com/prowk/binschema/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/prowk/binschema/actions/workflows/ci.yml/badge.svg?branch=main"></a>
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/github/license/prowk/binschema?style=flat-square"></a>
</p>
<p><a href="https://prowk.github.io/binschema/">Online Playground</a> · <a href="https://mooncakes.io/docs/prowk/binschema@0.3.0">Mooncakes documentation</a> · <a href="README.md">简体中文</a> · <strong>English</strong></p>

</div>

[![BinSchema Playground — browser-local binary protocol inspection](https://raw.githubusercontent.com/prowk/binschema/main/.github/assets/playground-preview.png)](https://prowk.github.io/binschema/)

BinSchema defines safe binary decoding and encoding once with a composable `Codec[T]`, while keeping every byte explainable. It combines resource limits, structured errors, field traces, schema metadata, and round-trip verification in one API, backed by a native CLI, a Wasm-GC browser inspector, and real ELF, PNG, WAVE, PCAP, ISO BMFF, and DNS implementations.

| Safety boundaries | Observability | Engineering confidence |
| --- | --- | --- |
| Bounded input, output, collections, and nesting | Stable errors with offsets and field paths | One suite across Wasm, Wasm-GC, JavaScript, and Native |
| Strict EOF, canonical integers, and structural validation | Trace and Schema metadata drive the inspector | Documentation, corpus, mutation, and coverage gates |

## Install

```bash
moon add prowk/binschema@0.3.0
```

Import it from your package:

```text
import {
  "prowk/binschema" @bin,
}
```

Built-in real-format codecs live in a separate package and are imported only when needed:

```text
import {
  "prowk/binschema/formats" @formats,
}
```

## Quick start

A minimal codec:

```moonbit
let packet = @bin.pair(
  @bin.magic(b"BS").named("magic"),
  @bin.u16_le().named("sequence"),
)

let schema_text = packet.describe()
let issues = packet.lint()
```

## Core capabilities

- bounded input/output, collection, nesting, and trace budgets;
- one `Codec[T]` for both decoding and encoding;
- offset/path-aware structured errors and named-field traces;
- inspectable `SchemaNode` metadata plus deterministic schema linting;
- canonical ULEB128/SLEB128 support;
- higher-level `count_prefixed`, `until_eof`, and `tagged` combinators;
- zero-copy `BytesView` APIs including `decode_view`, `bytes_view_fixed`, and `remaining_view`;
- buffered/retry incremental framing with `decode_prefix`, `probe_decode`, and `IncrementalDecoder`;
- deterministic property-style, corpus, and Schema/Trace-guided mutation regression;
- byte-exact ISO BMFF, bounded DNS compression, and byte-preserving ELF32/ELF64 structural inspection.

The native CLI also supports `binschema lint <png|wav|pcap|bmff|dns|elf> [--json]`; lint errors can be used as a CI quality gate while warnings remain advisory. The linter checks declared `SchemaNode` metadata; it does not analyze arbitrary `Codec::make` closures or prove that a custom closure matches its declared schema.

For fragmented network or stream input, `probe_decode` distinguishes `NeedMore` from real decode failures, while `IncrementalDecoder` retains unconsumed trailing bytes for the next frame. The generic incremental decoder retries the codec from the start of the buffered frame on each `poll()`; it is not a continuation-based streaming parser. For many tiny chunks, batch them with `append()` before polling. Protocols using `until_eof` or `remaining_*` should first establish an explicit bounded region.

For a realistic end-to-end example, see [`examples/demo_protocol`](examples/demo_protocol). It combines a magic header, version validation, a count-prefixed message list, tagged message branches, length-prefixed payloads, named traces, and a packet checksum in one codec tree.

See the canonical executable documentation in [README.mbt.md](README.mbt.md), architecture notes
in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), security guidance in
[docs/SECURITY.md](docs/SECURITY.md), compatibility policy in
[docs/COMPATIBILITY.md](docs/COMPATIBILITY.md), and the release checklist in
[docs/RELEASING.md](docs/RELEASING.md).

## Real-format support scope

The `formats` package is primarily a set of reference implementations and architecture stress cases, not six complete domain libraries.

- PNG validates signatures, chunk structure/order, CRCs, and core IHDR rules.
- WAVE validates RIFF sizing, chunk/padding structure, and basic `fmt ` / `data` consistency.
- PCAP validates global headers, byte order, packet lengths, timestamp ranges, and snapshot bounds.
- ISO BMFF validates box framing, 32/64-bit sizes, `size=0`, `uuid`, and preserves unknown payloads.
- DNS validates message framing and bounded compression pointers; RDATA remains raw bytes.
- ELF validates ELF32/ELF64 headers, byte order, table bounds, extended section numbering, and section names; symbols, relocations, DWARF, and dynamic-linking semantics are out of scope.

CLI `verify` therefore means that the input satisfies BinSchema's currently implemented structural rules and round-trips byte-for-byte. It is **not** a complete standards-conformance certification.

## Browser inspector

**Try it online:** [https://prowk.github.io/binschema/](https://prowk.github.io/binschema/)

No MoonBit installation is required. Pick an ELF, PNG, WAVE, PCAP, common MP4 / ISO BMFF, or DNS file in the browser; the file is processed locally and is not uploaded. DNS has no reliable fixed magic, so DNS inspection is selected explicitly rather than auto-detected.

For local development, the Wasm binary is generated from source and is not committed to the repository.

Build locally:

```bash
moon build --target wasm-gc web/bridge --release
cp _build/wasm-gc/release/build/web/bridge/bridge.wasm web/binschema.wasm
python -m http.server 4173 --directory web
```

The browser processes files locally and does not upload them.

## License

Apache-2.0.
