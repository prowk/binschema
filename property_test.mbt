///|
/// Property-style tests use deterministic generated cases so they run identically
/// on wasm, wasm-gc, js, and native without an external fuzzing dependency.
test "property: integer codecs round-trip generated values" {
  for index in 0..<512 {
    let value = index.reinterpret_as_uint() * 127U
    let codec = u32_be()
    let encoded = match encode(codec, value) {
      Err(error) => fail(error.render())
      Ok(bytes) => bytes
    }
    match decode(codec, encoded) {
      Err(error) => fail(error.render())
      Ok(decoded) => assert_eq(decoded.value, value)
    }
  }
}

///|
test "property: count-prefixed arrays round-trip generated lengths" {
  let codec = count_prefixed(u8(), u16_le(), max_count=32)
  for length in 0..<32 {
    let values : Array[UInt] = []
    for index in 0..<length {
      values.push((index * 257 + length).reinterpret_as_uint())
    }
    let encoded = match encode(codec, values) {
      Err(error) => fail(error.render())
      Ok(bytes) => bytes
    }
    match decode(codec, encoded) {
      Err(error) => fail(error.render())
      Ok(decoded) => assert_eq(decoded.value, values)
    }
  }
}

///|
test "property: until-eof is symmetric for byte sequences" {
  let codec = until_eof(u8())
  for length in 0..<64 {
    let values : Array[UInt] = []
    for index in 0..<length {
      values.push(((index * 17 + length) % 256).reinterpret_as_uint())
    }
    let encoded = match encode(codec, values) {
      Err(error) => fail(error.render())
      Ok(bytes) => bytes
    }
    match decode(codec, encoded) {
      Err(error) => fail(error.render())
      Ok(decoded) => assert_eq(decoded.value, values)
    }
  }
}

///|
test "property: tagged codec selects symmetric branches" {
  let codec = tagged(
    u8(),
    fn(tag) {
      match tag {
        1U => Ok(u8())
        2U => Ok(u16_be())
        _ => Err("unknown tag")
      }
    },
    fn(value) { Ok(if value <= 0xffU { 1U } else { 2U }) },
    render=fn(value) { value.to_string() },
  )
  let values = [0U, 1U, 0xffU, 0x100U, 0x1234U, 0xffffU]
  for value in values {
    let encoded = match encode(codec, value) {
      Err(error) => fail(error.render())
      Ok(bytes) => bytes
    }
    match decode(codec, encoded) {
      Err(error) => fail(error.render())
      Ok(decoded) => assert_eq(decoded.value, value)
    }
  }
}

///|
test "property: zero-copy view codecs compose inside bounded regions" {
  let source = b"\x03abcTAIL"
  let codec = length_prefixed(u8(), bytes_view_fixed(3), max_length=8)
  match decode_view(codec, source[:4]) {
    Err(error) => fail(error.render())
    Ok(decoded) => {
      assert_eq(decoded.consumed, 4)
      assert_eq(decoded.value.to_bytes(), b"abc")
    }
  }
  match decode_view(remaining_view(), source[4:]) {
    Err(error) => fail(error.render())
    Ok(decoded) => assert_eq(decoded.value.to_bytes(), b"TAIL")
  }
}
