///|
test "WAVE sample exposes PCM metadata and round-trips" {
  let input = sample_wav()
  match @bin.decode(wav_codec(), input) {
    Err(error) => fail("unexpected error: \{error.render()}")
    Ok(decoded) => {
      assert_eq(decoded.value.chunks.length(), 2)
      assert_true(
        decoded.value.format
        is Some({ audio_format: 1U, channels: 1U, sample_rate: 8000U, .. }),
      )
      assert_eq(@bin.encode(wav_codec(), decoded.value), Ok(input))
    }
  }
}

///|
test "WAVE rejects inconsistent RIFF sizes" {
  let source = sample_wav().to_array()
  source[4] = b'\x00'
  source[5] = b'\x00'
  source[6] = b'\x00'
  source[7] = b'\x00'
  match @bin.decode(wav_codec(), Bytes::from_array(source)) {
    Ok(_) => fail("invalid RIFF size must fail")
    Err(error) => assert_eq(error.kind, @bin.InvalidValue)
  }
}
