///|
test "hex rendering is stable and byte-oriented" {
  assert_eq(bytes_to_hex(b"\x00\x0f\xff"), "00 0f ff")
}

///|
test "byte alignment is enforced after partial bit reads" {
  let decoder = Decoder::new(b"\xff\x01", Limits::default())
  assert_eq(decoder.read_bits_msb(3), Ok(7U))
  match decoder.take_bytes(1) {
    Ok(_) => fail("misaligned byte read must fail")
    Err(error) => assert_eq(error.kind, Misaligned)
  }
  decoder.align_byte()
  assert_eq(decoder.take_bytes(1), Ok(b"\x01"))
}

///|
test "hex previews are bounded and report omitted bytes" {
  assert_eq(
    bytes_to_hex_preview(b"\x00\x01\x02\x03", 2),
    "00 01 … (+2 bytes)",
  )
  assert_eq(bytes_to_hex_preview(b"\x00\x01", 8), "00 01")
  assert_eq(bytes_to_hex_preview(b"\x00", -1), " … (+1 bytes)")
}

///|
test "error rendering covers rooted and named locations" {
  assert_eq(
    BinError::new(Unsupported, 4, "", "no format").render(),
    "Unsupported (offset 4): no format",
  )
  assert_eq(
    BinError::new(UnexpectedEof, 2, "header.id", "short").render(),
    "UnexpectedEof (header.id at offset 2): short",
  )
}

///|
test "named codecs preserve field paths during encoding" {
  let codec = bytes_fixed(2).named("payload")
  match encode(codec, b"x") {
    Ok(_) => fail("invalid fixed-length payload must fail")
    Err(error) => {
      assert_eq(error.kind, InvalidValue)
      assert_eq(error.path, "payload")
    }
  }
}

///|
test "repeat trace previews do not contain terminal control sequences" {
  let codec = repeat(1, u8()).named("items")
  match decode(codec, b"\x01") {
    Err(error) => fail(error.render())
    Ok(decoded) => {
      assert_eq(decoded.trace.length(), 2)
      for entry in decoded.trace {
        assert_true(!entry.value.contains("\u001b"))
      }
    }
  }
}

///|
test "byte fields are not constrained by collection item limits" {
  let limits = Limits::{
    max_input_bytes: 16,
    max_collection_length: 1,
    max_depth: 8,
    max_output_bytes: 16,
  }
  let options = DecodeOptions::{ limits, require_eof: true, }
  match decode_with_options(bytes_fixed(4), b"abcd", options) {
    Err(error) => fail(error.render())
    Ok(decoded) => assert_eq(decoded.value, b"abcd")
  }
}
