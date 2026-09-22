///|
test "CLI metadata commands are pure and stable" {
  assert_true(
    run(["binschema"]) is Ok(text) &&
    text.contains("安全的二进制协议检查器"),
  )
  match run(["binschema", "formats"]) {
    Ok(value) => assert_eq(value, "支持格式: PNG, WAVE, PCAP")
    Err(error) => fail(error.message())
  }
  match run(["binschema", "--version"]) {
    Ok(value) => assert_eq(value, "binschema " + @bin.VERSION)
    Err(error) => fail(error.message())
  }
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
  assert_true(
    parse_format(["binschema", "inspect", "x", "--format", "png", "--json"], 3)
    is Ok(@formats.Png),
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
  match enforce_input_limit(b"ab", 2) {
    Ok(value) => assert_eq(value, b"ab")
    Err(error) => fail(error.message())
  }
  assert_true(enforce_input_limit(b"abc", 2) is Err(Data(_)))
  match sample_bytes("png") {
    Ok(value) => assert_eq(value, @formats.sample_png())
    Err(error) => fail(error.message())
  }
  match sample_bytes("wav") {
    Ok(value) => assert_eq(value, @formats.sample_wav())
    Err(error) => fail(error.message())
  }
  match sample_bytes("pcap") {
    Ok(value) => assert_eq(value, @formats.sample_pcap())
    Err(error) => fail(error.message())
  }
  assert_true(sample_bytes("auto") is Err(Usage(_)))
}

///|
test "CLI errors expose stable process exit codes" {
  assert_eq(Usage("x").exit_code(), 2)
  assert_eq(Data("x").exit_code(), 3)
  assert_eq(Io("x").exit_code(), 4)
  assert_eq(Usage("message").message(), "message")
}

///|
test "CLI verification rejects non-canonical round trips" {
  let report = @formats.Inspection::{
    format: "TEST",
    size: 1,
    roundtrip_equal: false,
    summary: [],
    schema: @bin.SchemaNode::leaf("test"),
    trace: [],
  }
  assert_true(verify_report(report) is Err(Data(_)))
}

///|
test "CLI schema lint supports text JSON and validation" {
  match lint_format("png", false) {
    Ok(text) => {
      assert_true(text.contains("Schema lint: png"))
      assert_true(text.contains("0 errors"))
    }
    Err(error) => fail(error.message())
  }
  match lint_format("wav", true) {
    Ok(text) => assert_true(text.contains("["))
    Err(error) => fail(error.message())
  }
  match lint_format("pcap", false) {
    Ok(text) => assert_true(text.contains("0 errors"))
    Err(error) => fail(error.message())
  }
  assert_true(lint_format("auto", false) is Err(Usage(_)))
  assert_true(lint_command(["binschema", "lint"]) is Err(Usage(_)))
  assert_true(
    lint_command(["binschema", "lint", "png", "--wat"]) is Err(Usage(_)),
  )
}
