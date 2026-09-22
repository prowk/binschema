///|
test "DNS sample decodes compressed answer names and round-trips exactly" {
  let bytes = @formats.sample_dns()
  let decoded = match @bin.decode(@formats.dns_codec(), bytes) {
    Ok(value) => value
    Err(error) => fail(error.render())
  }
  assert_eq(decoded.value.id, 0x1234U)
  assert_eq(decoded.value.questions.length(), 1)
  assert_eq(decoded.value.answers.length(), 1)
  assert_eq(decoded.value.questions[0].name.display(), "example.com.")
  assert_eq(decoded.value.answers[0].name.display(), "example.com.")
  assert_eq(decoded.value.answers[0].name.wire, b"\xc0\x0c")
  assert_eq(decoded.value.answers[0].rr_type, 1U)
  assert_eq(decoded.value.answers[0].rdata, b"\x01\x02\x03\x04")
  assert_eq(@bin.encode(@formats.dns_codec(), decoded.value), Ok(bytes))
}

///|
test "DNS uncompressed name helper validates wire limits" {
  let name = match @formats.dns_name_uncompressed([b"www", b"example", b"com"]) {
    Ok(value) => value
    Err(message) => fail(message)
  }
  assert_eq(name.display(), "www.example.com.")
  assert_eq(name.wire, b"\x03www\x07example\x03com\x00")
  assert_true(@formats.dns_name_uncompressed([b""]) is Err(_))
  let too_long : Array[Byte] = []
  for _ in 0..<64 {
    too_long.push(b'a')
  }
  assert_true(
    @formats.dns_name_uncompressed([Bytes::from_array(too_long)]) is Err(_),
  )
}

///|
test "DNS rejects self and forward compression pointers" {
  let self_pointer =
    b"\x00\x01\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00\xc0\x0c\x00\x01\x00\x01"
  assert_true(
    @bin.decode(@formats.dns_codec(), self_pointer)
    is Err({ kind: @bin.InvalidValue, .. }),
  )
  let forward_pointer =
    b"\x00\x01\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00\xc0\x0e\x00\x01\x00\x01"
  assert_true(
    @bin.decode(@formats.dns_codec(), forward_pointer)
    is Err({ kind: @bin.InvalidValue, .. }),
  )
}

///|
test "DNS rejects reserved label encodings" {
  let packet =
    b"\x00\x01\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00\x40\x00\x01\x00\x01"
  assert_true(
    @bin.decode(@formats.dns_codec(), packet)
    is Err({ kind: @bin.InvalidValue, .. }),
  )
}

///|
test "DNS section counts honor configured collection limits before looping" {
  let packet =
    b"\x00\x01\x01\x00\x00\x02\x00\x00\x00\x00\x00\x00"
  let limits = @bin.Limits::new(
    max_input_bytes=64,
    max_collection_length=1,
    max_depth=8,
    max_output_bytes=64,
  )
  let options = @bin.DecodeOptions::{ limits, require_eof: true, }
  assert_true(
    @bin.decode_with_options(@formats.dns_codec(), packet, options)
    is Err({ kind: @bin.LimitExceeded, .. }),
  )
}

///|
test "DNS encoder derives section counts and validates compressed wire direction" {
  let question_name = match @formats.dns_name_uncompressed([b"example", b"com"]) {
    Ok(value) => value
    Err(message) => fail(message)
  }
  let invalid_pointer = @formats.DnsName::{ labels: [], wire: b"\xc0\xff" }
  let message = @formats.DnsMessage::{
    id: 1U,
    flags: 0x0100U,
    questions: [{ name: question_name, qtype: 1U, qclass: 1U, }],
    answers: [
      {
        name: invalid_pointer,
        rr_type: 1U,
        rr_class: 1U,
        ttl: 1U,
        rdata: b"\x7f\x00\x00\x01",
      },
    ],
    authorities: [],
    additionals: [],
  }
  assert_true(
    @bin.encode(@formats.dns_codec(), message)
    is Err({ kind: @bin.InvalidValue, .. }),
  )
}
