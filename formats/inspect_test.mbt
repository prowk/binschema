///|
test "detect and inspect all built-in formats" {
  for
    (bytes, expected) in [
      (@formats.sample_png(), @formats.Png),
      (@formats.sample_wav(), @formats.Wav),
      (@formats.sample_pcap(), @formats.Pcap),
      (@formats.sample_bmff(), @formats.Bmff),
    ] {
    assert_eq(@formats.detect_format(bytes), Ok(expected))
    let report = match @formats.inspect(bytes) {
      Ok(value) => value
      Err(error) => fail(error.render())
    }
    assert_true(report.roundtrip_equal)
    assert_true(report.trace.length() > 0)
    assert_true(report.schema.children.length() > 0)
    assert_true(report.to_json_string().contains("roundtrip_equal"))
    assert_true(report.to_json_string().contains("schema"))
  }
}

///|
test "unknown input returns Unsupported" {
  let result = @formats.inspect(b"not a binary format")
  assert_true(result is Err({ kind: @bin.Unsupported, .. }))
}


///|
test "DNS inspection is explicit and round-trip stable" {
  let input = @formats.sample_dns()
  assert_true(@formats.detect_format(input) is Err({ kind: @bin.Unsupported, .. }))
  let report = match @formats.inspect(input, format=@formats.Dns) {
    Ok(value) => value
    Err(error) => fail(error.render())
  }
  assert_eq(report.format, "DNS")
  assert_true(report.roundtrip_equal)
  assert_true(report.summary.any(fn(entry) { entry.key == "qname" }))
  assert_true(report.trace.length() > 0)
}
