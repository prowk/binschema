///|
test "WAVE sample exposes PCM metadata and round-trips" {
  let input = @formats.sample_wav()
  match @bin.decode(@formats.wav_codec(), input) {
    Err(error) => fail("unexpected error: \{error.render()}")
    Ok(decoded) => {
      assert_eq(decoded.value.chunks.length(), 2)
      assert_true(
        decoded.value.format
        is Some({ audio_format: 1U, channels: 1U, sample_rate: 8000U, .. }),
      )
      assert_eq(@bin.encode(@formats.wav_codec(), decoded.value), Ok(input))
    }
  }
}

///|
test "WAVE rejects inconsistent RIFF sizes" {
  let source = @formats.sample_wav().to_array()
  source[4] = b'\x00'
  source[5] = b'\x00'
  source[6] = b'\x00'
  source[7] = b'\x00'
  match @bin.decode(@formats.wav_codec(), Bytes::from_array(source)) {
    Ok(_) => fail("invalid RIFF size must fail")
    Err(error) => assert_eq(error.kind, @bin.InvalidValue)
  }
}

///|
test "WAVE requires a valid fmt chunk before data" {
  let data_first = @formats.WavFile::{
    riff_size: 0U,
    chunks: [@formats.WavChunk::{ id: "data", data: b"\x00", padding: None, }],
    format: None,
  }
  assert_true(
    @bin.encode(@formats.wav_codec(), data_first)
    is Err({ kind: @bin.InvalidValue, .. }),
  )
  let invalid_fmt = b"\x01\x00\x00\x00\x40\x1f\x00\x00\x40\x1f\x00\x00\x01\x00\x08\x00"
  let invalid = @formats.WavFile::{
    riff_size: 0U,
    chunks: [
      @formats.WavChunk::{ id: "fmt ", data: invalid_fmt, padding: None, },
      @formats.WavChunk::{ id: "data", data: b"\x00", padding: None, },
    ],
    format: None,
  }
  assert_true(
    @bin.encode(@formats.wav_codec(), invalid)
    is Err({ kind: @bin.InvalidValue, .. }),
  )
}

///|
test "WAV byte payloads are independent from collection count limits" {
  let limits = @bin.Limits::new(
    max_input_bytes=1024 * 1024,
    max_collection_length=3,
    max_depth=16,
    max_output_bytes=1024 * 1024,
  )
  let options = @bin.DecodeOptions::{ limits, require_eof: true, }
  match
    @bin.decode_with_options(
      @formats.wav_codec(),
      @formats.sample_wav(),
      options,
    ) {
    Err(error) => fail(error.render())
    Ok(_) => ()
  }
}

///|
test "WAVE encoding enforces collection item limits" {
  let decoded = match @bin.decode(@formats.wav_codec(), @formats.sample_wav()) {
    Err(error) => fail(error.render())
    Ok(value) => value
  }
  let limits = @bin.Limits::new(
    max_input_bytes=1024 * 1024,
    max_collection_length=1,
    max_depth=16,
    max_output_bytes=1024 * 1024,
  )
  let options = @bin.EncodeOptions::{ limits, }
  assert_true(
    @bin.encode_with_options(@formats.wav_codec(), decoded.value, options)
    is Err({ kind: @bin.LimitExceeded, .. }),
  )
}

///|
test "WAVE encoder rejects stale public metadata" {
  let decoded = match @bin.decode(@formats.wav_codec(), @formats.sample_wav()) {
    Ok(value) => value.value
    Err(error) => fail(error.render())
  }
  let stale_size = @formats.WavFile::{
    riff_size: decoded.riff_size + 1U,
    chunks: decoded.chunks,
    format: decoded.format,
  }
  assert_true(
    @bin.encode(@formats.wav_codec(), stale_size)
    is Err({ kind: @bin.InvalidValue, .. }),
  )
  let stale_format = @formats.WavFile::{
    riff_size: decoded.riff_size,
    chunks: decoded.chunks,
    format: Some(@formats.WavFormat::{
      audio_format: 1U,
      channels: 2U,
      sample_rate: 8000U,
      byte_rate: 16000U,
      block_align: 2U,
      bits_per_sample: 8U,
    }),
  }
  assert_true(
    @bin.encode(@formats.wav_codec(), stale_format)
    is Err({ kind: @bin.InvalidValue, .. }),
  )
}

///|
test "WAVE encoder rejects invalid ids and impossible padding metadata" {
  let fmt =
    b"\x01\x00\x01\x00\x40\x1f\x00\x00\x40\x1f\x00\x00\x01\x00\x08\x00"
  let invalid_id = @formats.WavFile::{
    riff_size: 0U,
    chunks: [
      @formats.WavChunk::{ id: "fmt ", data: fmt, padding: None, },
      @formats.WavChunk::{ id: "\u0001bad", data: b"\x00", padding: None, },
      @formats.WavChunk::{ id: "data", data: b"\x00", padding: Some(b'\x00'), },
    ],
    format: None,
  }
  assert_true(
    @bin.encode(@formats.wav_codec(), invalid_id)
    is Err({ kind: @bin.InvalidValue, .. }),
  )
  let even_padding = @formats.WavFile::{
    riff_size: 0U,
    chunks: [
      @formats.WavChunk::{ id: "fmt ", data: fmt, padding: None, },
      @formats.WavChunk::{ id: "data", data: b"\x00\x01", padding: Some(b'\x00'), },
    ],
    format: None,
  }
  assert_true(
    @bin.encode(@formats.wav_codec(), even_padding)
    is Err({ kind: @bin.InvalidValue, .. }),
  )
}
