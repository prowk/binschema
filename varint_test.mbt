///|
test "ULEB128 uses canonical encodings" {
  let cases = [
    (0UL, b"\x00"),
    (127UL, b"\x7f"),
    (128UL, b"\x80\x01"),
    (624485UL, b"\xe5\x8e\x26"),
    (0xffffffffffffffffUL, b"\xff\xff\xff\xff\xff\xff\xff\xff\xff\x01"),
  ]
  for (value, bytes) in cases {
    assert_eq(@binschema.encode(@binschema.uleb128(), value), Ok(bytes))
    match @binschema.decode(@binschema.uleb128(), bytes) {
      Ok(decoded) => assert_eq(decoded.value, value)
      Err(error) => fail(error.render())
    }
  }
}

///|
test "SLEB128 preserves signed boundaries" {
  let cases = [
    (0L, b"\x00"),
    (-1L, b"\x7f"),
    (63L, b"\x3f"),
    (64L, b"\xc0\x00"),
    (-64L, b"\x40"),
    (-65L, b"\xbf\x7f"),
    (-624485L, b"\x9b\xf1\x59"),
    (9223372036854775807L, b"\xff\xff\xff\xff\xff\xff\xff\xff\xff\x00"),
    (-9223372036854775807L - 1L, b"\x80\x80\x80\x80\x80\x80\x80\x80\x80\x7f"),
  ]
  for (value, bytes) in cases {
    assert_eq(@binschema.encode(@binschema.sleb128(), value), Ok(bytes))
    match @binschema.decode(@binschema.sleb128(), bytes) {
      Ok(decoded) => assert_eq(decoded.value, value)
      Err(error) => fail(error.render())
    }
  }
}

///|
test "LEB128 rejects truncated noncanonical and overflowing values" {
  assert_true(
    @binschema.decode(@binschema.uleb128(), b"\x80")
    is Err({ kind: @binschema.UnexpectedEof, .. }),
  )
  assert_true(
    @binschema.decode(@binschema.uleb128(), b"\x80\x00")
    is Err({ kind: @binschema.InvalidValue, .. }),
  )
  assert_true(
    @binschema.decode(
      @binschema.uleb128(),
      b"\xff\xff\xff\xff\xff\xff\xff\xff\xff\x02",
    )
    is Err({ kind: @binschema.InvalidValue, .. }),
  )
  assert_true(
    @binschema.decode(@binschema.sleb128(), b"\xff\x7f")
    is Err({ kind: @binschema.InvalidValue, .. }),
  )
  assert_true(
    @binschema.decode(
      @binschema.sleb128(),
      b"\x81\x80\x80\x80\x80\x80\x80\x80\x80\x01",
    )
    is Err({ kind: @binschema.InvalidValue, .. }),
  )
  assert_true(
    @binschema.decode(
      @binschema.uleb128(),
      b"\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x00",
    )
    is Err({ kind: @binschema.LimitExceeded, .. }),
  )
}
