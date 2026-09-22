///|
struct BridgeError {
  error : String
} derive(ToJson)

///|
pub extend BridgeError with ToJson::{to_json}

///|
let web_max_bytes : Int = 16 * 1024 * 1024

///|
fn error_json(message : String) -> String {
  @json.to_json(BridgeError::{ error: message, }).stringify()
}

///|
fn hex_digit(value : Int) -> Int? {
  if value >= 48 && value <= 57 {
    Some(value - 48)
  } else if value >= 65 && value <= 70 {
    Some(value - 65 + 10)
  } else if value >= 97 && value <= 102 {
    Some(value - 97 + 10)
  } else {
    None
  }
}

///|
fn decode_hex_with_limit(
  input : String,
  max_bytes : Int,
) -> Result[Bytes, String] {
  if input.length() % 2 != 0 {
    return Err("hex input must contain an even number of characters")
  }
  if input.length() / 2 > max_bytes {
    return Err("input exceeds the browser safety limit of \{max_bytes} bytes")
  }
  let output : Array[Byte] = []
  let mut index = 0
  while index < input.length() {
    let high = match hex_digit(input.code_unit_at(index).to_int()) {
      Some(value) => value
      None => return Err("invalid hex digit at index \{index}")
    }
    let low = match hex_digit(input.code_unit_at(index + 1).to_int()) {
      Some(value) => value
      None => return Err("invalid hex digit at index \{index + 1}")
    }
    output.push(((high << 4) | low).to_byte())
    index += 2
  }
  Ok(Bytes::from_array(output))
}

///|
fn decode_hex(input : String) -> Result[Bytes, String] {
  decode_hex_with_limit(input, web_max_bytes)
}

///|
fn encode_compact_hex(bytes : Bytes) -> String {
  let parts : Array[String] = []
  for byte in bytes {
    parts.push(byte.to_hex())
  }
  parts.join("")
}

///|
#export_name("inspect_hex")
pub fn inspect_hex(format_name : String, hex : String) -> String {
  let bytes = match decode_hex(hex) {
    Ok(value) => value
    Err(message) => return error_json(message)
  }
  let format = match @formats.Format::parse(format_name) {
    Ok(value) => value
    Err(message) => return error_json(message)
  }
  match @formats.inspect(bytes, format~) {
    Ok(report) => report.to_json_string()
    Err(error) => error_json(error.render())
  }
}

///|
#export_name("sample_hex")
pub fn sample_hex(format_name : String) -> String {
  let bytes = match @formats.Format::parse(format_name) {
    Ok(@formats.Png) => @formats.sample_png()
    Ok(@formats.Wav) => @formats.sample_wav()
    Ok(@formats.Pcap) => @formats.sample_pcap()
    Ok(@formats.Bmff) => @formats.sample_bmff()
    Ok(@formats.Dns) => @formats.sample_dns()
    Ok(@formats.Elf) => @formats.sample_elf()
    Ok(@formats.Auto) => return error_json("sample format cannot be auto")
    Err(message) => return error_json(message)
  }
  encode_compact_hex(bytes)
}
