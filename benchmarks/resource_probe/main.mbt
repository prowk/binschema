///|
fn fail_probe(message : String) -> Unit {
  println("resource probe failed: " + message)
  @sys.exit(1)
}

///|
fn push_u16(output : Array[Byte], value : UInt) -> Unit {
  output.push(value.to_byte())
  output.push((value >> 8).to_byte())
}

///|
fn push_u32(output : Array[Byte], value : UInt) -> Unit {
  for shift in [0, 8, 16, 24] {
    output.push((value >> shift).to_byte())
  }
}

///|
fn push_u64(output : Array[Byte], value : UInt64) -> Unit {
  for shift in [0, 8, 16, 24, 32, 40, 48, 56] {
    output.push((value >> shift).to_byte())
  }
}

///|
fn push_section(
  output : Array[Byte],
  name_offset : UInt,
  section_type : UInt,
  offset : UInt64,
  size : UInt64,
) -> Unit {
  push_u32(output, name_offset)
  push_u32(output, section_type)
  push_u64(output, 0UL)
  push_u64(output, 0UL)
  push_u64(output, offset)
  push_u64(output, size)
  push_u32(output, 0U)
  push_u32(output, 0U)
  push_u64(output, 1UL)
  push_u64(output, 0UL)
}

///|
fn repeated_name_elf(name_length : Int, reference_count : Int) -> Bytes {
  let section_count = reference_count + 2
  let string_table_size = name_length + 2
  let section_table_offset = 64 + string_table_size
  let output = b"\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00".to_array()
  push_u16(output, 1U)
  push_u16(output, 62U)
  push_u32(output, 1U)
  push_u64(output, 0UL)
  push_u64(output, 0UL)
  push_u64(output, section_table_offset.to_uint64())
  push_u32(output, 0U)
  push_u16(output, 64U)
  push_u16(output, 0U)
  push_u16(output, 0U)
  push_u16(output, 64U)
  push_u16(output, section_count.reinterpret_as_uint())
  push_u16(output, (section_count - 1).reinterpret_as_uint())
  output.push(0U.to_byte())
  for _ in 0..<name_length {
    output.push(b'n')
  }
  output.push(0U.to_byte())
  push_section(output, 0U, 0U, 0UL, 0UL)
  for _ in 0..<reference_count {
    push_section(output, 1U, 8U, 0UL, 0UL)
  }
  push_section(output, 0U, 3U, 64UL, string_table_size.to_uint64())
  Bytes::from_array(output)
}

///|
fn probe_large_input() -> Unit {
  let input_size = 32 * 1024 * 1024
  let input = Bytes::make(input_size, 0x5a)
  match @bin.decode_view(@bin.bytes_view_fixed(input_size), input[:]) {
    Ok(decoded) => {
      if decoded.value.length() != input_size || decoded.consumed != input_size {
        fail_probe("large input result mismatch")
      }
      println(
        "{\"scenario\":\"large-input\",\"input_bytes\":\{input_size},\"decoded_bytes\":\{decoded.consumed}}",
      )
    }
    Err(error) => fail_probe(error.render())
  }
}

///|
fn probe_elf_repeated_names() -> Unit {
  let name_length = 8 * 1024
  let reference_count = 4096
  let input = repeated_name_elf(name_length, reference_count)
  match @bin.decode(@formats.elf_codec(), input) {
    Ok(decoded) => {
      if decoded.value.sections.length() != reference_count + 2 ||
        decoded.value.sections[1].name.length() != name_length ||
        decoded.value.sections[reference_count].name !=
        decoded.value.sections[1].name {
        fail_probe("ELF repeated-name result mismatch")
      }
      println(
        "{\"scenario\":\"elf-repeated-names\",\"input_bytes\":\{input.length()},\"section_count\":\{reference_count + 2},\"name_bytes\":\{name_length},\"trace_entries\":\{decoded.trace.length()}}",
      )
    }
    Err(error) => fail_probe(error.render())
  }
}

///|
fn probe_short_frames() -> Unit {
  let frame_count = 50_000
  let input = Bytes::makei(frame_count * 2, fn(index) {
    let value = (index / 2) & 0xffff
    if index % 2 == 0 {
      (value >> 8).to_byte()
    } else {
      value.to_byte()
    }
  })
  let limits = @bin.Limits::new(max_input_bytes=input.length())
  let stream = @bin.IncrementalDecoder::new(@bin.u16_be(), limits~)
  match stream.append(input) {
    Err(error) => fail_probe(error.render())
    Ok(_) => ()
  }
  for expected in 0..<frame_count {
    match stream.poll() {
      @bin.Done(decoded) =>
        if decoded.value != (expected & 0xffff).reinterpret_as_uint() {
          fail_probe("short frame order mismatch")
        }
      @bin.NeedMore => fail_probe("short frame unexpectedly needs more input")
      @bin.Failed(error) => fail_probe(error.render())
    }
  }
  if stream.buffered_bytes() != 0 {
    fail_probe("short frame buffer was not drained")
  }
  println(
    "{\"scenario\":\"short-frames\",\"input_bytes\":\{input.length()},\"frame_count\":\{frame_count},\"remaining_bytes\":0}",
  )
}

///|
fn probe_many_traces() -> Unit {
  let field_count = 80_000
  let input = Bytes::make(field_count, 0x2a)
  let limits = @bin.Limits::new(
    max_input_bytes=input.length(),
    max_trace_entries=field_count * 2,
  )
  let codec = @bin.repeat(field_count, @bin.u8().named("byte"))
  match @bin.decode_with_options(codec, input, { limits, require_eof: true, }) {
    Ok(decoded) => {
      if decoded.value.length() != field_count ||
        decoded.trace.length() != field_count * 2 {
        fail_probe("trace count mismatch")
      }
      println(
        "{\"scenario\":\"many-traces\",\"input_bytes\":\{input.length()},\"field_count\":\{field_count},\"trace_entries\":\{decoded.trace.length()}}",
      )
    }
    Err(error) => fail_probe(error.render())
  }
}

///|
fn main {
  let args = @env.args()
  if args.length() != 2 {
    fail_probe(
      "usage: resource_probe <large-input|elf-repeated-names|short-frames|many-traces>",
    )
  }
  match args[1] {
    "large-input" => probe_large_input()
    "elf-repeated-names" => probe_elf_repeated_names()
    "short-frames" => probe_short_frames()
    "many-traces" => probe_many_traces()
    scenario => fail_probe("unknown scenario: " + scenario)
  }
}
