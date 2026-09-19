///|
pub fn u8() -> Codec[UInt] {
  uint_codec(1, Big)
}

///|
pub fn u16_be() -> Codec[UInt] {
  uint_codec(2, Big)
}

///|
pub fn u16_le() -> Codec[UInt] {
  uint_codec(2, Little)
}

///|
pub fn u32_be() -> Codec[UInt] {
  uint_codec(4, Big)
}

///|
pub fn u32_le() -> Codec[UInt] {
  uint_codec(4, Little)
}

///|
fn uint_codec(width : Int, endian : Endian) -> Codec[UInt] {
  Codec::make(
    fn(decoder) { decoder.read_uint(width, endian) },
    fn(encoder, value) { encoder.write_uint(value, width, endian) },
    kind=if width == 1 {
      "u8"
    } else if endian == Big {
      "u\{width * 8}be"
    } else {
      "u\{width * 8}le"
    },
    render=fn(value) { value.to_string() },
  )
}

///|
pub fn u64_be() -> Codec[UInt64] {
  uint64_codec(Big)
}

///|
pub fn u64_le() -> Codec[UInt64] {
  uint64_codec(Little)
}

///|
fn uint64_codec(endian : Endian) -> Codec[UInt64] {
  Codec::make(
    fn(decoder) { decoder.read_uint64(endian) },
    fn(encoder, value) { encoder.write_uint64(value, endian) },
    kind=if endian == Big { "u64be" } else { "u64le" },
    render=fn(value) { value.to_string() },
  )
}

///|
pub fn i8() -> Codec[Int] {
  u8().xmap(
    fn(value) {
      let integer = value.reinterpret_as_int()
      Ok(if value >= 128U { integer - 256 } else { integer })
    },
    fn(value) {
      if value < -128 || value > 127 {
        Err("i8 value out of range")
      } else {
        Ok(value.reinterpret_as_uint() & 0xffU)
      }
    },
    render=fn(value) { value.to_string() },
  )
}

///|
fn signed_codec(width : Int, endian : Endian) -> Codec[Int] {
  let unsigned = uint_codec(width, endian)
  unsigned.xmap(
    fn(value) {
      if width == 2 {
        let integer = value.reinterpret_as_int()
        Ok(if value >= 0x8000U { integer - 0x10000 } else { integer })
      } else {
        Ok(value.reinterpret_as_int())
      }
    },
    fn(value) {
      if width == 2 && (value < -32768 || value > 32767) {
        Err("i16 value out of range")
      } else {
        Ok(value.reinterpret_as_uint())
      }
    },
    render=fn(value) { value.to_string() },
  )
}

///|
pub fn i16_be() -> Codec[Int] {
  signed_codec(2, Big)
}

///|
pub fn i16_le() -> Codec[Int] {
  signed_codec(2, Little)
}

///|
pub fn i32_be() -> Codec[Int] {
  signed_codec(4, Big)
}

///|
pub fn i32_le() -> Codec[Int] {
  signed_codec(4, Little)
}

///|
pub fn i64_be() -> Codec[Int64] {
  u64_be().xmap(
    fn(value) { Ok(value.reinterpret_as_int64()) },
    fn(value) { Ok(value.reinterpret_as_uint64()) },
    render=fn(value) { value.to_string() },
  )
}

///|
pub fn i64_le() -> Codec[Int64] {
  u64_le().xmap(
    fn(value) { Ok(value.reinterpret_as_int64()) },
    fn(value) { Ok(value.reinterpret_as_uint64()) },
    render=fn(value) { value.to_string() },
  )
}

///|
pub fn bytes_fixed(count : Int) -> Codec[Bytes] {
  Codec::make(
    fn(decoder) { decoder.take_bytes(count) },
    fn(encoder, value) {
      if value.length() != count {
        Err(
          BinError::new(
            InvalidValue,
            encoder.length(),
            "",
            "byte string length does not match fixed field length",
          ),
        )
      } else {
        encoder.write_bytes(value[:])
      }
    },
    kind="bytes[\{count}]",
    render=fn(value) { bytes_to_hex_preview(value, 32) },
  )
}

///|
pub fn magic(expected : Bytes) -> Codec[Unit] {
  bytes_fixed(expected.length()).xmap(
    fn(actual) {
      if actual == expected {
        Ok(())
      } else {
        Err("magic bytes mismatch")
      }
    },
    fn(_) { Ok(expected) },
    render=fn(_) { bytes_to_hex(expected) },
  )
}

///|
pub fn bits_msb(width : Int) -> Codec[UInt] {
  Codec::make(
    fn(decoder) { decoder.read_bits_msb(width) },
    fn(encoder, value) { encoder.write_bits_msb(value, width) },
    kind="bits\{width}msb",
    render=fn(value) { value.to_string() },
  )
}

///|
pub fn bool8() -> Codec[Bool] {
  u8().xmap(
    fn(value) {
      match value {
        0U => Ok(false)
        1U => Ok(true)
        _ => Err("boolean byte must be 0 or 1")
      }
    },
    fn(value) { Ok(if value { 1U } else { 0U }) },
    render=fn(value) { if value { "true" } else { "false" } },
  )
}

///|
pub fn bytes_to_hex(bytes : Bytes) -> String {
  let parts : Array[String] = []
  for byte in bytes {
    parts.push(byte.to_hex())
  }
  parts.join(" ")
}

///|
/// 为检查轨迹生成有界十六进制预览，避免大字段制造巨量日志。
pub fn bytes_to_hex_preview(bytes : Bytes, max_bytes : Int) -> String {
  let limit = if max_bytes < 0 {
    0
  } else if max_bytes < bytes.length() {
    max_bytes
  } else {
    bytes.length()
  }
  let parts : Array[String] = []
  for index in 0..<limit {
    parts.push(bytes[index].to_hex())
  }
  let prefix = parts.join(" ")
  if limit < bytes.length() {
    prefix + " … (+\{bytes.length() - limit} bytes)"
  } else {
    prefix
  }
}
