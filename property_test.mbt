///|
/// Property-style tests use deterministic generated cases so they run identically
/// on wasm, wasm-gc, js, and native without an external fuzzing dependency.
test "property: integer codecs round-trip generated values" {
  for index in 0..<512 {
    let value = index.reinterpret_as_uint() * 127U
    let codec = @binschema.u32_be()
    let encoded = match @binschema.encode(codec, value) {
      Err(error) => fail(error.render())
      Ok(bytes) => bytes
    }
    match @binschema.decode(codec, encoded) {
      Err(error) => fail(error.render())
      Ok(decoded) => assert_eq(decoded.value, value)
    }
  }
}

///|
test "property: count-prefixed arrays round-trip generated lengths" {
  let codec = @binschema.count_prefixed(
    @binschema.u8(),
    @binschema.u16_le(),
    max_count=32,
  )
  for length in 0..<32 {
    let values : Array[UInt] = []
    for index in 0..<length {
      values.push((index * 257 + length).reinterpret_as_uint())
    }
    let encoded = match @binschema.encode(codec, values) {
      Err(error) => fail(error.render())
      Ok(bytes) => bytes
    }
    match @binschema.decode(codec, encoded) {
      Err(error) => fail(error.render())
      Ok(decoded) => assert_eq(decoded.value, values)
    }
  }
}

///|
test "property: until-eof is symmetric for byte sequences" {
  let codec = @binschema.until_eof(@binschema.u8())
  for length in 0..<64 {
    let values : Array[UInt] = []
    for index in 0..<length {
      values.push(((index * 17 + length) % 256).reinterpret_as_uint())
    }
    let encoded = match @binschema.encode(codec, values) {
      Err(error) => fail(error.render())
      Ok(bytes) => bytes
    }
    match @binschema.decode(codec, encoded) {
      Err(error) => fail(error.render())
      Ok(decoded) => assert_eq(decoded.value, values)
    }
  }
}

///|
test "property: tagged codec selects symmetric branches" {
  let codec = @binschema.tagged(
    @binschema.u8(),
    fn(tag) {
      match tag {
        1U => Ok(@binschema.u8())
        2U => Ok(@binschema.u16_be())
        _ => Err("unknown tag")
      }
    },
    fn(value) { Ok(if value <= 0xffU { 1U } else { 2U }) },
    render=fn(value) { value.to_string() },
  )
  let values = [0U, 1U, 0xffU, 0x100U, 0x1234U, 0xffffU]
  for value in values {
    let encoded = match @binschema.encode(codec, value) {
      Err(error) => fail(error.render())
      Ok(bytes) => bytes
    }
    match @binschema.decode(codec, encoded) {
      Err(error) => fail(error.render())
      Ok(decoded) => assert_eq(decoded.value, value)
    }
  }
}

///|
test "property: zero-copy view codecs compose inside bounded regions" {
  let source = b"\x03abcTAIL"
  let codec = @binschema.length_prefixed(
    @binschema.u8(),
    @binschema.bytes_view_fixed(3),
    max_length=8,
  )
  match @binschema.decode_view(codec, source[:4]) {
    Err(error) => fail(error.render())
    Ok(decoded) => {
      assert_eq(decoded.consumed, 4)
      assert_eq(decoded.value.to_owned(), b"abc")
    }
  }
  match @binschema.decode_view(@binschema.remaining_view(), source[4:]) {
    Err(error) => fail(error.render())
    Ok(decoded) => assert_eq(decoded.value.to_owned(), b"TAIL")
  }
}

///|
fn property_checksum(bytes : BytesView) -> UInt {
  let mut value = 0U
  for byte in bytes {
    value = (value + byte.to_uint()) & 0xffU
  }
  value
}

///|
fn property_copy_range(input : Bytes, start : Int, end : Int) -> Bytes {
  let output : Array[Byte] = []
  for index in start..<end {
    output.push(input[index])
  }
  Bytes::from_array(output)
}

