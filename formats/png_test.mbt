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

///|
test "PNG encoder enforces IHDR and IEND structure" {
  let ihdr = b"\x00\x00\x00\x01\x00\x00\x00\x01\x08\x00\x00\x00\x00"
  let missing_header = PngFile::{
    chunks: [PngChunk::{ kind: "IEND", data: b"", crc: 0U, }],
  }
  assert_true(
    @bin.encode(png_codec(), missing_header)
    is Err({ kind: @bin.InvalidValue, .. }),
  )
  let non_empty_end = PngFile::{
    chunks: [
      PngChunk::{ kind: "IHDR", data: ihdr, crc: 0U, },
      PngChunk::{ kind: "IEND", data: b"x", crc: 0U, },
    ],
  }
  assert_true(
    @bin.encode(png_codec(), non_empty_end)
    is Err({ kind: @bin.InvalidValue, .. }),
  )
  let reserved_bit = PngFile::{
    chunks: [
      PngChunk::{ kind: "IHdR", data: ihdr, crc: 0U, },
      PngChunk::{ kind: "IEND", data: b"", crc: 0U, },
    ],
  }
  assert_true(
    @bin.encode(png_codec(), reserved_bit)
    is Err({ kind: @bin.InvalidValue, .. }),
  )
}
