///|
fn mutation_prefix(input : Bytes, length : Int) -> Bytes {
  let output : Array[Byte] = []
  for index in 0..<length {
    output.push(input[index])
  }
  Bytes::from_array(output)
}

///|
fn mutation_replace_byte(input : Bytes, index : Int, value : Byte) -> Bytes {
  let output : Array[Byte] = []
  for position, byte in input {
    output.push(if position == index { value } else { byte })
  }
  Bytes::from_array(output)
}

///|
fn mutation_fill_range(
  input : Bytes,
  start : Int,
  end : Int,
  value : Byte,
) -> Bytes {
  let output : Array[Byte] = []
  for position, byte in input {
    output.push(if position >= start && position < end { value } else { byte })
  }
  Bytes::from_array(output)
}

///|
fn mutation_report(
  input : Bytes,
  format : @formats.Format,
) -> @formats.Inspection {
  match @formats.inspect(input, format~) {
    Ok(report) => report
    Err(error) => fail(error.render())
  }
}

///|
fn assert_structured_mutation_result(
  input : Bytes,
  format : @formats.Format,
) -> Unit {
  match @formats.inspect(input, format~) {
    Ok(report) => assert_true(report.roundtrip_equal)
    Err(error) => {
      assert_true(error.offset >= 0)
      assert_true(error.offset <= input.length())
      assert_true(error.render().length() > 0)
    }
  }
}

///|
fn assert_trace_truncations_rejected(
  input : Bytes,
  format : @formats.Format,
) -> Unit {
  let report = mutation_report(input, format)
  assert_eq(@bin.lint_schema(report.schema).length(), 0)
  let mut cases = 0
  for entry in report.trace {
    if entry.start > 0 && entry.start < input.length() {
      cases += 1
      assert_true(
        @formats.inspect(mutation_prefix(input, entry.start), format~) is Err(_),
      )
    }
    let inside_end = entry.end - 1
    if entry.end > entry.start && inside_end > 0 && inside_end < input.length() {
      cases += 1
      assert_true(
        @formats.inspect(mutation_prefix(input, inside_end), format~) is Err(_),
      )
    }
  }
  assert_true(cases > 0)
}

///|
fn is_allocation_length_field(format : @formats.Format, path : String) -> Bool {
  match format {
    @formats.Png => path.contains(".length")
    @formats.Wav => path.contains(".size")
    @formats.Pcap => path.contains(".included_length")
    @formats.Auto => false
  }
}

///|
fn assert_length_expansion_rejected(
  input : Bytes,
  format : @formats.Format,
) -> Unit {
  let report = mutation_report(input, format)
  let mut cases = 0
  for entry in report.trace {
    if entry.end > entry.start && is_allocation_length_field(format, entry.path) {
      cases += 1
      let mutated = mutation_fill_range(
        input,
        entry.start,
        entry.end,
        0xffU.to_byte(),
      )
      assert_true(@formats.inspect(mutated, format~) is Err(_))
    }
  }
  assert_true(cases > 0)
}

///|
test "mutation: field-boundary truncations stay structured on all formats" {
  for (input, format) in [
    (@formats.sample_png(), @formats.Png),
    (@formats.sample_wav(), @formats.Wav),
    (@formats.sample_pcap(), @formats.Pcap),
  ] {
    assert_trace_truncations_rejected(input, format)
  }
}

///|
test "mutation: allocation length inflation stays rejected" {
  for (input, format) in [
    (@formats.sample_png(), @formats.Png),
    (@formats.sample_wav(), @formats.Wav),
    (@formats.sample_pcap(), @formats.Pcap),
  ] {
    assert_length_expansion_rejected(input, format)
  }
}

///|
test "mutation: PNG CRC damage reports checksum mismatch" {
  let input = @formats.sample_png()
  let report = mutation_report(input, @formats.Png)
  let mut cases = 0
  for entry in report.trace {
    if entry.path.contains(".crc") && entry.end > entry.start {
      cases += 1
      let mutated = mutation_replace_byte(
        input,
        entry.start,
        (input[entry.start].to_uint() ^ 1U).to_byte(),
      )
      assert_true(
        @formats.inspect(mutated, @formats.Png)
        is Err({ kind: @bin.ChecksumMismatch, .. }),
      )
    }
  }
  assert_true(cases > 0)
}

///|
test "mutation: first-byte field flips never escape structured outcomes" {
  for (input, format) in [
    (@formats.sample_png(), @formats.Png),
    (@formats.sample_wav(), @formats.Wav),
    (@formats.sample_pcap(), @formats.Pcap),
  ] {
    let report = mutation_report(input, format)
    let mut cases = 0
    for entry in report.trace {
      if entry.end > entry.start && entry.start < input.length() {
        cases += 1
        let mutated = mutation_replace_byte(
          input,
          entry.start,
          (input[entry.start].to_uint() ^ 1U).to_byte(),
        )
        assert_structured_mutation_result(mutated, format)
      }
    }
    assert_true(cases > 0)
  }
}
