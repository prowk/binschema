///|
/// 内置的示例格式。Auto 仅用于自动检测入口。
pub(all) enum Format {
  Auto
  Png
  Wav
  Pcap
  Bmff
} derive(Eq, Debug, ToJson)

///|
pub extend Format with Eq::{not_equal, equal}

///|
pub extend Format with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Format with ToJson::{to_json}

///|
pub(all) struct SummaryItem {
  key : String
  value : String
} derive(Eq, Debug, ToJson)

///|
pub extend SummaryItem with Eq::{not_equal, equal}

///|
pub extend SummaryItem with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend SummaryItem with ToJson::{to_json}

///|
/// 与 CLI、Web 演示共享的稳定检查结果。
pub(all) struct Inspection {
  format : String
  size : Int
  roundtrip_equal : Bool
  summary : Array[SummaryItem]
  schema : @bin.SchemaNode
  trace : Array[@bin.TraceEntry]
} derive(Eq, Debug, ToJson)

///|
pub extend Inspection with Eq::{not_equal, equal}

///|
pub extend Inspection with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Inspection with ToJson::{to_json}

///|
pub fn Format::parse(name : String) -> Result[Format, String] {
  match name.to_lower() {
    "auto" => Ok(Auto)
    "png" => Ok(Png)
    "wav" | "wave" => Ok(Wav)
    "pcap" => Ok(Pcap)
    "bmff" | "isobmff" | "mp4" => Ok(Bmff)
    other => Err("unsupported format: " + other)
  }
}

///|
pub fn Format::name(self : Format) -> String {
  match self {
    Auto => "auto"
    Png => "png"
    Wav => "wav"
    Pcap => "pcap"
    Bmff => "bmff"
  }
}

///|
fn starts_with(input : Bytes, prefix : Bytes) -> Bool {
  if input.length() < prefix.length() {
    return false
  }
  for index in 0..<prefix.length() {
    if input[index] != prefix[index] {
      return false
    }
  }
  true
}

///|
pub fn detect_format(input : Bytes) -> Result[Format, @bin.BinError] {
  if starts_with(input, b"\x89PNG\x0d\x0a\x1a\x0a") {
    Ok(Png)
  } else if starts_with(input, b"RIFF") &&
    input.length() >= 12 &&
    input[8] == b'W' &&
    input[9] == b'A' &&
    input[10] == b'V' &&
    input[11] == b'E' {
    Ok(Wav)
  } else if input.length() >= 8 &&
    (input[4:8].to_owned() == b"ftyp" || input[4:8].to_owned() == b"styp") {
    Ok(Bmff)
  } else if starts_with(input, b"\xd4\xc3\xb2\xa1") ||
    starts_with(input, b"\xa1\xb2\xc3\xd4") ||
    starts_with(input, b"\x4d\x3c\xb2\xa1") ||
    starts_with(input, b"\xa1\xb2\x3c\x4d") {
    Ok(Pcap)
  } else {
    Err(
      @bin.BinError::new(
        @bin.Unsupported,
        0,
        "format",
        "input does not match PNG, WAVE, PCAP, or a common ISO BMFF signature",
      ),
    )
  }
}

///|
fn item(key : String, value : String) -> SummaryItem {
  { key, value, }
}

///|
fn uint32_be_at(bytes : Bytes, offset : Int) -> UInt {
  (bytes[offset].to_uint() << 24) |
  (bytes[offset + 1].to_uint() << 16) |
  (bytes[offset + 2].to_uint() << 8) |
  bytes[offset + 3].to_uint()
}

///|
fn inspect_png(input : Bytes) -> Result[Inspection, @bin.BinError] {
  let decoded = match @bin.decode(png_codec().named("png"), input) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let encoded = match @bin.encode(png_codec(), decoded.value) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let summary = [item("chunks", decoded.value.chunks.length().to_string())]
  for chunk in decoded.value.chunks {
    if chunk.kind == "IHDR" && chunk.data.length() >= 8 {
      summary.push(item("width", uint32_be_at(chunk.data, 0).to_string()))
      summary.push(item("height", uint32_be_at(chunk.data, 4).to_string()))
      break
    }
  }
  Ok({
    format: "PNG",
    size: input.length(),
    roundtrip_equal: encoded == input,
    summary,
    schema: png_codec().named("png").schema_node(),
    trace: decoded.trace,
  })
}

