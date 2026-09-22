///|
/// Fixed wire fixtures are written independently from sample_* encoders so a shared
/// encoder/decoder bug cannot make every real-format smoke test pass by construction.
test "golden wire fixtures decode and round-trip independently" {
  let png =
    b"\x89PNG\x0d\x0a\x1a\x0a\x00\x00\x00\x0dIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x00\x00\x00\x00\x3a\x7e\x9b\x55\x00\x00\x00\x0aIDAT\x78\x9c\x63\x60\x00\x00\x00\x02\x00\x01\x48\xaf\xa4\x71\x00\x00\x00\x00IEND\xae\x42\x60\x82"
  match @formats.inspect(png, format=@formats.Png) {
    Ok(report) => assert_true(report.roundtrip_equal)
    Err(error) => fail(error.render())
  }

  let wav =
    b"RIFF\x28\x00\x00\x00WAVEfmt \x10\x00\x00\x00\x01\x00\x01\x00\x40\x1f\x00\x00\x40\x1f\x00\x00\x01\x00\x08\x00data\x04\x00\x00\x00\x00\x40\x80\xff"
  match @formats.inspect(wav, format=@formats.Wav) {
    Ok(report) => assert_true(report.roundtrip_equal)
    Err(error) => fail(error.render())
  }

  let pcap =
    b"\xd4\xc3\xb2\xa1\x02\x00\x04\x00\x00\x00\x00\x00\x00\x00\x00\x00\xff\xff\x00\x00\x01\x00\x00\x00\x01\x00\x00\x00\x02\x00\x00\x00\x04\x00\x00\x00\x04\x00\x00\x00\xde\xad\xbe\xef"
  match @formats.inspect(pcap, format=@formats.Pcap) {
    Ok(report) => assert_true(report.roundtrip_equal)
    Err(error) => fail(error.render())
  }

  let bmff =
    b"\x00\x00\x00\x18ftypisom\x00\x00\x02\x00isomiso2"
  match @formats.inspect(bmff, format=@formats.Bmff) {
    Ok(report) => assert_true(report.roundtrip_equal)
    Err(error) => fail(error.render())
  }

  let dns =
    b"\x12\x34\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00\x07example\x03com\x00\x00\x01\x00\x01"
  match @formats.inspect(dns, format=@formats.Dns) {
    Ok(report) => {
      assert_true(report.roundtrip_equal)
      assert_true(report.summary.any(fn(item) { item.value == "example.com" }))
    }
    Err(error) => fail(error.render())
  }

  let elf =
    b"\x7fELF\x01\x02\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x01\x00\x03\x00\x00\x00\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x34\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
  match @formats.inspect(elf, format=@formats.Elf) {
    Ok(report) => assert_true(report.roundtrip_equal)
    Err(error) => fail(error.render())
  }
}
