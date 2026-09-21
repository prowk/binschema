///|
test "demo protocol round-trips tagged messages and rejects corruption" {
  let codec = demo_protocol_codec()
  let value = (
    (),
    (
      1U,
      (
        0U,
        [
          Counter(7U),
          Sensor((3U, 512U)),
          Blob(b"abc"),
        ],
      ),
    ),
  )
  let bytes = match @bin.encode(codec, value) {
    Err(error) => fail(error.render())
    Ok(bytes) => bytes
  }
  match @bin.decode(codec, bytes) {
    Err(error) => fail(error.render())
    Ok(decoded) => {
      assert_eq(decoded.value, value)
      assert_true(decoded.trace.any(fn(entry) { entry.path.contains("messages") }))
      assert_true(decoded.trace.any(fn(entry) { entry.path.contains("checksum") }))
    }
  }

  let corrupted = bytes.to_array()
  corrupted[3] = (corrupted[3].to_uint() ^ 0x01U).to_byte()
  match @bin.decode(codec, Bytes::from_array(corrupted)) {
    Ok(_) => fail("corrupted demo packet must fail")
    Err(error) => assert_eq(error.kind, @bin.ChecksumMismatch)
  }
}