///|
test "property: checksum alignment bounded regions compose symmetrically" {
  for alignment in [1, 2, 4, 8] {
    let body = @binschema.pair(
      @binschema.u8(),
      @binschema.pair(@binschema.align(alignment), @binschema.u16_le()),
    )
    let body_length = if alignment == 1 { 3 } else { alignment + 2 }
    let codec = @binschema.bounded(
      body_length + 2,
      @binschema.length_prefixed(
        @binschema.u8(),
        @binschema.checksum_suffix_view(
          body,
          @binschema.u8(),
          property_checksum,
        ),
        max_length=body_length + 1,
      ),
    )
    for index in 0..<64 {
      let value = (
        ((index * 29 + alignment) % 256).reinterpret_as_uint(),
        ((), ((index * 977 + alignment * 31) % 65536).reinterpret_as_uint()),
      )
      let encoded = match @binschema.encode(codec, value) {
        Err(error) => fail(error.render())
        Ok(bytes) => bytes
      }
      assert_eq(encoded.length(), body_length + 2)
      match @binschema.decode(codec, encoded) {
        Err(error) => fail(error.render())
        Ok(decoded) => assert_eq(decoded.value, value)
      }
      let damaged = encoded.to_array()
      let checksum_index = damaged.length() - 1
      damaged[checksum_index] = (damaged[checksum_index].to_uint() ^ 1U).to_byte()
      assert_true(
        @binschema.decode(codec, Bytes::from_array(damaged))
        is Err({ kind: @binschema.ChecksumMismatch, .. }),
      )
    }
  }
}

///|
test "property: checksum isolates bit fields from preceding offsets" {
  for bit_count in 1..<8 {
    let body = @binschema.pair(
      @binschema.bits_msb(bit_count),
      @binschema.bits_msb(8 - bit_count),
    )
    let codec = @binschema.pair(
      @binschema.u8(),
      @binschema.checksum_suffix_view(body, @binschema.u8(), property_checksum),
    )
    let left_mask = (1 << bit_count) - 1
    let right_mask = (1 << (8 - bit_count)) - 1
    for index in 0..<32 {
      let value = (
        (index * 17 % 256).reinterpret_as_uint(),
        (
          (index & left_mask).reinterpret_as_uint(),
          ((index * 3) & right_mask).reinterpret_as_uint(),
        ),
      )
      let encoded = match @binschema.encode(codec, value) {
        Err(error) => fail(error.render())
        Ok(bytes) => bytes
      }
      match @binschema.decode(codec, encoded) {
        Err(error) => fail(error.render())
        Ok(decoded) => assert_eq(decoded.value, value)
      }
    }
  }
}

///|
test "property: length-prefixed frames survive deterministic chunking" {
  for length in 0..<32 {
    let payload : Array[Byte] = []
    for index in 0..<length {
      payload.push(((index * 37 + length * 11) % 256).to_byte())
    }
    let value = Bytes::from_array(payload)
    let codec = @binschema.length_prefixed(
      @binschema.u8(),
      @binschema.bytes_fixed(length),
      max_length=32,
    )
    let encoded = match @binschema.encode(codec, value) {
      Err(error) => fail(error.render())
      Ok(bytes) => bytes
    }
    for chunk_size in 1..<=5 {
      let stream = @binschema.IncrementalDecoder::new(codec)
      let mut offset = 0
      let mut completed = false
      while offset < encoded.length() {
        let end = if offset + chunk_size < encoded.length() {
          offset + chunk_size
        } else {
          encoded.length()
        }
        match stream.feed(property_copy_range(encoded, offset, end)) {
          @binschema.Done(decoded) => {
            assert_eq(end, encoded.length())
            assert_eq(decoded.value, value)
            completed = true
          }
          @binschema.NeedMore => assert_true(end < encoded.length())
          @binschema.Failed(error) => fail(error.render())
        }
        offset = end
      }
      assert_true(completed)
      assert_eq(stream.buffered_bytes(), 0)
    }
  }
}

///|
test "property: nested region resource limits are encode decode symmetric" {
  let codec = @binschema.bounded(
    4,
    @binschema.length_prefixed(
      @binschema.u8(),
      @binschema.bounded(3, @binschema.bytes_fixed(3)),
      max_length=3,
    ),
  )
  let value = b"abc"
  let encoded = b"\x03abc"
  for max_depth in 0..<=4 {
    let limits = @binschema.Limits::new(
      max_input_bytes=4,
      max_collection_length=16,
      max_depth~,
      max_output_bytes=4,
    )
    let encoded_result = @binschema.encode_with_options(codec, value, @binschema.EncodeOptions::{
      limits,
    })
    let decoded_result = @binschema.decode_with_options(codec, encoded, @binschema.DecodeOptions::{
      limits,
      require_eof: true,
    })
    assert_eq(encoded_result is Ok(_), decoded_result is Ok(_))
  }
  for budget in 0..<=4 {
    let limits = @binschema.Limits::new(
      max_input_bytes=budget,
      max_collection_length=16,
      max_depth=8,
      max_output_bytes=budget,
    )
    let encoded_result = @binschema.encode_with_options(codec, value, @binschema.EncodeOptions::{
      limits,
    })
    let decoded_result = @binschema.decode_with_options(codec, encoded, @binschema.DecodeOptions::{
      limits,
      require_eof: true,
    })
    assert_eq(encoded_result is Ok(_), decoded_result is Ok(_))
  }
}
