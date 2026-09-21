///|
/// Fixed regression corpus: accepted encodings must remain accepted and malformed
/// encodings must keep failing with structured errors.
test "corpus: canonical integer and varint encodings" {
  let u16_cases = [
    (b"\x00\x00", 0U),
    (b"\x00\x01", 1U),
    (b"\x12\x34", 0x1234U),
    (b"\xff\xff", 0xffffU),
  ]
  for (bytes, expected) in u16_cases {
    match @binschema.decode(@binschema.u16_be(), bytes) {
      Err(error) => fail(error.render())
      Ok(decoded) => assert_eq(decoded.value, expected)
    }
  }

  let uleb_cases = [
    (b"\x00", 0UL),
    (b"\x7f", 127UL),
    (b"\x80\x01", 128UL),
    (b"\xe5\x8e\x26", 624485UL),
  ]
  for (bytes, expected) in uleb_cases {
    match @binschema.decode(@binschema.uleb128(), bytes) {
      Err(error) => fail(error.render())
      Ok(decoded) => assert_eq(decoded.value, expected)
    }
  }
}

///|
test "corpus: malformed lengths tags and varints stay rejected" {
  let counted = @binschema.count_prefixed(
    @binschema.u8(),
    @binschema.u16_be(),
    max_count=4,
  )
  assert_true(
    @binschema.decode(counted, b"\x05\x00\x01\x00\x02\x00\x03\x00\x04\x00\x05")
    is Err({ kind: @binschema.LimitExceeded, .. }),
  )

  let tagged_codec = @binschema.tagged(
    @binschema.u8(),
    fn(tag) { if tag == 1U { Ok(@binschema.u8()) } else { Err("unknown tag") } },
    fn(_) { Ok(1U) },
    render=fn(value) { value.to_string() },
  )
  assert_true(
    @binschema.decode(tagged_codec, b"\x02\x00")
    is Err({ kind: @binschema.InvalidValue, .. }),
  )

  let malformed_uleb = [
    b"\x80", b"\x80\x00", b"\xff\xff\xff\xff\xff\xff\xff\xff\xff\x02",
  ]
  for bytes in malformed_uleb {
    assert_true(@binschema.decode(@binschema.uleb128(), bytes) is Err(_))
  }
}

///|
test "corpus: until-eof rejects zero-progress element codecs" {
  let empty = @binschema.Codec::make(
    fn(_) { Ok(()) },
    fn(_, _) { Ok(()) },
    kind="empty",
    render=fn(_) { "()" },
  )
  assert_true(
    @binschema.decode(@binschema.until_eof(empty), b"\x00")
    is Err({ kind: @binschema.InvalidValue, .. }),
  )
}
