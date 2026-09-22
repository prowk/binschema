///|
test "hex bridge accepts both letter cases" {
  assert_eq(decode_hex("00aF"), Ok(b"\x00\xaf"))
  assert_eq(decode_hex("DEADBEEF"), Ok(b"\xde\xad\xbe\xef"))
}

///|
test "hex bridge rejects malformed and oversized inputs" {
  assert_true(decode_hex("0") is Err(_))
  assert_true(decode_hex("0g") is Err(_))
  assert_true(decode_hex_with_limit("000102", 2) is Err(_))
}

///|
test "exported bridge inspects every built-in sample" {
  for format in ["png", "wav", "pcap", "bmff"] {
    let hex = sample_hex(format)
    assert_true(!hex.contains(" "))
    let report = inspect_hex("auto", hex)
    assert_true(report.contains("\"roundtrip_equal\":true"))
  }
}

///|
test "exported bridge returns structured errors" {
  assert_true(inspect_hex("zip", "00").contains("\"error\""))
  assert_true(inspect_hex("auto", "").contains("\"error\""))
  assert_true(sample_hex("auto").contains("\"error\""))
}


///|
test "DNS bridge inspection uses explicit format selection" {
  let hex = sample_hex("dns")
  assert_true(!hex.contains(" "))
  assert_true(inspect_hex("auto", hex).contains("\"error\""))
  let report = inspect_hex("dns", hex)
  assert_true(report.contains("\"roundtrip_equal\":true"))
  assert_true(report.contains("\"format\":\"DNS\""))
}
