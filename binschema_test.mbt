///|
test "unsigned integer codecs round-trip in both byte orders" {
  let be = @binschema.u32_be().named("header.length")
  let le = @binschema.u32_le().named("header.length")
  let value = 0x12345678U
  assert_eq(@binschema.encode(be, value), Ok(b"\x12\x34\x56\x78"))
  assert_eq(@binschema.encode(le, value), Ok(b"\x78\x56\x34\x12"))
  match @binschema.decode(be, b"\x12\x34\x56\x78") {
    Err(error) => fail("unexpected error: \{error.render()}")
    Ok(decoded) => {
      assert_eq(decoded.value, value)
      assert_eq(decoded.consumed, 4)
      assert_eq(decoded.trace.length(), 1)
      assert_eq(decoded.trace[0].path, "header.length")
      assert_eq(decoded.trace[0].start, 0)
      assert_eq(decoded.trace[0].end, 4)
    }
  }
}

///|
test "signed codecs preserve two's-complement values" {
  assert_eq(@binschema.encode(@binschema.i16_le(), -2), Ok(b"\xfe\xff"))
  match @binschema.decode(@binschema.i16_le(), b"\xfe\xff") {
    Ok(decoded) => assert_eq(decoded.value, -2)
    Err(error) => fail("unexpected error: \{error.render()}")
  }
  let value = -9_223_372_036_854_775_000L
  match @binschema.encode(@binschema.i64_be(), value) {
    Err(error) => fail("unexpected error: \{error.render()}")
    Ok(bytes) =>
      match @binschema.decode(@binschema.i64_be(), bytes) {
        Ok(decoded) => assert_eq(decoded.value, value)
        Err(error) => fail("unexpected error: \{error.render()}")
      }
  }
}

///|
test "bit fields share bytes and align deterministically" {
  let layout = @binschema.pair(@binschema.bits_msb(3), @binschema.bits_msb(5))
  assert_eq(@binschema.encode(layout, (5U, 17U)), Ok(b"\xb1"))
  match @binschema.decode(layout, b"\xb1") {
    Ok(decoded) => assert_eq(decoded.value, (5U, 17U))
    Err(error) => fail("unexpected error: \{error.render()}")
  }
}

///|
test "magic and fixed byte codecs reject invalid inputs" {
  let signature = @binschema.magic(b"PNG")
  assert_eq(@binschema.encode(signature, ()), Ok(b"PNG"))
  match @binschema.decode(signature, b"BAD") {
    Ok(_) => fail("invalid signature must fail")
    Err(error) => assert_eq(error.kind, @binschema.InvalidValue)
  }
  match @binschema.encode(@binschema.bytes_fixed(3), b"xx") {
    Ok(_) => fail("invalid fixed length must fail")
    Err(error) => assert_eq(error.kind, @binschema.InvalidValue)
  }
}

///|
test "decoder reports eof offset and field path" {
  let codec = @binschema.u32_be().named("packet.sequence")
  match @binschema.decode(codec, b"\x00\x01") {
    Ok(_) => fail("truncated input must fail")
    Err(error) => {
      assert_eq(error.kind, @binschema.UnexpectedEof)
      assert_eq(error.offset, 0)
      assert_eq(error.path, "packet.sequence")
    }
  }
}

///|
test "full decode rejects trailing bytes" {
  match @binschema.decode(@binschema.u8(), b"\x01\x02") {
    Ok(_) => fail("trailing input must fail")
    Err(error) => {
      assert_eq(error.kind, @binschema.TrailingBytes)
      assert_eq(error.offset, 1)
    }
  }
}

///|
test "repeat and validation enforce structural rules" {
  let codec = @binschema.repeat(
    3,
    @binschema.u8().validate(fn(value) { value < 10U }, "digit out of range"),
  )
  match @binschema.decode(codec, b"\x01\x02\x03") {
    Ok(decoded) => assert_eq(decoded.value, [1U, 2U, 3U])
    Err(error) => fail("unexpected error: \{error.render()}")
  }
  match @binschema.decode(codec, b"\x01\x0a\x03") {
    Ok(_) => fail("invalid digit must fail")
    Err(error) => assert_eq(error.path, "1")
  }
}

///|
test "limits reject oversized input before parsing" {
  let limits = @binschema.Limits::{
    max_input_bytes: 2,
    max_collection_length: 16,
    max_depth: 8,
    max_output_bytes: 16,
  }
  let options = @binschema.DecodeOptions::{ limits, require_eof: true, }
  match
    @binschema.decode_with_options(@binschema.bytes_fixed(3), b"abc", options) {
    Ok(_) => fail("oversized input must fail")
    Err(error) => assert_eq(error.kind, @binschema.LimitExceeded)
  }
}

///|
test "length-prefixed fields are decoded in bounded subregions" {
  let codec = @binschema.length_prefixed(
    @binschema.u16_be(),
    @binschema.bytes_fixed(3).named("payload"),
    max_length=8,
  )
  assert_eq(@binschema.encode(codec, b"abc"), Ok(b"\x00\x03abc"))
  match @binschema.decode(codec, b"\x00\x03abc") {
    Err(error) => fail("unexpected error: \{error.render()}")
    Ok(decoded) => {
      assert_eq(decoded.value, b"abc")
      assert_true(decoded.trace.any(fn(entry) { entry.path == "payload" }))
    }
  }
}

///|
test "optional codec uses an explicit canonical flag" {
  let codec = @binschema.optional_if(@binschema.bool8(), @binschema.u16_le())
  assert_eq(@binschema.encode(codec, None), Ok(b"\x00"))
  assert_eq(@binschema.encode(codec, Some(0x1234U)), Ok(b"\x01\x34\x12"))
  match @binschema.decode(codec, b"\x01\x34\x12") {
    Ok(decoded) => assert_eq(decoded.value, Some(0x1234U))
    Err(error) => fail("unexpected error: \{error.render()}")
  }
}

///|
test "checksum suffix rejects corrupted payloads" {
  let sum = fn(bytes : Bytes) {
    let mut value = 0U
    for byte in bytes {
      value = (value + byte.to_uint()) & 0xffU
    }
    value
  }
  let codec = @binschema.checksum_suffix(
    @binschema.pair(@binschema.u8(), @binschema.u8()),
    @binschema.u8(),
    sum,
  )
  assert_eq(@binschema.encode(codec, (2U, 3U)), Ok(b"\x02\x03\x05"))
  match @binschema.decode(codec, b"\x02\x03\x06") {
    Ok(_) => fail("corrupted checksum must fail")
    Err(error) => assert_eq(error.kind, @binschema.ChecksumMismatch)
  }
}
