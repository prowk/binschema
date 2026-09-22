///|
test "PNG sample validates CRC and round-trips" {
  let input = @formats.sample_png()
  match @bin.decode(@formats.png_codec(), input) {
    Err(error) => fail("unexpected error: \{error.render()}")
    Ok(decoded) => {
      assert_eq(decoded.value.chunks.length(), 3)
      assert_eq(decoded.value.chunks[0].kind, "IHDR")
      assert_eq(decoded.value.chunks[2].kind, "IEND")
      assert_eq(@bin.encode(@formats.png_codec(), decoded.value), Ok(input))
    }
  }
}

///|
test "PNG corruption is reported as a checksum failure" {
  let source = @formats.sample_png().to_array()
  source[20] = (source[20].to_uint() ^ 1U).to_byte()
  match @bin.decode(@formats.png_codec(), Bytes::from_array(source)) {
    Ok(_) => fail("corrupted PNG must fail")
    Err(error) => assert_eq(error.kind, @bin.ChecksumMismatch)
  }
}

///|
test "PNG encoder enforces IHDR and IEND structure" {
  let ihdr = b"\x00\x00\x00\x01\x00\x00\x00\x01\x08\x00\x00\x00\x00"
  let missing_header = @formats.PngFile::{
    chunks: [@formats.PngChunk::{ kind: "IEND", data: b"", crc: 0U, }],
  }
  assert_true(
    @bin.encode(@formats.png_codec(), missing_header)
    is Err({ kind: @bin.InvalidValue, .. }),
  )
  let non_empty_end = @formats.PngFile::{
    chunks: [
      @formats.PngChunk::{ kind: "IHDR", data: ihdr, crc: 0U, },
      @formats.PngChunk::{ kind: "IEND", data: b"x", crc: 0U, },
    ],
  }
  assert_true(
    @bin.encode(@formats.png_codec(), non_empty_end)
    is Err({ kind: @bin.InvalidValue, .. }),
  )
  let reserved_bit = @formats.PngFile::{
    chunks: [
      @formats.PngChunk::{ kind: "IHdR", data: ihdr, crc: 0U, },
      @formats.PngChunk::{ kind: "IEND", data: b"", crc: 0U, },
    ],
  }
  assert_true(
    @bin.encode(@formats.png_codec(), reserved_bit)
    is Err({ kind: @bin.InvalidValue, .. }),
  )
}

///|
test "PNG byte payloads are independent from collection count limits" {
  let limits = @bin.Limits::new(
    max_input_bytes=1024 * 1024,
    max_collection_length=4,
    max_depth=16,
    max_output_bytes=1024 * 1024,
  )
  let options = @bin.DecodeOptions::{ limits, require_eof: true, }
  match
    @bin.decode_with_options(
      @formats.png_codec(),
      @formats.sample_png(),
      options,
    ) {
    Err(error) => fail(error.render())
    Ok(_) => ()
  }
}

///|
test "PNG encoding enforces collection item limits" {
  let decoded = match @bin.decode(@formats.png_codec(), @formats.sample_png()) {
    Err(error) => fail(error.render())
    Ok(value) => value
  }
  let limits = @bin.Limits::new(
    max_input_bytes=1024 * 1024,
    max_collection_length=2,
    max_depth=16,
    max_output_bytes=1024 * 1024,
  )
  let options = @bin.EncodeOptions::{ limits, }
  assert_true(
    @bin.encode_with_options(@formats.png_codec(), decoded.value, options)
    is Err({ kind: @bin.LimitExceeded, .. }),
  )
}

///|
test "PNG encoder rejects stale CRC and malformed chunk type without panicking" {
  let decoded = match @bin.decode(@formats.png_codec(), @formats.sample_png()) {
    Ok(value) => value.value
    Err(error) => fail(error.render())
  }
  let stale = @formats.PngFile::{
    chunks: [
      @formats.PngChunk::{
        kind: decoded.chunks[0].kind,
        data: decoded.chunks[0].data,
        crc: 0U,
      },
      decoded.chunks[1],
      decoded.chunks[2],
    ],
  }
  assert_true(
    @bin.encode(@formats.png_codec(), stale)
    is Err({ kind: @bin.InvalidValue, .. }),
  )
  let malformed = @formats.PngFile::{
    chunks: [
      @formats.PngChunk::{ kind: "A", data: b"", crc: 0U, },
      @formats.PngChunk::{ kind: "IEND", data: b"", crc: decoded.chunks[2].crc, },
    ],
  }
  assert_true(
    @bin.encode(@formats.png_codec(), malformed)
    is Err({ kind: @bin.InvalidValue, .. }),
  )
}

///|
test "PNG encoder validates core IHDR semantics" {
  let invalid_ihdr =
    b"\x00\x00\x00\x01\x00\x00\x00\x01\x03\x02\x00\x00\x00"
  let invalid = @formats.PngFile::{
    chunks: [
      @formats.PngChunk::{ kind: "IHDR", data: invalid_ihdr, crc: 0U, },
      @formats.PngChunk::{ kind: "IEND", data: b"", crc: 0U, },
    ],
  }
  assert_true(
    @bin.encode(@formats.png_codec(), invalid)
    is Err({ kind: @bin.InvalidValue, .. }),
  )
}
