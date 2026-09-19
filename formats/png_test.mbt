///|
test "PNG sample validates CRC and round-trips" {
  let input = sample_png()
  match @bin.decode(png_codec(), input) {
    Err(error) => fail("unexpected error: \{error.render()}")
    Ok(decoded) => {
      assert_eq(decoded.value.chunks.length(), 3)
      assert_eq(decoded.value.chunks[0].kind, "IHDR")
      assert_eq(decoded.value.chunks[2].kind, "IEND")
      assert_eq(@bin.encode(png_codec(), decoded.value), Ok(input))
    }
  }
}

///|
test "PNG corruption is reported as a checksum failure" {
  let source = sample_png().to_array()
  source[20] = (source[20].to_uint() ^ 1U).to_byte()
  match @bin.decode(png_codec(), Bytes::from_array(source)) {
    Ok(_) => fail("corrupted PNG must fail")
    Err(error) => assert_eq(error.kind, @bin.ChecksumMismatch)
  }
}
