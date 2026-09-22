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
