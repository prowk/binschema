# BinSchema

[简体中文](README.md) · **English** · [🌐 Online Playground](https://prowk.github.io/binschema/)

> Define safe binary decoding and encoding once with a composable `Codec[T]`, while keeping every byte explainable.

BinSchema is a MoonBit binary protocol codec library focused on safe defaults, composability,
diagnostics, and cross-backend consistency. It includes a native CLI, a Wasm-GC browser
inspector, and real PNG, WAVE, and PCAP format implementations.

## Highlights

- bounded input/output, collection, nesting, and trace budgets;
- one `Codec[T]` for both decoding and encoding;
- offset/path-aware structured errors and named-field traces;
- inspectable `SchemaNode` metadata plus deterministic schema linting;
- canonical ULEB128/SLEB128 support;
- higher-level `count_prefixed`, `until_eof`, and `tagged` combinators;
- zero-copy `BytesView` APIs including `decode_view`, `bytes_view_fixed`, and `remaining_view`;
- deterministic property-style tests and a fixed malformed/valid binary corpus;
- validated Wasm, Wasm-GC, JavaScript, and Native library backends.

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

A minimal codec:

```moonbit
let packet = @bin.pair(
  @bin.magic(b"BS").named("magic"),
  @bin.u16_le().named("sequence"),
)

let schema_text = packet.describe()
let issues = packet.lint()
```

The native CLI also supports `binschema lint <png|wav|pcap> [--json]`; lint errors can be used as a CI quality gate while warnings remain advisory.\n\nFor a realistic end-to-end example, see [`examples/demo_protocol`](examples/demo_protocol). It combines a magic header, version validation, a count-prefixed message list, tagged message branches, length-prefixed payloads, named traces, and a packet checksum in one codec tree.

See the canonical executable documentation in [README.mbt.md](README.mbt.md), architecture notes
in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), security guidance in
[docs/SECURITY.md](docs/SECURITY.md), compatibility policy in
[docs/COMPATIBILITY.md](docs/COMPATIBILITY.md), and the release checklist in
[docs/RELEASING.md](docs/RELEASING.md).

## Browser inspector

**Try it online:** [https://prowk.github.io/binschema/](https://prowk.github.io/binschema/)

No MoonBit installation is required. Pick a PNG, WAVE, or PCAP file in the browser; the file is processed locally and is not uploaded.

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
