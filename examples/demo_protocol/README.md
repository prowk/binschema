# Demo Protocol

This example shows how BinSchema can describe a small but realistic binary protocol with one codec tree.

Layout:

```text
magic "BS"
version u8 (= 1)
flags u8
message_count u8
messages[message_count]:
  tag u8
  tag=1 -> Counter(u32_le)
  tag=2 -> Sensor(sensor_id u16_le, reading u16_le)
  tag=3 -> Blob(length u16_le, payload bytes)
checksum u8   # additive checksum of every preceding byte
```

The example demonstrates:

- `magic` and semantic validation;
- `count_prefixed` collections;
- `tagged` dynamic message branches;
- `length_prefixed` variable payloads;
- named byte-range traces;
- `checksum_suffix_view` corruption detection;
- one codec used for both encoding and decoding.

Run it with:

```bash
moon run --target native examples/demo_protocol
```

The printed trace maps protocol fields back to their byte ranges, which is the same information model used by BinSchema's browser inspector.
