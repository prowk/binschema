///|
pub(all) enum ElfClass {
  Elf32
  Elf64
} derive(Eq, Debug, ToJson)

///|
pub extend ElfClass with Eq::{not_equal, equal}

///|
pub extend ElfClass with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ElfClass with ToJson::{to_json}

///|
pub fn ElfClass::name(self : ElfClass) -> String {
  match self {
    Elf32 => "ELF32"
    Elf64 => "ELF64"
  }
}

///|
pub(all) struct ElfSection {
  name : String
  name_offset : UInt
  section_type : UInt
  flags : UInt64
  address : UInt64
  offset : UInt64
  size : UInt64
  link : UInt
  info : UInt
  alignment : UInt64
  entry_size : UInt64
} derive(Eq, Debug, ToJson)

///|
pub extend ElfSection with Eq::{not_equal, equal}

///|
pub extend ElfSection with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ElfSection with ToJson::{to_json}

///|
/// ELF is exposed as a byte-preserving structural view. The parsed metadata must
/// continue to match raw before encoding, so edits can never be silently ignored.
pub(all) struct ElfFile {
  class : ElfClass
  endian : @bin.Endian
  os_abi : UInt
  abi_version : UInt
  file_type : UInt
  machine : UInt
  version : UInt
  entry : UInt64
  program_header_offset : UInt64
  section_header_offset : UInt64
  flags : UInt
  header_size : Int
  program_header_entry_size : Int
  program_header_count : Int
  section_header_entry_size : Int
  section_header_count : Int
  section_name_index : Int
  sections : Array[ElfSection]
  raw : Bytes
} derive(Eq, Debug, ToJson)

///|
pub extend ElfFile with Eq::{not_equal, equal}

///|
pub extend ElfFile with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ElfFile with ToJson::{to_json}

///|
fn elf_error(
  kind : @bin.ErrorKind,
  offset : Int,
  path : String,
  message : String,
) -> @bin.BinError {
  @bin.BinError::new(kind, offset, path, message)
}

///|
fn elf_need(
  input : BytesView,
  offset : Int,
  count : Int,
  path : String,
) -> Result[BytesView, @bin.BinError] {
  if offset < 0 || count < 0 || offset > input.length() ||
    count > input.length() - offset {
    Err(
      elf_error(
        @bin.UnexpectedEof,
        if offset < 0 { 0 } else { offset },
        path,
        "ELF field exceeds file bounds",
      ),
    )
  } else {
    Ok(input[offset:offset + count])
  }
}

///|
fn elf_u16_at(
  input : BytesView,
  offset : Int,
  endian : @bin.Endian,
  path : String,
) -> Result[UInt, @bin.BinError] {
  let bytes = match elf_need(input, offset, 2, path) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  Ok(
    match endian {
      @bin.Little => bytes[0].to_uint() | (bytes[1].to_uint() << 8)
      @bin.Big => (bytes[0].to_uint() << 8) | bytes[1].to_uint()
    },
  )
}

///|
fn elf_u32_at(
  input : BytesView,
  offset : Int,
  endian : @bin.Endian,
  path : String,
) -> Result[UInt, @bin.BinError] {
  let bytes = match elf_need(input, offset, 4, path) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let mut value = 0U
  match endian {
    @bin.Big =>
      for byte in bytes {
        value = (value << 8) | byte.to_uint()
      }
    @bin.Little =>
      for index, byte in bytes {
        value = value | (byte.to_uint() << (index * 8))
      }
  }
  Ok(value)
}

///|
fn elf_u64_at(
  input : BytesView,
  offset : Int,
  endian : @bin.Endian,
  path : String,
) -> Result[UInt64, @bin.BinError] {
  let bytes = match elf_need(input, offset, 8, path) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let mut value = 0UL
  match endian {
    @bin.Big =>
      for byte in bytes {
        value = (value << 8) | byte.to_uint64()
      }
    @bin.Little =>
      for index, byte in bytes {
        value = value | (byte.to_uint64() << (index * 8))
      }
  }
  Ok(value)
}

///|
fn elf_uint_as_u64(value : UInt) -> UInt64 {
  value.to_uint64()
}

