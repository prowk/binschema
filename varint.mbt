///|
fn encode_uleb128_bytes(value : UInt64) -> Bytes {
  let output : Array[Byte] = []
  for current = value {
    let payload = (current & 0x7fUL).to_byte()
    let next = current >> 7
    if next == 0UL {
      output.push(payload)
      break
    } else {
      output.push((payload.to_uint() | 0x80U).to_byte())
      continue next
    }
  }
  Bytes::from_array(output)
}

///|
fn encode_sleb128_bytes(value : Int64) -> Bytes {
  let output : Array[Byte] = []
  for current = value {
    let payload = current & 0x7fL
    let next = current >> 7
    let sign_set = (payload & 0x40L) != 0L
    let finished = if current >= 0L {
      next == 0L && !sign_set
    } else {
      next == -1L && sign_set
    }
    if finished {
      output.push(payload.to_byte())
      break
    } else {
      output.push((payload | 0x80L).to_byte())
      continue next
    }
  }
  Bytes::from_array(output)
}

///|
/// 64 位无符号 LEB128。解码严格要求最短规范表示，最多消费 10 字节。
pub fn uleb128() -> Codec[UInt64] {
  Codec::make(
    fn(decoder) {
      let start = decoder.absolute_offset()
      let encoded : Array[Byte] = []
      let mut value = 0UL
      for index in 0..<10 {
        let byte = match decoder.take_bytes(1) {
          Err(error) => return Err(error)
          Ok(bytes) => bytes[0]
        }
        encoded.push(byte)
        let payload = (byte.to_uint() & 0x7fU).to_uint64()
        if index == 9 && payload > 1UL {
          return Err(
            BinError::new(
              InvalidValue,
              start,
              decoder.path(),
              "ULEB128 value overflows UInt64",
            ),
          )
        }
        value = value | (payload << (index * 7))
        if (byte.to_uint() & 0x80U) == 0U {
          let actual = Bytes::from_array(encoded)
          if encode_uleb128_bytes(value) != actual {
            return Err(
              BinError::new(
                InvalidValue,
                start,
                decoder.path(),
                "ULEB128 value is not canonically encoded",
              ),
            )
          }
          return Ok(value)
        }
      }
      Err(
        BinError::new(
          LimitExceeded,
          start,
          decoder.path(),
          "ULEB128 exceeds the 10-byte UInt64 limit",
        ),
      )
    },
    fn(encoder, value) { encoder.write_bytes(encode_uleb128_bytes(value)[:]) },
    kind="uleb128",
    render=fn(value) { value.to_string() },
  )
}

///|
/// 64 位有符号 LEB128。解码严格要求最短规范表示，最多消费 10 字节。
pub fn sleb128() -> Codec[Int64] {
  Codec::make(
    fn(decoder) {
      let start = decoder.absolute_offset()
      let encoded : Array[Byte] = []
      let mut value = 0L
      for index in 0..<10 {
        let byte = match decoder.take_bytes(1) {
          Err(error) => return Err(error)
          Ok(bytes) => bytes[0]
        }
        encoded.push(byte)
        let payload = (byte.to_int() & 0x7f).to_int64()
        if index == 9 && payload != 0L && payload != 0x7fL {
          return Err(
            BinError::new(
              InvalidValue,
              start,
              decoder.path(),
              "SLEB128 value overflows Int64",
            ),
          )
        }
        value = value | (payload << (index * 7))
        if (byte.to_uint() & 0x80U) == 0U {
          let bits = (index + 1) * 7
          if bits < 64 && (byte.to_uint() & 0x40U) != 0U {
            value = value | (-1L << bits)
          }
          let actual = Bytes::from_array(encoded)
          if encode_sleb128_bytes(value) != actual {
            return Err(
              BinError::new(
                InvalidValue,
                start,
                decoder.path(),
                "SLEB128 value is not canonically encoded",
              ),
            )
          }
          return Ok(value)
        }
      }
      Err(
        BinError::new(
          LimitExceeded,
          start,
          decoder.path(),
          "SLEB128 exceeds the 10-byte Int64 limit",
        ),
      )
    },
    fn(encoder, value) { encoder.write_bytes(encode_sleb128_bytes(value)[:]) },
    kind="sleb128",
    render=fn(value) { value.to_string() },
  )
}