///|
fn inspect_wav(input : Bytes) -> Result[Inspection, @bin.BinError] {
  let decoded = match @bin.decode(wav_codec().named("wav"), input) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let encoded = match @bin.encode(wav_codec(), decoded.value) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let summary = [item("chunks", decoded.value.chunks.length().to_string())]
  match decoded.value.format {
    Some(format) => {
      summary.push(item("channels", format.channels.to_string()))
      summary.push(item("sample_rate", format.sample_rate.to_string()))
      summary.push(item("bits_per_sample", format.bits_per_sample.to_string()))
    }
    None => summary.push(item("audio", "fmt chunk not present"))
  }
  Ok({
    format: "WAVE",
    size: input.length(),
    roundtrip_equal: encoded == input,
    summary,
    schema: wav_codec().named("wav").schema_node(),
    trace: decoded.trace,
  })
}

///|
fn inspect_pcap(input : Bytes) -> Result[Inspection, @bin.BinError] {
  let decoded = match @bin.decode(pcap_codec().named("pcap"), input) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let encoded = match @bin.encode(pcap_codec(), decoded.value) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let value = decoded.value
  let endian = match value.endian {
    @bin.Big => "big"
    @bin.Little => "little"
  }
  let resolution = if value.nanosecond_timestamps {
    "nanosecond"
  } else {
    "microsecond"
  }
  let summary = [
    item("version", "\{value.version_major}.\{value.version_minor}"),
    item("packets", value.packets.length().to_string()),
    item("link_type", value.link_type.to_string()),
    item("endianness", endian),
    item("timestamp_resolution", resolution),
  ]
  Ok({
    format: "PCAP",
    size: input.length(),
    roundtrip_equal: encoded == input,
    summary,
    schema: pcap_codec().named("pcap").schema_node(),
    trace: decoded.trace,
  })
}

///|
fn inspect_bmff(input : Bytes) -> Result[Inspection, @bin.BinError] {
  let decoded = match @bin.decode(bmff_codec().named("bmff"), input) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let encoded = match @bin.encode(bmff_codec(), decoded.value) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let types : Array[String] = []
  for box in decoded.value.boxes {
    if types.length() < 8 {
      types.push(box.type_name())
    }
  }
  let summary = [
    item("boxes", decoded.value.boxes.length().to_string()),
    item("types", types.join(", ")),
  ]
  match decoded.value.boxes.first() {
    Some(box) =>
      if box.kind == b"ftyp" && box.payload.length() >= 4 {
        summary.push(item("major_brand", @utf8.decode_lossy(box.payload[0:4])))
      }
    None => ()
  }
  Ok({
    format: "ISO BMFF",
    size: input.length(),
    roundtrip_equal: encoded == input,
    summary,
    schema: bmff_codec().named("bmff").schema_node(),
    trace: decoded.trace,
  })
}
///|
pub fn inspect(
  input : Bytes,
  format? : Format = Auto,
) -> Result[Inspection, @bin.BinError] {
  let selected = match format {
    Auto =>
      match detect_format(input) {
        Err(error) => return Err(error)
        Ok(value) => value
      }
    value => value
  }
  match selected {
    Auto =>
      Err(
        @bin.BinError::new(
          @bin.Unsupported,
          0,
          "format",
          "auto format must be resolved before inspection",
        ),
      )
    Png => inspect_png(input)
    Wav => inspect_wav(input)
    Pcap => inspect_pcap(input)
    Bmff => inspect_bmff(input)
  }
}

///|
pub fn Inspection::to_json_string(
  self : Inspection,
  pretty? : Bool = false,
) -> String {
  if pretty {
    @json.to_json(self).stringify(indent=2)
  } else {
    @json.to_json(self).stringify()
  }
}
