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
