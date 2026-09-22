# BinSchema

[简体中文](README.md) · **English** · [🌐 Online Playground](https://prowk.github.io/binschema/)

> Define safe binary decoding and encoding once with a composable `Codec[T]`, while keeping every byte explainable.

BinSchema is a MoonBit binary protocol codec library focused on safe defaults, composability,
diagnostics, and cross-backend consistency. It includes a native CLI, a Wasm-GC browser
inspector, and real ELF, PNG, WAVE, PCAP, ISO BMFF, and DNS format implementations.

## Highlights

- bounded input/output, collection, nesting, and trace budgets;
- one `Codec[T]` for both decoding and encoding;
- offset/path-aware structured errors and named-field traces;
- inspectable `SchemaNode` metadata plus deterministic schema linting;
- canonical ULEB128/SLEB128 support;
- higher-level `count_prefixed`, `until_eof`, and `tagged` combinators;
- zero-copy `BytesView` APIs including `decode_view`, `bytes_view_fixed`, and `remaining_view`;
- buffered/retry incremental framing with `decode_prefix`, `probe_decode`, and `IncrementalDecoder`;
- deterministic property-style tests and a fixed malformed/valid binary corpus;
- validated Wasm, Wasm-GC, JavaScript, and Native library backends;
- deterministic Schema/Trace-guided mutation regression for truncation, length inflation, checksum damage, and field-boundary flips;
- byte-exact ISO BMFF box parsing with 32-bit size, 64-bit `largesize`, `size=0`, `uuid` user types, and unknown-payload preservation;
- DNS message parsing with bounded section counts, 63-octet labels, byte-exact compressed names, backward-only bounded compression pointers, and depth limits;
- byte-preserving ELF32/ELF64 structural inspection with both byte orders, bounded offset tables, extended section numbering, and section-name resolution.

## Install

```bash
moon add prowk/binschema
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

A minimal codec:

```moonbit
let packet = @bin.pair(
  @bin.magic(b"BS").named("magic"),
  @bin.u16_le().named("sequence"),
)

let schema_text = packet.describe()
let issues = packet.lint()
```

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
