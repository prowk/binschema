# BinSchema

[简体中文](README.md) · **English**

> Define safe binary decoding and encoding once with a composable `Codec[T]`, while keeping every byte explainable.

BinSchema is a MoonBit binary protocol codec library focused on safe defaults, composability,
diagnostics, and cross-backend consistency. It includes a native CLI, a Wasm-GC browser
inspector, and real PNG, WAVE, and PCAP format implementations.

## Highlights

- bounded input/output, collection, nesting, and trace budgets;
- one `Codec[T]` for both decoding and encoding;
- offset/path-aware structured errors and named-field traces;
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
```

See the canonical executable documentation in [README.mbt.md](README.mbt.md), architecture notes
in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), security guidance in
[docs/SECURITY.md](docs/SECURITY.md), compatibility policy in
[docs/COMPATIBILITY.md](docs/COMPATIBILITY.md), and the release checklist in
[docs/RELEASING.md](docs/RELEASING.md).

## Browser inspector

Build locally:

```bash
moon build --target wasm-gc web/bridge --release
cp _build/wasm-gc/release/build/web/bridge/bridge.wasm web/binschema.wasm
python -m http.server 4173 --directory web
```

The browser processes files locally and does not upload them.

## License

Apache-2.0.
