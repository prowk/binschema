///|
test "PCAP sample preserves global header and packet data" {
  let input = sample_pcap()
  match @bin.decode(pcap_codec(), input) {
    Err(error) => fail("unexpected error: \{error.render()}")
    Ok(decoded) => {
      assert_eq(decoded.value.version_major, 2U)
      assert_eq(decoded.value.version_minor, 4U)
      assert_eq(decoded.value.packets.length(), 1)
      assert_eq(decoded.value.packets[0].data, b"\xde\xad\xbe\xef")
      assert_eq(@bin.encode(pcap_codec(), decoded.value), Ok(input))
    }
  }
}

///|
test "PCAP auto-endian parsing supports big-endian files" {
  let value = PcapFile::{
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
  match @bin.encode(pcap_codec(), value) {
    Err(error) => fail("unexpected error: \{error.render()}")
    Ok(bytes) =>
      match @bin.decode(pcap_codec(), bytes) {
        Err(error) => fail("unexpected error: \{error.render()}")
        Ok(decoded) => {
          assert_eq(decoded.value.endian, @bin.Big)
          assert_eq(decoded.value.nanosecond_timestamps, true)
        }
      }
  }
}
