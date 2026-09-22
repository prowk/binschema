///|
/// 与 Decoder 对称的有界二进制写入器。
pub struct Encoder {
  buffer : @buffer.Buffer
  mut bit_buffer : UInt
  mut bit_count : Int
  mut field_path : String
  limits : Limits
}

///|
pub fn Encoder::new(limits : Limits) -> Encoder {
  {
    buffer: @buffer.Buffer(),
    bit_buffer: 0U,
    bit_count: 0,
    field_path: "",
    limits,
  }
}

///|
pub fn Encoder::path(self : Encoder) -> String {
  self.field_path
}

///|
pub fn Encoder::max_collection_length(self : Encoder) -> Int {
  self.limits.max_collection_length
}

///|
fn[T] Encoder::with_path(
  self : Encoder,
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
fn Encoder::error(
  self : Encoder,
  kind : ErrorKind,
  message : String,
) -> BinError {
  BinError::new(kind, self.length(), self.field_path, message)
}

///|
pub fn Encoder::length(self : Encoder) -> Int {
  self.buffer.length()
}

///|
fn Encoder::ensure_capacity(
  self : Encoder,
  additional : Int,
) -> Result[Unit, BinError] {
  if additional < 0 ||
    self.length() > self.limits.max_output_bytes ||
    additional > self.limits.max_output_bytes - self.length() {
    Err(self.error(LimitExceeded, "encoded output exceeds max_output_bytes"))
  } else {
    Ok(())
  }
}

///|
fn Encoder::write_zeroes(
  self : Encoder,
  count : Int,
) -> Result[Unit, BinError] {
  if self.bit_count != 0 {
    return Err(self.error(Misaligned, "operation requires byte alignment"))
  }
  match self.ensure_capacity(count) {
    Err(error) => Err(error)
    Ok(_) => {
      for _ in 0..<count {
        self.buffer.write_byte(0U.to_byte())
      }
      Ok(())
    }
  }
}

///|
pub fn Encoder::write_bytes(
  self : Encoder,
  bytes : BytesView,
) -> Result[Unit, BinError] {
  if self.bit_count != 0 {
    return Err(self.error(Misaligned, "operation requires byte alignment"))
  }
  match self.ensure_capacity(bytes.length()) {
    Err(error) => Err(error)
    Ok(_) => {
      self.buffer.write_bytes(bytes)
      Ok(())
    }
  }
}

///|
pub fn Encoder::write_uint(
  self : Encoder,
  value : UInt,
  width : Int,
  endian : Endian,
) -> Result[Unit, BinError] {
  guard width == 1 || width == 2 || width == 4 else {
    return Err(self.error(Unsupported, "UInt width must be 1, 2, or 4"))
  }
  if (width == 1 && value > 0xffU) ||
    (width == 2 && value > 0xffffU) {
    return Err(
      self.error(InvalidValue, "unsigned value does not fit requested width"),
    )
  }
  let output : Array[Byte] = []
  match endian {
    Big =>
      for index = 0; index < width; index = index + 1 {
        let shift = (width - index - 1) * 8
        output.push((value >> shift).to_byte())
      }
    Little =>
      for index = 0; index < width; index = index + 1 {
        output.push((value >> (index * 8)).to_byte())
      }
  }
  self.write_bytes(Bytes::from_array(output)[:])
}

///|
pub fn Encoder::write_uint64(
  self : Encoder,
  value : UInt64,
  endian : Endian,
) -> Result[Unit, BinError] {
  let output : Array[Byte] = []
  match endian {
    Big =>
      for index = 0; index < 8; index = index + 1 {
        output.push((value >> ((7 - index) * 8)).to_byte())
      }
    Little =>
      for index = 0; index < 8; index = index + 1 {
        output.push((value >> (index * 8)).to_byte())
      }
  }
  self.write_bytes(Bytes::from_array(output)[:])
}

///|
pub fn Encoder::write_bits_msb(
  self : Encoder,
  value : UInt,
  width : Int,
) -> Result[Unit, BinError] {
  guard width > 0 && width <= 32 else {
    return Err(self.error(InvalidValue, "bit width must be in 1..32"))
  }
  if width < 32 && value >= 1U << width {
    return Err(
      self.error(InvalidValue, "value does not fit requested bit width"),
    )
  }
  for index = width - 1; index >= 0; index = index - 1 {
    self.bit_buffer = (self.bit_buffer << 1) | ((value >> index) & 1U)
    self.bit_count = self.bit_count + 1
    if self.bit_count == 8 {
      match self.ensure_capacity(1) {
        Err(error) => return Err(error)
        Ok(_) => self.buffer.write_byte(self.bit_buffer.to_byte())
      }
      self.bit_buffer = 0U
      self.bit_count = 0
    }
  }
  Ok(())
}

///|
pub fn Encoder::align_byte(
  self : Encoder,
  fill_bit? : Bool = false,
) -> Result[Unit, BinError] {
  if self.bit_count == 0 {
    return Ok(())
  }
  while self.bit_count < 8 {
    self.bit_buffer = (self.bit_buffer << 1) | (if fill_bit { 1U } else { 0U })
    self.bit_count = self.bit_count + 1
  }
  match self.ensure_capacity(1) {
    Err(error) => Err(error)
    Ok(_) => {
      self.buffer.write_byte(self.bit_buffer.to_byte())
      self.bit_buffer = 0U
      self.bit_count = 0
      Ok(())
    }
  }
}

///|
pub fn Encoder::finish(self : Encoder) -> Result[Bytes, BinError] {
  match self.align_byte() {
    Err(error) => Err(error)
    Ok(_) => Ok(self.buffer.to_bytes())
  }
}
