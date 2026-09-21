///|
/// 有界二进制读取器。所有读取都会先检查范围。
pub struct Decoder {
  input : Bytes
  base_offset : Int
  mut offset : Int
  mut bit_offset : Int
  mut field_path : String
  depth : Int
  limits : Limits
  trace_entries : Array[TraceEntry]
}

///|
pub fn Decoder::new(input : Bytes, limits : Limits) -> Decoder {
  {
    input,
    base_offset: 0,
    offset: 0,
    bit_offset: 0,
    field_path: "",
    depth: 0,
    limits,
    trace_entries: [],
  }
}

///|
pub fn Decoder::offset(self : Decoder) -> Int {
  self.offset
}

///|
pub fn Decoder::absolute_offset(self : Decoder) -> Int {
  self.base_offset + self.offset
}

///|
pub fn Decoder::remaining(self : Decoder) -> Int {
  self.input.length() - self.offset
}

///|
pub fn Decoder::total_length(self : Decoder) -> Int {
  self.input.length()
}

///|
pub fn Decoder::path(self : Decoder) -> String {
  self.field_path
}

///|
pub fn Decoder::trace(self : Decoder) -> Array[TraceEntry] {
  self.trace_entries.copy()
}

///|
pub fn Decoder::max_collection_length(self : Decoder) -> Int {
  self.limits.max_collection_length
}

///|
pub fn Decoder::depth(self : Decoder) -> Int {
  self.depth
}

///|
fn Decoder::new_child(
  input : Bytes,
  base_offset : Int,
  path : String,
  depth : Int,
  limits : Limits,
) -> Decoder {
  {
    input,
    base_offset,
    offset: 0,
    bit_offset: 0,
    field_path: path,
    depth,
    limits,
    trace_entries: [],
  }
}

///|
fn Decoder::error(
  self : Decoder,
  kind : ErrorKind,
  message : String,
) -> BinError {
  BinError::new(kind, self.absolute_offset(), self.field_path, message)
}

///|
fn Decoder::ensure_byte_aligned(self : Decoder) -> Result[Unit, BinError] {
  if self.bit_offset == 0 {
    Ok(())
  } else {
    Err(self.error(Misaligned, "operation requires byte alignment"))
  }
}

///|
pub fn Decoder::take_bytes(
  self : Decoder,
  count : Int,
) -> Result[Bytes, BinError] {
  match self.ensure_byte_aligned() {
    Err(error) => Err(error)
    Ok(_) =>
      if count < 0 {
        Err(self.error(InvalidValue, "byte count cannot be negative"))
      } else if count > self.remaining() {
        Err(self.error(UnexpectedEof, "not enough bytes for requested field"))
      } else {
        let start = self.offset
        self.offset = self.offset + count
        Ok(self.input[start:self.offset].to_owned())
      }
  }
}

///|
pub fn Decoder::read_uint(
  self : Decoder,
  width : Int,
  endian : Endian,
) -> Result[UInt, BinError] {
  guard width == 1 || width == 2 || width == 4 else {
    return Err(self.error(Unsupported, "UInt width must be 1, 2, or 4"))
  }
  match self.take_bytes(width) {
    Err(error) => Err(error)
    Ok(bytes) => {
      let mut value = 0U
      match endian {
        Big =>
          for byte in bytes {
            value = (value << 8) | byte.to_uint()
          }
        Little =>
          for index, byte in bytes {
            value = value | (byte.to_uint() << (index * 8))
          }
      }
      Ok(value)
    }
  }
}

///|
pub fn Decoder::read_uint64(
  self : Decoder,
  endian : Endian,
) -> Result[UInt64, BinError] {
  match self.take_bytes(8) {
    Err(error) => Err(error)
    Ok(bytes) => {
      let mut value = 0UL
      match endian {
        Big =>
          for byte in bytes {
            value = (value << 8) | byte.to_uint64()
          }
        Little =>
          for index, byte in bytes {
            value = value | (byte.to_uint64() << (index * 8))
          }
      }
      Ok(value)
    }
  }
}

///|
pub fn Decoder::read_bits_msb(
  self : Decoder,
  width : Int,
) -> Result[UInt, BinError] {
  guard width > 0 && width <= 32 else {
    return Err(self.error(InvalidValue, "bit width must be in 1..32"))
  }
  let mut value = 0U
  for index = 0; index < width; index = index + 1 {
    if self.offset >= self.input.length() {
      return Err(
        self.error(UnexpectedEof, "not enough bits for requested field"),
      )
    }
    let byte = self.input[self.offset].to_uint()
    let shift = 7 - self.bit_offset
    value = (value << 1) | ((byte >> shift) & 1U)
    self.bit_offset = self.bit_offset + 1
    if self.bit_offset == 8 {
      self.bit_offset = 0
      self.offset = self.offset + 1
    }
  }
  Ok(value)
}

///|
pub fn Decoder::align_byte(self : Decoder) -> Unit {
  if self.bit_offset != 0 {
    self.bit_offset = 0
    self.offset = self.offset + 1
  }
}

///|
fn[T] Decoder::with_path(
  self : Decoder,
  name : String,
  action : () -> Result[T, BinError],
) -> Result[T, BinError] {
  let previous = self.field_path
  self.field_path = if previous == "" { name } else { previous + "." + name }
  let result = action()
  self.field_path = previous
  result
}

///|
fn Decoder::record(
  self : Decoder,
  path : String,
  kind : String,
  start : Int,
  end : Int,
  render_value : () -> String,
) -> Result[Unit, BinError] {
  if self.trace_entries.length() >= self.limits.max_trace_entries {
    Err(self.error(LimitExceeded, "trace entry limit exceeded"))
  } else {
    self.trace_entries.push({ path, kind, start, end, value: render_value(), })
    Ok(())
  }
}

///|
fn Decoder::append_trace(
  self : Decoder,
  entries : Array[TraceEntry],
) -> Result[Unit, BinError] {
  if entries.length() >
    self.limits.max_trace_entries - self.trace_entries.length() {
    return Err(self.error(LimitExceeded, "trace entry limit exceeded"))
  }
  for entry in entries {
    self.trace_entries.push(entry)
  }
  Ok(())
}
