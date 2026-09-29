///|
fn elf_test_push_u16(output : Array[Byte], value : UInt) -> Unit {
  output.push(value.to_byte())
  output.push((value >> 8).to_byte())
}

///|
fn elf_test_push_u32(output : Array[Byte], value : UInt) -> Unit {
  for shift in [0, 8, 16, 24] {
    output.push((value >> shift).to_byte())
  }
}

///|
fn elf_test_push_u64(output : Array[Byte], value : UInt64) -> Unit {
  for shift in [0, 8, 16, 24, 32, 40, 48, 56] {
    output.push((value >> shift).to_byte())
  }
}

///|
fn elf_test_push_section(
  output : Array[Byte],
  name_offset : UInt,
  section_type : UInt,
  offset : UInt64,
  size : UInt64,
) -> Unit {
  elf_test_push_u32(output, name_offset)
  elf_test_push_u32(output, section_type)
  elf_test_push_u64(output, 0UL)
  elf_test_push_u64(output, 0UL)
  elf_test_push_u64(output, offset)
  elf_test_push_u64(output, size)
  elf_test_push_u32(output, 0U)
  elf_test_push_u32(output, 0U)
  elf_test_push_u64(output, 1UL)
  elf_test_push_u64(output, 0UL)
}

///|
fn elf_test_name_fixture(overlap : Bool) -> Bytes {
  let name_count = 10
  let section_count = name_count + 2
  let string_table = b"\x00abcdefghijklmnopqrstuvwxyz01234\x00"
  let section_table_offset = 104
  let output = b"\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00".to_array()
  elf_test_push_u16(output, 1U)
  elf_test_push_u16(output, 62U)
  elf_test_push_u32(output, 1U)
  elf_test_push_u64(output, 0UL)
  elf_test_push_u64(output, 0UL)
  elf_test_push_u64(output, section_table_offset.to_uint64())
  elf_test_push_u32(output, 0U)
  elf_test_push_u16(output, 64U)
  elf_test_push_u16(output, 0U)
  elf_test_push_u16(output, 0U)
  elf_test_push_u16(output, 64U)
  elf_test_push_u16(output, section_count.reinterpret_as_uint())
  elf_test_push_u16(output, (section_count - 1).reinterpret_as_uint())
  for byte in string_table {
    output.push(byte)
  }
  while output.length() < section_table_offset {
    output.push(0U.to_byte())
  }
  elf_test_push_section(output, 0U, 0U, 0UL, 0UL)
  for index in 0..<name_count {
    let name_offset = if overlap { index + 1 } else { 1 }
    elf_test_push_section(
      output,
      name_offset.reinterpret_as_uint(),
      8U,
      0UL,
      0UL,
    )
  }
  elf_test_push_section(output, 0U, 3U, 64UL, string_table.length().to_uint64())
  Bytes::from_array(output)
}

///|
test "ELF64 sample resolves section table and names with byte-exact roundtrip" {
  let bytes = @formats.sample_elf()
  let decoded = match @bin.decode(@formats.elf_codec(), bytes) {
    Ok(value) => value
    Err(error) => fail(error.render())
  }
  assert_eq(decoded.value.class, @formats.Elf64)
  assert_eq(decoded.value.endian, @bin.Little)
  assert_eq(decoded.value.machine, 62U)
  assert_eq(decoded.value.section_header_count, 3)
  assert_eq(decoded.value.section_name_index, 2)
  assert_eq(decoded.value.sections.length(), 3)
  assert_eq(decoded.value.sections[0].name, "")
  assert_eq(decoded.value.sections[1].name, ".text")
  assert_eq(decoded.value.sections[1].offset, 64UL)
  assert_eq(decoded.value.sections[1].size, 1UL)
  assert_eq(decoded.value.sections[2].name, ".shstrtab")
  assert_eq(@bin.encode(@formats.elf_codec(), decoded.value), Ok(bytes))
}

///|
test "ELF32 big-endian header without section table is supported" {
  let bytes = b"\x7fELF\x01\x02\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x01\x00\x03\x00\x00\x00\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x34\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
  let decoded = match @bin.decode(@formats.elf_codec(), bytes) {
    Ok(value) => value
    Err(error) => fail(error.render())
  }
  assert_eq(decoded.value.class, @formats.Elf32)
  assert_eq(decoded.value.endian, @bin.Big)
  assert_eq(decoded.value.machine, 3U)
  assert_eq(decoded.value.section_header_count, 0)
  assert_eq(decoded.value.sections.length(), 0)
  assert_eq(@bin.encode(@formats.elf_codec(), decoded.value), Ok(bytes))
}

///|
test "ELF extended section count and name index are resolved from section zero" {
  let source = @formats.sample_elf().to_array()
  source[60] = 0U.to_byte()
  source[61] = 0U.to_byte()
  source[62] = 0xffU.to_byte()
  source[63] = 0xffU.to_byte()
  source[120] = 3U.to_byte()
  source[128] = 2U.to_byte()
  let bytes = Bytes::from_array(source)
  let decoded = match @bin.decode(@formats.elf_codec(), bytes) {
    Ok(value) => value
    Err(error) => fail(error.render())
  }
  assert_eq(decoded.value.section_header_count, 3)
  assert_eq(decoded.value.section_name_index, 2)
  assert_eq(decoded.value.sections[1].name, ".text")
  assert_eq(@bin.encode(@formats.elf_codec(), decoded.value), Ok(bytes))
}

///|
test "ELF rejects section payloads outside file bounds" {
  let source = @formats.sample_elf().to_array()
  source[184] = 0xffU.to_byte()
  let result = @bin.decode(@formats.elf_codec(), Bytes::from_array(source))
  assert_true(result is Err({ kind: @bin.UnexpectedEof, .. }))
}

///|
test "ELF rejects section names outside the designated string table" {
  let source = @formats.sample_elf().to_array()
  source[152] = 0xffU.to_byte()
  let result = @bin.decode(@formats.elf_codec(), Bytes::from_array(source))
  assert_true(result is Err({ kind: @bin.InvalidValue, .. }))
}

///|
test "ELF rejects undersized section header entries before table iteration" {
  let source = @formats.sample_elf().to_array()
  source[58] = 1U.to_byte()
  source[59] = 0U.to_byte()
  let result = @bin.decode(@formats.elf_codec(), Bytes::from_array(source))
  assert_true(result is Err({ kind: @bin.InvalidValue, .. }))
}

///|
test "ELF rejects extended program-header counts outside the runtime model" {
  let source = @formats.sample_elf().to_array()
  source[56] = 0xffU.to_byte()
  source[57] = 0xffU.to_byte()
  source[132] = 0xffU.to_byte()
  source[133] = 0xffU.to_byte()
  source[134] = 0xffU.to_byte()
  source[135] = 0xffU.to_byte()
  assert_true(
    @bin.decode(@formats.elf_codec(), Bytes::from_array(source))
    is Err({ kind: @bin.LimitExceeded, .. }),
  )
}

///|
test "ELF caches repeated section names and bounds unique expansion" {
  match @bin.decode(@formats.elf_codec(), elf_test_name_fixture(false)) {
    Ok(decoded) => {
      assert_eq(decoded.value.sections.length(), 12)
      assert_eq(
        decoded.value.sections[1].name,
        "abcdefghijklmnopqrstuvwxyz01234",
      )
      assert_eq(decoded.value.sections[10].name, decoded.value.sections[1].name)
    }
    Err(error) => fail(error.render())
  }
  assert_true(
    @bin.decode(@formats.elf_codec(), elf_test_name_fixture(true))
    is Err({ kind: @bin.LimitExceeded, .. }),
  )
}
