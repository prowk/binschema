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
) -> Result[@formats.Inspection, String] {
  match @formats.inspect(input, format~) {
    Ok(report) => Ok(report)
    Err(error) => Err(error.render())
  }
}

///|
fn structured_mutation_result(
  input : Bytes,
  format : @formats.Format,
) -> Result[Unit, String] {
  match @formats.inspect(input, format~) {
    Ok(report) =>
      if report.roundtrip_equal {
        Ok(())
      } else {
        Err("successful mutation parse must remain roundtrip-stable")
      }
    Err(error) =>
      if error.offset < 0 || error.offset > input.length() {
        Err("structured error offset escaped the mutated input bounds")
      } else if error.render().length() == 0 {
        Err("structured error rendering must not be empty")
      } else {
        Ok(())
      }
  }
}

///|
fn trace_truncations_are_structured(
  input : Bytes,
  format : @formats.Format,
) -> Result[Unit, String] {
  let report = match mutation_report(input, format) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  if @bin.lint_schema(report.schema).length() != 0 {
    return Err("built-in format schema must be lint-clean before mutation")
  }
  let mut cases = 0
  for entry in report.trace {
    if entry.start > 0 && entry.start < input.length() {
      cases += 1
      match
        structured_mutation_result(mutation_prefix(input, entry.start), format) {
        Ok(_) => ()
        Err(message) => return Err(message)
      }
    }
    let inside_end = entry.end - 1
    if entry.end > entry.start && inside_end > 0 && inside_end < input.length() {
      cases += 1
      if format == @formats.Bmff && entry.path.contains(".payload") {
        match
          structured_mutation_result(mutation_prefix(input, inside_end), format) {
          Ok(_) => ()
          Err(message) => return Err(message)
        }
      } else if
        @formats.inspect(mutation_prefix(input, inside_end), format~) is Ok(_) {
        return Err(
          "truncation inside field must not parse successfully: " + entry.path,
        )
      }
    }
  }
  if cases == 0 {
    Err("mutation suite did not derive truncation cases")
  } else {
    Ok(())
  }
}

///|
fn is_allocation_length_field(format : @formats.Format, path : String) -> Bool {
  match format {
    @formats.Png => path.contains(".length")
    @formats.Wav => path.contains(".size")
    @formats.Pcap => path.contains(".included_length")
    @formats.Bmff => path.contains(".size") || path.contains(".largesize")
    @formats.Auto => false
  }
}

///|
fn length_expansion_is_rejected(
  input : Bytes,
  format : @formats.Format,
) -> Result[Unit, String] {
  let report = match mutation_report(input, format) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
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
      if @formats.inspect(mutated, format~) is Ok(_) {
        return Err("inflated allocation length must be rejected: " + entry.path)
      }
    }
  }
  if cases == 0 {
    Err("mutation suite did not derive allocation-length cases")
  } else {
    Ok(())
  }
}

///|
test "mutation: field-boundary truncations stay structured on all formats" {
  for
    (input, format) in [
      (@formats.sample_png(), @formats.Png),
      (@formats.sample_wav(), @formats.Wav),
      (@formats.sample_pcap(), @formats.Pcap),
      (@formats.sample_bmff(), @formats.Bmff),
    ] {
    match trace_truncations_are_structured(input, format) {
      Ok(_) => ()
      Err(message) => fail(message)
    }
  }
}

///|
test "mutation: allocation length inflation stays rejected" {
  for
    (input, format) in [
      (@formats.sample_png(), @formats.Png),
      (@formats.sample_wav(), @formats.Wav),
      (@formats.sample_pcap(), @formats.Pcap),
      (@formats.sample_bmff(), @formats.Bmff),
    ] {
    match length_expansion_is_rejected(input, format) {
      Ok(_) => ()
      Err(message) => fail(message)
    }
  }
}

///|
test "mutation: PNG CRC damage reports checksum mismatch" {
  let input = @formats.sample_png()
  let report = match mutation_report(input, @formats.Png) {
    Ok(value) => value
    Err(message) => fail(message)
  }
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
        @formats.inspect(mutated, format=@formats.Png)
        is Err({ kind: @bin.ChecksumMismatch, .. }),
      )
    }
  }
  assert_true(cases > 0)
}

///|
test "mutation: first-byte field flips never escape structured outcomes" {
  for
    (input, format) in [
      (@formats.sample_png(), @formats.Png),
      (@formats.sample_wav(), @formats.Wav),
      (@formats.sample_pcap(), @formats.Pcap),
      (@formats.sample_bmff(), @formats.Bmff),
    ] {
    let report = match mutation_report(input, format) {
      Ok(value) => value
      Err(message) => fail(message)
    }
    let mut cases = 0
    for entry in report.trace {
      if entry.end > entry.start && entry.start < input.length() {
        cases += 1
        let mutated = mutation_replace_byte(
          input,
          entry.start,
          (input[entry.start].to_uint() ^ 1U).to_byte(),
        )
        match structured_mutation_result(mutated, format) {
          Ok(_) => ()
          Err(message) => fail(message)
        }
      }
    }
    assert_true(cases > 0)
  }
}
