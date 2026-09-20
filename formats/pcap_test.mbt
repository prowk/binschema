///|
test "PCAP sample preserves global header and packet data" {
  let input = @formats.sample_pcap()
  match @bin.decode(@formats.pcap_codec(), input) {
    Err(error) => fail("unexpected error: \{error.render()}")
    Ok(decoded) => {
      assert_eq(decoded.value.version_major, 2U)
      assert_eq(decoded.value.version_minor, 4U)
      assert_eq(decoded.value.packets.length(), 1)
      assert_eq(decoded.value.packets[0].data, b"\xde\xad\xbe\xef")
      assert_eq(@bin.encode(@formats.pcap_codec(), decoded.value), Ok(input))
    }
  }
}

///|
test "PCAP auto-endian parsing supports big-endian files" {
  let value = @formats.PcapFile::{
    endian: @bin.Big,
    nanosecond_timestamps: true,
    version_major: 2U,
    version_minor: 4U,
    timezone_offset: 0,
    timestamp_accuracy: 0U,
    snapshot_length: 64U,
    link_type: 1U,
    packets: [],
  }
  match @bin.encode(@formats.pcap_codec(), value) {
    Err(error) => fail("unexpected error: \{error.render()}")
    Ok(bytes) =>
      match @bin.decode(@formats.pcap_codec(), bytes) {
        Err(error) => fail("unexpected error: \{error.render()}")
        Ok(decoded) => {
          assert_eq(decoded.value.endian, @bin.Big)
          assert_eq(decoded.value.nanosecond_timestamps, true)
        }
      }
  }
}

///|
test "PCAP validates header and packet invariants" {
  let invalid_version = @formats.PcapFile::{
    endian: @bin.Little,
    nanosecond_timestamps: false,
    version_major: 1U,
    version_minor: 0U,
    timezone_offset: 0,
    timestamp_accuracy: 0U,
    snapshot_length: 64U,
    link_type: 1U,
    packets: [],
  }
  assert_true(
    @bin.encode(@formats.pcap_codec(), invalid_version)
    is Err({ kind: @bin.InvalidValue, .. }),
  )
  let invalid_packet = @formats.PcapPacket::{
    timestamp_seconds: 0U,
    timestamp_fraction: 1_000_000U,
    original_length: 1U,
    data: b"\x00\x01",
  }
  let invalid_file = @formats.PcapFile::{
    endian: @bin.Little,
    nanosecond_timestamps: false,
    version_major: 2U,
    version_minor: 4U,
    timezone_offset: 0,
    timestamp_accuracy: 0U,
    snapshot_length: 1U,
    link_type: 1U,
    packets: [invalid_packet],
  }
  assert_true(
    @bin.encode(@formats.pcap_codec(), invalid_file)
    is Err({ kind: @bin.InvalidValue, .. }),
  )
}

///|
test "PCAP decoder rejects timestamp fractions outside resolution" {
  let source = @formats.sample_pcap().to_array()
  source[28] = b'\x40'
  source[29] = b'\x42'
  source[30] = b'\x0f'
  source[31] = b'\x00'
  assert_true(
    @bin.decode(@formats.pcap_codec(), Bytes::from_array(source))
    is Err({ kind: @bin.InvalidValue, .. }),
  )
}

///|
test "PCAP byte payloads are independent from collection count limits" {
  let limits = @bin.Limits::{
    max_input_bytes: 1024 * 1024,
    max_collection_length: 2,
    max_depth: 16,
    max_output_bytes: 1024 * 1024,
  }
  let options = @bin.DecodeOptions::{ limits, require_eof: true, }
  match
    @bin.decode_with_options(
      @formats.pcap_codec(),
      @formats.sample_pcap(),
      options,
    ) {
    Err(error) => fail(error.render())
    Ok(_) => ()
  }
}

///|
test "PCAP encoding enforces collection item limits" {
  let decoded = match
    @bin.decode(@formats.pcap_codec(), @formats.sample_pcap()) {
    Err(error) => fail(error.render())
    Ok(value) => value
  }
  let limits = @bin.Limits::{
    max_input_bytes: 1024 * 1024,
    max_collection_length: 0,
    max_depth: 16,
    max_output_bytes: 1024 * 1024,
  }
  let options = @bin.EncodeOptions::{ limits, }
  assert_true(
    @bin.encode_with_options(@formats.pcap_codec(), decoded.value, options)
    is Err({ kind: @bin.LimitExceeded, .. }),
  )
}
