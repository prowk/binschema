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
