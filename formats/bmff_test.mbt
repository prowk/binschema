///|
test "ISO BMFF sample round-trips all supported header forms" {
  let bytes = @formats.sample_bmff()
  let decoded = match @bin.decode(@formats.bmff_codec(), bytes) {
    Ok(value) => value
    Err(error) => fail(error.render())
  }
  assert_eq(decoded.value.boxes.length(), 4)
  assert_eq(decoded.value.boxes[0].kind, b"ftyp")
  assert_true(!decoded.value.boxes[0].extended_size)
  assert_true(decoded.value.boxes[1].extended_size)
  assert_eq(decoded.value.boxes[1].kind, b"free")
  assert_eq(decoded.value.boxes[2].kind, b"uuid")
  assert_eq(decoded.value.boxes[2].user_type, Some(b"0123456789abcdef"))
  assert_true(decoded.value.boxes[3].size_to_eof)
  assert_eq(decoded.value.boxes[3].kind, b"mdat")
  assert_eq(@bin.encode(@formats.bmff_codec(), decoded.value), Ok(bytes))
}

///|
test "ISO BMFF rejects boxes smaller than their headers" {
  assert_true(
    @bin.decode(@formats.bmff_codec(), b"\x00\x00\x00\x04free")
    is Err({ kind: @bin.InvalidValue, .. }),
  )
  assert_true(
    @bin.decode(
      @formats.bmff_codec(),
      b"\x00\x00\x00\x01free\x00\x00\x00\x00\x00\x00\x00\x08",
    ) is Err({ kind: @bin.InvalidValue, .. }),
  )
}

///|
test "ISO BMFF rejects runtime-oversized extended boxes before allocation" {
  assert_true(
    @bin.decode(
      @formats.bmff_codec(),
      b"\x00\x00\x00\x01free\x00\x00\x00\x01\x00\x00\x00\x00",
    ) is Err({ kind: @bin.LimitExceeded, .. }),
  )
}

///|
test "ISO BMFF size zero is only emitted for the final box" {
  let invalid = @formats.BmffFile::{
    boxes: [
      {
        kind: b"free",
        extended_size: false,
        size_to_eof: true,
        user_type: None,
        payload: b"x",
      },
      {
        kind: b"mdat",
        extended_size: false,
        size_to_eof: false,
        user_type: None,
        payload: b"y",
      },
    ],
  }
  assert_true(
    @bin.encode(@formats.bmff_codec(), invalid)
    is Err({ kind: @bin.InvalidValue, .. }),
  )
}

///|
test "ISO BMFF uuid invariants are symmetric" {
  let missing = @formats.BmffFile::{
    boxes: [
      {
        kind: b"uuid",
        extended_size: false,
        size_to_eof: false,
        user_type: None,
        payload: b"",
      },
    ],
  }
  assert_true(@bin.encode(@formats.bmff_codec(), missing) is Err(_))
  let stray = @formats.BmffFile::{
    boxes: [
      {
        kind: b"free",
        extended_size: false,
        size_to_eof: false,
        user_type: Some(b"0123456789abcdef"),
        payload: b"",
      },
    ],
  }
  assert_true(@bin.encode(@formats.bmff_codec(), stray) is Err(_))
}
