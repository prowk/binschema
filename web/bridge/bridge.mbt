///|
struct BridgeError {
  error : String
} derive(ToJson)

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
fn decode_hex(input : String) -> Result[Bytes, String] {
  if input.length() % 2 != 0 {
    return Err("hex input must contain an even number of characters")
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
    Ok(@formats.Auto) => return error_json("sample format cannot be auto")
    Err(message) => return error_json(message)
  }
  @bin.bytes_to_hex(bytes)
}
