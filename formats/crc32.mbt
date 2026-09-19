///|
/// PNG 等格式使用的 IEEE CRC-32。
fn crc32(bytes : Bytes) -> UInt {
  let mut crc = 0xffffffffU
  for byte in bytes {
    crc = crc ^ byte.to_uint()
    for index = 0; index < 8; index = index + 1 {
      crc = if (crc & 1U) == 1U { (crc >> 1) ^ 0xedb88320U } else { crc >> 1 }
    }
  }
  crc ^ 0xffffffffU
}

///|
fn chunk_crc_input(kind : String, data : Bytes) -> Bytes {
  let output = @utf8.encode(kind[:]).to_array()
  for byte in data {
    output.push(byte)
  }
  Bytes::from_array(output)
}
