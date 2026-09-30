///|
test "TCP frame codec round-trips and reports field traces" {
  let message = EchoRequest((7U, b"hello"))
  let bytes = encode_message(message).unwrap()
  match @bin.decode(frame_codec(), bytes) {
    Err(error) => fail(error.render())
    Ok(decoded) => {
      assert_eq(decoded.value, message)
      assert_eq(decoded.consumed, bytes.length())
      assert_true(
        decoded.trace.any(fn(entry) { entry.path.contains("request_id") }),
      )
      assert_true(
        decoded.trace.any(fn(entry) { entry.path.contains("checksum") }),
      )
    }
  }
}

///|
test "TCP frame codec rejects checksum corruption" {
  let bytes = encode_message(EchoRequest((8U, b"hello"))).unwrap().to_array()
  bytes[bytes.length() - 1] = (bytes[bytes.length() - 1].to_uint() ^ 1U).to_byte()
  match @bin.decode(frame_codec(), Bytes::from_array(bytes)) {
    Ok(_) => fail("corrupted frame must fail")
    Err(error) => assert_eq(error.kind, @bin.ChecksumMismatch)
  }
}

///|
test "TCP frame codec rejects an oversized declaration before its body arrives" {
  let declared = (MAX_FRAME_BYTES + 1).reinterpret_as_uint()
  let bytes = Bytes::from_array([
    ((declared >> 24) & 0xffU).to_byte(),
    ((declared >> 16) & 0xffU).to_byte(),
    ((declared >> 8) & 0xffU).to_byte(),
    (declared & 0xffU).to_byte(),
  ])
  match @bin.probe_decode(frame_codec(), bytes) {
    @bin.Failed(error) => assert_eq(error.kind, @bin.LimitExceeded)
    _ => fail("oversized length must fail immediately")
  }
}

///|
test "incremental decoder handles fragmentation and coalescing" {
  let first = encode_message(EchoRequest((1U, b"a"))).unwrap()
  let second = encode_message(EchoRequest((2U, b"bc"))).unwrap()
  let decoder = @bin.IncrementalDecoder::new(frame_codec())
  assert_true(decoder.feed(first[0:2].to_owned()) is @bin.NeedMore)
  let tail : Array[Byte] = []
  for byte in first[2:] {
    tail.push(byte)
  }
  for byte in second {
    tail.push(byte)
  }
  match decoder.feed(Bytes::from_array(tail)) {
    @bin.Done(decoded) => assert_eq(decoded.value.request_id(), 1U)
    _ => fail("first fragmented frame must decode")
  }
  match decoder.poll() {
    @bin.Done(decoded) => assert_eq(decoded.value.request_id(), 2U)
    _ => fail("coalesced trailing frame must remain buffered")
  }
  assert_eq(decoder.buffered_bytes(), 0)
}
