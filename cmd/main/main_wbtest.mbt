///|
test "CLI metadata commands are pure and stable" {
  assert_true(
    run(["binschema"]) is Ok(text) &&
    text.contains("安全的二进制协议检查器"),
  )
  assert_eq(run(["binschema", "formats"]), Ok("支持格式: PNG, WAVE, PCAP"))
  assert_eq(run(["binschema", "--version"]), Ok("binschema " + @bin.VERSION))
  assert_true(run(["binschema", "unknown"]) is Err(Usage(_)))
}

///|
test "CLI parameter parser rejects malformed flags" {
  assert_true(
    parse_format(["binschema", "inspect", "x", "--format"], 3) is Err(Usage(_)),
  )
  assert_true(
    parse_format(["binschema", "inspect", "x", "--format", "zip"], 3)
    is Err(Usage(_)),
  )
  assert_true(
    parse_format(["binschema", "inspect", "x", "--wat"], 3) is Err(Usage(_)),
  )
  assert_eq(
    parse_format(["binschema", "inspect", "x", "--format", "png", "--json"], 3),
    Ok(@formats.Png),
  )
}

///|
test "CLI inspection renders text JSON and verification" {
  let input = @formats.sample_png()
  match inspect_input(input, @formats.Auto, false, false) {
    Ok(text) => {
      assert_true(text.contains("格式: PNG"))
      assert_true(text.contains("png.signature"))
    }
    Err(error) => fail(error.message())
  }
  match inspect_input(input, @formats.Png, true, false) {
    Ok(text) => assert_true(text.contains("\"roundtrip_equal\": true"))
    Err(error) => fail(error.message())
  }
  match inspect_input(input, @formats.Auto, false, true) {
    Ok(text) => assert_true(text.contains("验证通过：PNG"))
    Err(error) => fail(error.message())
  }
  assert_true(inspect_input(input, @formats.Wav, false, false) is Err(Data(_)))
}

///|
test "CLI input budgets and sample selection are enforced" {
  assert_eq(enforce_input_limit(b"ab", 2), Ok(b"ab"))
  assert_true(enforce_input_limit(b"abc", 2) is Err(Data(_)))
  assert_eq(sample_bytes("png"), Ok(@formats.sample_png()))
  assert_eq(sample_bytes("wav"), Ok(@formats.sample_wav()))
  assert_eq(sample_bytes("pcap"), Ok(@formats.sample_pcap()))
  assert_true(sample_bytes("auto") is Err(Usage(_)))
}

///|
test "CLI errors expose stable process exit codes" {
  assert_eq(Usage("x").exit_code(), 2)
  assert_eq(Data("x").exit_code(), 3)
  assert_eq(Io("x").exit_code(), 4)
  assert_eq(Usage("message").message(), "message")
}
