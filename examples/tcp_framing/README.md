# BinSchema TCP Framing Example

This module is an executable integration example, not a networking API in the
BinSchema core package. It shows how one codec can be used at a real TCP
boundary where reads may split or combine application frames.

## Wire format

```text
frame_length u32_be (maximum 64 KiB)
  magic "BS"
  version u8 (= 1)
  message_type u8
  request_id u32_be
  payload_length u16_be (maximum 4 KiB)
  payload bytes
  checksum u8
```

The server uses `IncrementalDecoder` to retain partial input and decode every
complete frame from a coalesced read. Each connection has one socket reader and
one business processor connected by `Queue(Blocking(2))`. When the processor
falls behind, the full queue suspends the reader instead of allowing unbounded
memory growth.

The connection policy is explicit:

- a declared frame larger than 64 KiB is rejected after its four-byte length;
- a payload larger than 4 KiB is rejected;
- an incomplete connection is closed after the idle timeout;
- checksum and schema failures report their BinSchema byte offset and, when
  available, field path;
- structured concurrency cancels the sibling task and closes the connection on
  failure.

## One-command demo

From the repository root:

```bash
moon update
moon run --target native examples/tcp_framing/app -- demo
```

The command starts a server on a loopback ephemeral port, runs normal,
fragmented, coalesced, corrupted, oversized, and idle-partial clients, then
exits. The coalesced case deliberately slows business processing so the output
contains `backpressure queue full`.

## Separate server and client

Run these in two terminals. The server listens only on `127.0.0.1:42042`.

```bash
moon run --target native examples/tcp_framing/app -- server
```

```bash
moon run --target native examples/tcp_framing/app -- client fragmented
moon run --target native examples/tcp_framing/app -- client coalesced
moon run --target native examples/tcp_framing/app -- client corrupt
```

Available client scenarios are `normal`, `fragmented`, `coalesced`, `corrupt`,
`oversized`, and `timeout`.

## Tests

```bash
moon test --target native examples/tcp_framing/protocol --deny-warn
moon test --target native examples/tcp_framing/app --deny-warn
```

The pure protocol tests cover round trips, Trace generation, corruption,
oversized declarations, fragmentation, and coalescing. The async loopback test
also verifies backpressure, connection timeout, failure reporting, and cleanup.

`moonbitlang/async` is currently experimental, so this example is isolated in
its own workspace module and pinned to `0.22.3`. The BinSchema library module
does not acquire an async dependency or a new public API.