///|
fn elf_bounded_int(
  value : UInt64,
  offset : Int,
  path : String,
  what : String,
) -> Result[Int, @bin.BinError] {
  if value > 0x7fffffffUL {
    Err(
      elf_error(
        @bin.LimitExceeded,
        offset,
        path,
        what + " exceeds this runtime's bounded file model",
      ),
    )
  } else {
    Ok(value.to_int())
  }
}

///|
fn elf_range(
  input_length : Int,
  offset : UInt64,
  size : UInt64,
  path : String,
) -> Result[(Int, Int), @bin.BinError] {
  let total = input_length.to_uint64()
  if offset > total || size > total - offset {
    return Err(
      elf_error(
        @bin.UnexpectedEof,
        if offset > 0x7fffffffUL { input_length } else { offset.to_int() },
        path,
        "ELF range exceeds file bounds",
      ),
    )
  }
  let start = match elf_bounded_int(offset, 0, path, "ELF offset") {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let length = match elf_bounded_int(size, start, path, "ELF size") {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  Ok((start, length))
}

///|
fn elf_section_at(
  input : BytesView,
  table_offset : Int,
  entry_size : Int,
  index : Int,
  class : ElfClass,
  endian : @bin.Endian,
) -> Result[ElfSection, @bin.BinError] {
  let base = table_offset + index * entry_size
  let path = "sections.\{index}"
  let name_offset = match elf_u32_at(input, base, endian, path + ".name_offset") {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let section_type = match elf_u32_at(input, base + 4, endian, path + ".type") {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let (flags, address, offset, size, link_offset, info_offset, align_offset, entsize_offset) = match class {
    Elf32 => {
      let flags = match elf_u32_at(input, base + 8, endian, path + ".flags") {
        Ok(value) => elf_uint_as_u64(value)
        Err(error) => return Err(error)
      }
      let address = match elf_u32_at(input, base + 12, endian, path + ".address") {
        Ok(value) => elf_uint_as_u64(value)
        Err(error) => return Err(error)
      }
      let offset = match elf_u32_at(input, base + 16, endian, path + ".offset") {
        Ok(value) => elf_uint_as_u64(value)
        Err(error) => return Err(error)
      }
      let size = match elf_u32_at(input, base + 20, endian, path + ".size") {
        Ok(value) => elf_uint_as_u64(value)
        Err(error) => return Err(error)
      }
      (flags, address, offset, size, 24, 28, 32, 36)
    }
    Elf64 => {
      let flags = match elf_u64_at(input, base + 8, endian, path + ".flags") {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      let address = match elf_u64_at(input, base + 16, endian, path + ".address") {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      let offset = match elf_u64_at(input, base + 24, endian, path + ".offset") {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      let size = match elf_u64_at(input, base + 32, endian, path + ".size") {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      (flags, address, offset, size, 40, 44, 48, 56)
    }
  }
  let link = match elf_u32_at(input, base + link_offset, endian, path + ".link") {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let info = match elf_u32_at(input, base + info_offset, endian, path + ".info") {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let alignment = match class {
    Elf32 =>
      match elf_u32_at(input, base + align_offset, endian, path + ".alignment") {
        Ok(value) => elf_uint_as_u64(value)
        Err(error) => return Err(error)
      }
    Elf64 =>
      match elf_u64_at(input, base + align_offset, endian, path + ".alignment") {
        Ok(value) => value
        Err(error) => return Err(error)
      }
  }
  let entry_size = match class {
    Elf32 =>
      match elf_u32_at(input, base + entsize_offset, endian, path + ".entry_size") {
        Ok(value) => elf_uint_as_u64(value)
        Err(error) => return Err(error)
      }
    Elf64 =>
      match elf_u64_at(input, base + entsize_offset, endian, path + ".entry_size") {
        Ok(value) => value
        Err(error) => return Err(error)
      }
  }
  Ok({
    name: "",
    name_offset,
    section_type,
    flags,
    address,
    offset,
    size,
    link,
    info,
    alignment,
    entry_size,
  })
}

///|
fn elf_string_at(
  table : BytesView,
  offset : UInt,
  file_offset : Int,
) -> Result[String, @bin.BinError] {
  let start = offset.reinterpret_as_int()
  if start < 0 || start >= table.length() {
    return Err(
      elf_error(
        @bin.InvalidValue,
        file_offset,
        "sections.name",
        "ELF section name offset is outside the section-name string table",
      ),
    )
  }
  if start == 0 {
    return Ok("")
  }
  let bytes : Array[Byte] = []
  let mut index = start
  while index < table.length() && table[index] != 0U.to_byte() {
    bytes.push(table[index])
    index += 1
  }
  if index >= table.length() {
    return Err(
      elf_error(
        @bin.InvalidValue,
        file_offset + start,
        "sections.name",
        "ELF section name is not NUL terminated",
      ),
    )
  }
  Ok(@utf8.decode_lossy(Bytes::from_array(bytes)[:]))
}

///|
fn parse_elf(raw : Bytes, max_sections : Int) -> Result[ElfFile, @bin.BinError] {
  let input = raw[:]
  if input.length() < 16 {
    return Err(elf_error(@bin.UnexpectedEof, 0, "ident", "ELF identification is truncated"))
  }
  if input[0] != 0x7fU.to_byte() ||
    input[1] != b'E' ||
    input[2] != b'L' ||
    input[3] != b'F' {
    return Err(elf_error(@bin.InvalidValue, 0, "magic", "ELF magic bytes mismatch"))
  }
  let class = match input[4].to_uint() {
    1U => Elf32
    2U => Elf64
    _ => return Err(elf_error(@bin.Unsupported, 4, "class", "unsupported ELF class"))
  }
  let endian = match input[5].to_uint() {
    1U => @bin.Little
    2U => @bin.Big
    _ => return Err(elf_error(@bin.Unsupported, 5, "data", "unsupported ELF byte order"))
  }
  if input[6].to_uint() != 1U {
    return Err(elf_error(@bin.InvalidValue, 6, "ident_version", "unsupported ELF identification version"))
  }
  let minimum_header = match class {
    Elf32 => 52
    Elf64 => 64
  }
  if input.length() < minimum_header {
    return Err(elf_error(@bin.UnexpectedEof, 0, "header", "ELF header is truncated"))
  }
  let os_abi = input[7].to_uint()
  let abi_version = input[8].to_uint()
  let file_type = match elf_u16_at(input, 16, endian, "type") {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let machine = match elf_u16_at(input, 18, endian, "machine") {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let version = match elf_u32_at(input, 20, endian, "version") {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if version != 1U {
    return Err(elf_error(@bin.InvalidValue, 20, "version", "unsupported ELF header version"))
  }
  let (entry, program_header_offset, section_header_offset, flags_offset, header_size_offset) = match class {
    Elf32 => {
      let entry = match elf_u32_at(input, 24, endian, "entry") {
        Ok(value) => elf_uint_as_u64(value)
        Err(error) => return Err(error)
      }
      let phoff = match elf_u32_at(input, 28, endian, "program_header_offset") {
        Ok(value) => elf_uint_as_u64(value)
        Err(error) => return Err(error)
      }
      let shoff = match elf_u32_at(input, 32, endian, "section_header_offset") {
        Ok(value) => elf_uint_as_u64(value)
        Err(error) => return Err(error)
      }
      (entry, phoff, shoff, 36, 40)
    }
    Elf64 => {
      let entry = match elf_u64_at(input, 24, endian, "entry") {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      let phoff = match elf_u64_at(input, 32, endian, "program_header_offset") {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      let shoff = match elf_u64_at(input, 40, endian, "section_header_offset") {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      (entry, phoff, shoff, 48, 52)
    }
  }
  let flags = match elf_u32_at(input, flags_offset, endian, "flags") {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let header_size = match elf_u16_at(input, header_size_offset, endian, "header_size") {
    Ok(value) => value.reinterpret_as_int()
    Err(error) => return Err(error)
  }
  if header_size < minimum_header || header_size > input.length() {
    return Err(elf_error(@bin.InvalidValue, header_size_offset, "header_size", "ELF header size is inconsistent with class or file length"))
  }
  let program_header_entry_size = match elf_u16_at(input, header_size_offset + 2, endian, "program_header_entry_size") {
    Ok(value) => value.reinterpret_as_int()
    Err(error) => return Err(error)
  }
  let raw_program_header_count = match elf_u16_at(input, header_size_offset + 4, endian, "program_header_count") {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let section_header_entry_size = match elf_u16_at(input, header_size_offset + 6, endian, "section_header_entry_size") {
    Ok(value) => value.reinterpret_as_int()
    Err(error) => return Err(error)
  }
  let raw_section_header_count = match elf_u16_at(input, header_size_offset + 8, endian, "section_header_count") {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let raw_section_name_index = match elf_u16_at(input, header_size_offset + 10, endian, "section_name_index") {
    Ok(value) => value
    Err(error) => return Err(error)
  }

  let expected_section_entry = match class {
    Elf32 => 40
    Elf64 => 64
  }
  let expected_program_entry = match class {
    Elf32 => 32
    Elf64 => 56
  }
  let sections : Array[ElfSection] = []
  let mut section_zero : ElfSection? = None
  let mut section_header_count = 0
  let mut section_name_index = raw_section_name_index.reinterpret_as_int()

  if section_header_offset == 0UL {
    if raw_section_header_count != 0U || raw_section_name_index != 0U {
      return Err(elf_error(@bin.InvalidValue, header_size_offset + 8, "sections", "ELF declares section metadata without a section header table"))
    }
  } else {
    if section_header_entry_size < expected_section_entry {
      return Err(elf_error(@bin.InvalidValue, header_size_offset + 6, "section_header_entry_size", "ELF section header entry is smaller than the class-defined structure"))
    }
    let table_offset = match elf_bounded_int(section_header_offset, header_size_offset + 6, "section_header_offset", "ELF section table offset") {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    if table_offset > input.length() ||
      section_header_entry_size > input.length() - table_offset {
      return Err(elf_error(@bin.UnexpectedEof, table_offset, "sections.0", "ELF section header zero exceeds file bounds"))
    }
    let zero = match elf_section_at(input, table_offset, section_header_entry_size, 0, class, endian) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    section_zero = Some(zero)
    section_header_count = if raw_section_header_count == 0U {
      match elf_bounded_int(zero.size, table_offset, "section_header_count", "extended ELF section count") {
        Ok(value) => value
        Err(error) => return Err(error)
      }
    } else {
      raw_section_header_count.reinterpret_as_int()
    }
    if section_header_count <= 0 {
      return Err(elf_error(@bin.InvalidValue, table_offset, "section_header_count", "ELF section table must contain section zero"))
    }
    if section_header_count > max_sections {
      return Err(elf_error(@bin.LimitExceeded, table_offset, "sections", "ELF section count exceeds configured collection limit"))
    }
    if section_header_count >
      (input.length() - table_offset) / section_header_entry_size {
      return Err(elf_error(@bin.UnexpectedEof, table_offset, "sections", "ELF section header table exceeds file bounds"))
    }
    for index in 0..<section_header_count {
      let section = match elf_section_at(input, table_offset, section_header_entry_size, index, class, endian) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      if section.section_type != 8U && section.size != 0UL {
        match elf_range(input.length(), section.offset, section.size, "sections.\{index}.payload") {
          Ok(_) => ()
          Err(error) => return Err(error)
        }
      }
      sections.push(section)
    }
    if raw_section_name_index == 0xffffU {
      section_name_index = zero.link.reinterpret_as_int()
    }
    if section_name_index < 0 || section_name_index >= section_header_count {
      return Err(elf_error(@bin.InvalidValue, table_offset, "section_name_index", "ELF section-name string table index is outside the section table"))
    }
    if section_name_index != 0 {
      let string_section = sections[section_name_index]
      if string_section.section_type != 3U {
        return Err(elf_error(@bin.InvalidValue, table_offset + section_name_index * section_header_entry_size, "section_name_index", "ELF section-name table is not SHT_STRTAB"))
      }
      let (string_offset, string_size) = match elf_range(input.length(), string_section.offset, string_section.size, "section_name_table") {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      let table = input[string_offset:string_offset + string_size]
      if table.length() > 0 &&
        (table[0] != 0U.to_byte() || table[table.length() - 1] != 0U.to_byte()) {
        return Err(elf_error(@bin.InvalidValue, string_offset, "section_name_table", "ELF string table must begin and end with NUL"))
      }
      for index in 0..<sections.length() {
        let section = sections[index]
        let name = if table.length() == 0 {
          if section.name_offset == 0U {
            ""
          } else {
            return Err(elf_error(@bin.InvalidValue, string_offset, "sections.\{index}.name", "non-zero ELF section name references an empty string table"))
          }
        } else {
          match elf_string_at(table, section.name_offset, string_offset) {
            Ok(value) => value
            Err(error) => return Err(error)
          }
        }
        sections[index] = {
          name,
          name_offset: section.name_offset,
          section_type: section.section_type,
          flags: section.flags,
          address: section.address,
          offset: section.offset,
          size: section.size,
          link: section.link,
          info: section.info,
          alignment: section.alignment,
          entry_size: section.entry_size,
        }
      }
    }
  }

  let program_header_count = if raw_program_header_count == 0xffffU {
    match section_zero {
      Some(zero) => zero.info.reinterpret_as_int()
      None =>
        return Err(elf_error(@bin.InvalidValue, header_size_offset + 4, "program_header_count", "extended ELF program-header count requires section header zero"))
    }
  } else {
    raw_program_header_count.reinterpret_as_int()
  }
  if program_header_count > max_sections {
    return Err(elf_error(@bin.LimitExceeded, header_size_offset + 4, "program_headers", "ELF program-header count exceeds configured collection limit"))
  }
  if program_header_count > 0 {
    if program_header_offset == 0UL {
      return Err(elf_error(@bin.InvalidValue, header_size_offset + 4, "program_header_offset", "ELF declares program headers with zero table offset"))
    }
    if program_header_entry_size < expected_program_entry {
      return Err(elf_error(@bin.InvalidValue, header_size_offset + 2, "program_header_entry_size", "ELF program header entry is smaller than the class-defined structure"))
    }
    let phoff = match elf_bounded_int(program_header_offset, header_size_offset + 2, "program_header_offset", "ELF program table offset") {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    if phoff > input.length() ||
      program_header_count > (input.length() - phoff) / program_header_entry_size {
      return Err(elf_error(@bin.UnexpectedEof, phoff, "program_headers", "ELF program header table exceeds file bounds"))
    }
  }

  Ok({
    class,
    endian,
    os_abi,
    abi_version,
    file_type,
    machine,
    version,
    entry,
    program_header_offset,
    section_header_offset,
    flags,
    header_size,
    program_header_entry_size,
    program_header_count,
    section_header_entry_size,
    section_header_count,
    section_name_index,
    sections,
    raw,
  })
}

///|
fn elf_u16_codec(endian : @bin.Endian) -> @bin.Codec[UInt] {
  match endian {
    @bin.Little => @bin.u16_le()
    @bin.Big => @bin.u16_be()
  }
}

///|
fn elf_u32_codec(endian : @bin.Endian) -> @bin.Codec[UInt] {
  match endian {
    @bin.Little => @bin.u32_le()
    @bin.Big => @bin.u32_be()
  }
}

///|
fn elf_u64_codec(endian : @bin.Endian) -> @bin.Codec[UInt64] {
  match endian {
    @bin.Little => @bin.u64_le()
    @bin.Big => @bin.u64_be()
  }
}

///|
fn elf_trace_header(
  decoder : @bin.Decoder,
  value : ElfFile,
) -> Result[Unit, @bin.BinError] {
  let results : Array[Result[Unit, @bin.BinError]] = []
  results.push(@bin.magic(b"\x7fELF").named("magic").decode_from(decoder).map(fn(_) { () }))
  for name in ["class", "data", "ident_version", "os_abi", "abi_version"] {
    results.push(@bin.u8().named(name).decode_from(decoder).map(fn(_) { () }))
  }
  results.push(@bin.bytes_fixed(7).named("ident_padding").decode_from(decoder).map(fn(_) { () }))
  for result in results {
    match result {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
  }
  let u16 = elf_u16_codec(value.endian)
  let u32 = elf_u32_codec(value.endian)
  match u16.named("type").decode_from(decoder) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  match u16.named("machine").decode_from(decoder) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  match u32.named("version").decode_from(decoder) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  match value.class {
    Elf32 => {
      for name in ["entry", "program_header_offset", "section_header_offset"] {
        match u32.named(name).decode_from(decoder) {
          Ok(_) => ()
          Err(error) => return Err(error)
        }
      }
    }
    Elf64 => {
      let u64 = elf_u64_codec(value.endian)
      for name in ["entry", "program_header_offset", "section_header_offset"] {
        match u64.named(name).decode_from(decoder) {
          Ok(_) => ()
          Err(error) => return Err(error)
        }
      }
    }
  }
  match u32.named("flags").decode_from(decoder) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  for name in [
    "header_size",
    "program_header_entry_size",
    "program_header_count",
    "section_header_entry_size",
    "section_header_count",
    "section_name_index",
  ] {
    match u16.named(name).decode_from(decoder) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
  }
  if value.header_size > decoder.offset() {
    match
      @bin.bytes_fixed(value.header_size - decoder.offset())
      .named("header_extra")
      .decode_from(decoder) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
  }
  if decoder.remaining() > 0 {
    match @bin.remaining_bytes().named("file_body").decode_from(decoder) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
  }
  Ok(())
}

///|
fn elf_schema() -> @bin.SchemaNode {
  @bin.SchemaNode::node(
    "elf",
    [
      @bin.SchemaNode::node("ident", [
        @bin.SchemaNode::leaf("bytes[4]").with_name("magic"),
        @bin.SchemaNode::leaf("u8").with_name("class"),
        @bin.SchemaNode::leaf("u8").with_name("data"),
        @bin.SchemaNode::leaf("u8").with_name("version"),
        @bin.SchemaNode::leaf("u8").with_name("os_abi"),
        @bin.SchemaNode::leaf("u8").with_name("abi_version"),
      ]),
      @bin.SchemaNode::node("header", [
        @bin.SchemaNode::leaf("u16[endian]").with_name("type"),
        @bin.SchemaNode::leaf("u16[endian]").with_name("machine"),
        @bin.SchemaNode::leaf("u32[endian]").with_name("version"),
        @bin.SchemaNode::leaf("addr[class,endian]").with_name("entry"),
        @bin.SchemaNode::leaf("offset[class,endian]").with_name("program_header_offset"),
        @bin.SchemaNode::leaf("offset[class,endian]").with_name("section_header_offset"),
        @bin.SchemaNode::leaf("u32[endian]").with_name("flags"),
        @bin.SchemaNode::leaf("u16[endian]").with_name("header_size"),
        @bin.SchemaNode::leaf("u16[endian]").with_name("program_header_entry_size"),
        @bin.SchemaNode::leaf("u16[endian]").with_name("program_header_count"),
        @bin.SchemaNode::leaf("u16[endian]").with_name("section_header_entry_size"),
        @bin.SchemaNode::leaf("u16[endian]").with_name("section_header_count"),
        @bin.SchemaNode::leaf("u16[endian]").with_name("section_name_index"),
      ]),
      @bin.SchemaNode::node("sections", [
        @bin.SchemaNode::node("section-header", [
          @bin.SchemaNode::leaf("u32[endian]").with_name("name_offset"),
          @bin.SchemaNode::leaf("u32[endian]").with_name("type"),
          @bin.SchemaNode::leaf("word[class,endian]").with_name("flags"),
          @bin.SchemaNode::leaf("addr[class,endian]").with_name("address"),
          @bin.SchemaNode::leaf("offset[class,endian]").with_name("offset"),
          @bin.SchemaNode::leaf("word[class,endian]").with_name("size"),
          @bin.SchemaNode::leaf("u32[endian]").with_name("link"),
          @bin.SchemaNode::leaf("u32[endian]").with_name("info"),
          @bin.SchemaNode::leaf("word[class,endian]").with_name("alignment"),
          @bin.SchemaNode::leaf("word[class,endian]").with_name("entry_size"),
        ]),
      ], constraints=[
        "table=random-access", "names=e_shstrndx string-table", "max_count=runtime-limit",
      ]),
    ],
    constraints=[
      "classes=ELF32|ELF64",
      "endianness=EI_DATA",
      "extended-section-numbering=supported",
      "encode=byte-preserving-validated-view",
    ],
  )
}

///|
pub fn elf_codec() -> @bin.Codec[ElfFile] {
  @bin.Codec::make(
    fn(decoder) {
      let raw = match decoder.view_at(0, decoder.total_length()) {
        Ok(value) => value.to_owned()
        Err(error) => return Err(error)
      }
      let value = match parse_elf(raw, decoder.max_collection_length()) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      match elf_trace_header(decoder, value) {
        Ok(_) => Ok(value)
        Err(error) => Err(error)
      }
    },
    fn(encoder, value) {
      if value.sections.length() > encoder.max_collection_length() {
        return Err(
          elf_error(
            @bin.LimitExceeded,
            encoder.length(),
            "sections",
            "ELF section count exceeds configured collection limit",
          ),
        )
      }
      let parsed = match parse_elf(value.raw, encoder.max_collection_length()) {
        Ok(parsed) => parsed
        Err(error) => return Err(error)
      }
      if parsed != value {
        return Err(
          elf_error(
            @bin.InvalidValue,
            encoder.length(),
            "elf",
            "ELF metadata no longer matches the byte-preserving raw image",
          ),
        )
      }
      encoder.write_bytes(value.raw[:])
    },
    kind="elf",
    render=fn(value) {
      "\{value.class.name()} with \{value.sections.length()} sections"
    },
    schema=elf_schema(),
  )
}

///|
fn elf_sample_u16(output : Array[Byte], value : UInt) -> Unit {
  output.push(value.to_byte())
  output.push((value >> 8).to_byte())
}

///|
fn elf_sample_u32(output : Array[Byte], value : UInt) -> Unit {
  for index in 0..<4 {
    output.push((value >> (index * 8)).to_byte())
  }
}

///|
fn elf_sample_u64(output : Array[Byte], value : UInt64) -> Unit {
  for index in 0..<8 {
    output.push((value >> (index * 8)).to_byte())
  }
}

///|
fn elf_sample_section64(
  output : Array[Byte],
  name : UInt,
  section_type : UInt,
  flags : UInt64,
  address : UInt64,
  offset : UInt64,
  size : UInt64,
  link : UInt,
  info : UInt,
  alignment : UInt64,
  entry_size : UInt64,
) -> Unit {
  elf_sample_u32(output, name)
  elf_sample_u32(output, section_type)
  elf_sample_u64(output, flags)
  elf_sample_u64(output, address)
  elf_sample_u64(output, offset)
  elf_sample_u64(output, size)
  elf_sample_u32(output, link)
  elf_sample_u32(output, info)
  elf_sample_u64(output, alignment)
  elf_sample_u64(output, entry_size)
}

///|
/// Minimal ELF64 little-endian relocatable object with .text and .shstrtab.
pub fn sample_elf() -> Bytes {
  let output = b"\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00".to_array()
  elf_sample_u16(output, 1U)
  elf_sample_u16(output, 62U)
  elf_sample_u32(output, 1U)
  elf_sample_u64(output, 0UL)
  elf_sample_u64(output, 0UL)
  elf_sample_u64(output, 88UL)
  elf_sample_u32(output, 0U)
  elf_sample_u16(output, 64U)
  elf_sample_u16(output, 0U)
  elf_sample_u16(output, 0U)
  elf_sample_u16(output, 64U)
  elf_sample_u16(output, 3U)
  elf_sample_u16(output, 2U)
  output.push(0xc3U.to_byte())
  for byte in b"\x00.text\x00.shstrtab\x00" {
    output.push(byte)
  }
  while output.length() < 88 {
    output.push(0U.to_byte())
  }
  elf_sample_section64(output, 0U, 0U, 0UL, 0UL, 0UL, 0UL, 0U, 0U, 0UL, 0UL)
  elf_sample_section64(output, 1U, 1U, 6UL, 0UL, 64UL, 1UL, 0U, 0U, 1UL, 0UL)
  elf_sample_section64(output, 7U, 3U, 0UL, 0UL, 65UL, 17UL, 0U, 0U, 1UL, 0UL)
  Bytes::from_array(output)
}
