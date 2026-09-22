///|
pub(all) struct PcapPacket {
  timestamp_seconds : UInt
  timestamp_fraction : UInt
  original_length : UInt
  data : Bytes
} derive(Eq, Debug, ToJson)

///|
pub extend PcapPacket with Eq::{not_equal, equal}

///|
pub extend PcapPacket with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend PcapPacket with ToJson::{to_json}

///|
pub(all) struct PcapFile {
  endian : @bin.Endian
  nanosecond_timestamps : Bool
  version_major : UInt
  version_minor : UInt
  timezone_offset : Int
  timestamp_accuracy : UInt
  snapshot_length : UInt
  link_type : UInt
  packets : Array[PcapPacket]
} derive(Eq, Debug, ToJson)

///|
pub extend PcapFile with Eq::{not_equal, equal}

///|
pub extend PcapFile with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend PcapFile with ToJson::{to_json}

///|
fn pcap_uint16(endian : @bin.Endian) -> @bin.Codec[UInt] {
  match endian {
    @bin.Big => @bin.u16_be()
    @bin.Little => @bin.u16_le()
  }
}

///|
fn pcap_uint32(endian : @bin.Endian) -> @bin.Codec[UInt] {
  match endian {
    @bin.Big => @bin.u32_be()
    @bin.Little => @bin.u32_le()
  }
}

///|
fn pcap_int32(endian : @bin.Endian) -> @bin.Codec[Int] {
  match endian {
    @bin.Big => @bin.i32_be()
    @bin.Little => @bin.i32_le()
  }
}

///|
fn pcap_magic(endian : @bin.Endian, nano : Bool) -> Bytes {
  match (endian, nano) {
    (@bin.Little, false) => b"\xd4\xc3\xb2\xa1"
    (@bin.Big, false) => b"\xa1\xb2\xc3\xd4"
    (@bin.Little, true) => b"\x4d\x3c\xb2\xa1"
    (@bin.Big, true) => b"\xa1\xb2\x3c\x4d"
  }
}

///|
fn classify_pcap_magic(bytes : Bytes) -> Result[(@bin.Endian, Bool), String] {
  if bytes == b"\xd4\xc3\xb2\xa1" {
    Ok((@bin.Little, false))
  } else if bytes == b"\xa1\xb2\xc3\xd4" {
    Ok((@bin.Big, false))
  } else if bytes == b"\x4d\x3c\xb2\xa1" {
    Ok((@bin.Little, true))
  } else if bytes == b"\xa1\xb2\x3c\x4d" {
    Ok((@bin.Big, true))
  } else {
    Err("unsupported PCAP magic bytes")
  }
}

///|
fn validate_pcap_header(
  major : UInt,
  minor : UInt,
  snapshot : UInt,
) -> Result[Unit, String] {
  if major != 2U || minor != 4U {
    return Err("only PCAP version 2.4 is supported")
  }
  if snapshot == 0U {
    return Err("PCAP snapshot length must be non-zero")
  }
  Ok(())
}

///|
fn validate_pcap_packet(
  packet : PcapPacket,
  snapshot : UInt,
  nano : Bool,
) -> Result[Unit, String] {
  let included = packet.data.length().reinterpret_as_uint()
  if included > snapshot {
    return Err("PCAP packet exceeds the declared snapshot length")
  }
  if included > packet.original_length {
    return Err("PCAP included length exceeds original packet length")
  }
  let fraction_limit = if nano { 1_000_000_000U } else { 1_000_000U }
  if packet.timestamp_fraction >= fraction_limit {
    return Err("PCAP timestamp fraction exceeds its declared resolution")
  }
  Ok(())
}

///|
fn pcap_schema() -> @bin.SchemaNode {
  @bin.SchemaNode::node(
    "pcap",
    [
      @bin.SchemaNode::leaf("bytes[4]").with_name("magic"),
      @bin.SchemaNode::node(
        "header",
        [
          @bin.SchemaNode::leaf("u16[endian]").with_name("version_major"),
          @bin.SchemaNode::leaf("u16[endian]").with_name("version_minor"),
          @bin.SchemaNode::leaf("i32[endian]").with_name("timezone_offset"),
          @bin.SchemaNode::leaf("u32[endian]").with_name("timestamp_accuracy"),
          @bin.SchemaNode::leaf("u32[endian]").with_name("snapshot_length"),
          @bin.SchemaNode::leaf("u32[endian]").with_name("link_type"),
        ],
        constraints=["version=2.4"],
      ),
      @bin.SchemaNode::node(
        "packets",
        [
          @bin.SchemaNode::node(
            "packet",
            [
              @bin.SchemaNode::leaf("u32[endian]").with_name(
                "timestamp_seconds",
              ),
              @bin.SchemaNode::leaf("u32[endian]").with_name(
                "timestamp_fraction",
              ),
              @bin.SchemaNode::leaf("u32[endian]").with_name("included_length"),
              @bin.SchemaNode::leaf("u32[endian]").with_name("original_length"),
              @bin.SchemaNode::leaf("bytes[included_length]").with_name("data"),
            ],
            constraints=["included_length<=snapshot_length"],
          ),
        ],
        constraints=["repeat=until-region-eof", "max_count=runtime-limit"],
      ),
    ],
    constraints=["endianness=from-magic", "timestamp-resolution=from-magic"],
  )
}

///|
pub fn pcap_codec() -> @bin.Codec[PcapFile] {
  @bin.Codec::make(
    fn(decoder) {
      let magic = match
        @bin.bytes_fixed(4).named("magic").decode_from(decoder) {
        Err(error) => return Err(error)
        Ok(value) => value
      }
      let (endian, nano) = match classify_pcap_magic(magic) {
        Err(message) =>
          return Err(@bin.BinError::new(@bin.InvalidValue, 0, "magic", message))
        Ok(value) => value
      }
      let u16 = pcap_uint16(endian)
      let u32 = pcap_uint32(endian)
      let i32 = pcap_int32(endian)
      let version_major = match
        u16.named("version_major").decode_from(decoder) {
        Err(error) => return Err(error)
        Ok(value) => value
      }
      let version_minor = match
        u16.named("version_minor").decode_from(decoder) {
        Err(error) => return Err(error)
        Ok(value) => value
      }
      let timezone_offset = match
        i32.named("timezone_offset").decode_from(decoder) {
        Err(error) => return Err(error)
        Ok(value) => value
      }
      let timestamp_accuracy = match
        u32.named("timestamp_accuracy").decode_from(decoder) {
        Err(error) => return Err(error)
        Ok(value) => value
      }
      let snapshot_length = match
        u32.named("snapshot_length").decode_from(decoder) {
        Err(error) => return Err(error)
        Ok(value) => value
      }
      let link_type = match u32.named("link_type").decode_from(decoder) {
        Err(error) => return Err(error)
        Ok(value) => value
      }
      match
        validate_pcap_header(version_major, version_minor, snapshot_length) {
        Err(message) =>
          return Err(
            @bin.BinError::new(@bin.InvalidValue, 4, "header", message),
          )
        Ok(_) => ()
      }
      let packets : Array[PcapPacket] = []
      while decoder.remaining() > 0 {
        if packets.length() >= decoder.max_collection_length() {
          return Err(
            @bin.BinError::new(
              @bin.LimitExceeded,
              decoder.absolute_offset(),
              "packets",
              "PCAP packet count exceeds configured limit",
            ),
          )
        }
        let prefix = "packets.\{packets.length()}"
        let timestamp_seconds = match
          u32.named(prefix + ".timestamp_seconds").decode_from(decoder) {
          Err(error) => return Err(error)
          Ok(value) => value
        }
        let timestamp_fraction = match
          u32.named(prefix + ".timestamp_fraction").decode_from(decoder) {
          Err(error) => return Err(error)
          Ok(value) => value
        }
        let included_length = match
          u32.named(prefix + ".included_length").decode_from(decoder) {
          Err(error) => return Err(error)
          Ok(value) => value
        }
        let original_length = match
          u32.named(prefix + ".original_length").decode_from(decoder) {
          Err(error) => return Err(error)
          Ok(value) => value
        }
        if included_length > 0x7fffffffU {
          return Err(
            @bin.BinError::new(
              @bin.LimitExceeded,
              decoder.absolute_offset(),
              prefix,
              "PCAP packet is too large for this runtime",
            ),
          )
        }
        let length = included_length.reinterpret_as_int()
        if included_length > snapshot_length {
          return Err(
            @bin.BinError::new(
              @bin.LimitExceeded,
              decoder.absolute_offset(),
              prefix,
              "PCAP packet exceeds the declared snapshot length",
            ),
          )
        }
        if included_length > original_length {
          return Err(
            @bin.BinError::new(
              @bin.InvalidValue,
              decoder.absolute_offset(),
              prefix,
              "PCAP included length exceeds original packet length",
            ),
          )
        }
        let fraction_limit = if nano { 1_000_000_000U } else { 1_000_000U }
        if timestamp_fraction >= fraction_limit {
          return Err(
            @bin.BinError::new(
              @bin.InvalidValue,
              decoder.absolute_offset(),
              prefix + ".timestamp_fraction",
              "PCAP timestamp fraction exceeds its declared resolution",
            ),
          )
        }
        let data = match
          @bin.bytes_fixed(length).named(prefix + ".data").decode_from(decoder) {
          Err(error) => return Err(error)
          Ok(value) => value
        }
        packets.push({
          timestamp_seconds,
          timestamp_fraction,
          original_length,
          data,
        })
      }
      Ok({
        endian,
        nanosecond_timestamps: nano,
        version_major,
        version_minor,
        timezone_offset,
        timestamp_accuracy,
        snapshot_length,
        link_type,
        packets,
      })
    },
    fn(encoder, value) {
      if value.packets.length() > encoder.max_collection_length() {
        return Err(
          @bin.BinError::new(
            @bin.LimitExceeded,
            encoder.length(),
            "packets",
            "PCAP packet count exceeds configured limit",
          ),
        )
      }
      match
        validate_pcap_header(
          value.version_major,
          value.version_minor,
          value.snapshot_length,
        ) {
        Err(message) =>
          return Err(
            @bin.BinError::new(
              @bin.InvalidValue,
              encoder.length(),
              "header",
              message,
            ),
          )
        Ok(_) => ()
      }
      for index, packet in value.packets {
        match
          validate_pcap_packet(
            packet,
            value.snapshot_length,
            value.nanosecond_timestamps,
          ) {
          Err(message) =>
            return Err(
              @bin.BinError::new(
                @bin.InvalidValue,
                encoder.length(),
                "packets.\{index}",
                message,
              ),
            )
          Ok(_) => ()
        }
      }
      match
        @bin.bytes_fixed(4).encode_into(
          encoder,
          pcap_magic(value.endian, value.nanosecond_timestamps),
        ) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
      let u16 = pcap_uint16(value.endian)
      let u32 = pcap_uint32(value.endian)
      let i32 = pcap_int32(value.endian)
      for
        result in [
          u16.encode_into(encoder, value.version_major),
          u16.encode_into(encoder, value.version_minor),
          i32.encode_into(encoder, value.timezone_offset),
          u32.encode_into(encoder, value.timestamp_accuracy),
          u32.encode_into(encoder, value.snapshot_length),
          u32.encode_into(encoder, value.link_type),
        ] {
        match result {
          Err(error) => return Err(error)
          Ok(_) => ()
        }
      }
      for packet in value.packets {
        for
          result in [
            u32.encode_into(encoder, packet.timestamp_seconds),
            u32.encode_into(encoder, packet.timestamp_fraction),
            u32.encode_into(encoder, packet.data.length().reinterpret_as_uint()),
            u32.encode_into(encoder, packet.original_length),
          ] {
          match result {
            Err(error) => return Err(error)
            Ok(_) => ()
          }
        }
        match
          @bin.bytes_fixed(packet.data.length()).encode_into(
            encoder,
            packet.data,
          ) {
          Err(error) => return Err(error)
          Ok(_) => ()
        }
      }
      Ok(())
    },
    kind="pcap",
    render=fn(value) { "PCAP with \{value.packets.length()} packets" },
    schema=pcap_schema(),
  )
}

///|
pub fn sample_pcap() -> Bytes {
  let packets = [
    PcapPacket::{
      timestamp_seconds: 1_700_000_000U,
      timestamp_fraction: 123_456U,
      original_length: 4U,
      data: b"\xde\xad\xbe\xef",
    },
  ]
  let value = PcapFile::{
    endian: @bin.Little,
    nanosecond_timestamps: false,
    version_major: 2U,
    version_minor: 4U,
    timezone_offset: 0,
    timestamp_accuracy: 0U,
    snapshot_length: 65535U,
    link_type: 1U,
    packets,
  }
  match @bin.encode(pcap_codec(), value) {
    Ok(bytes) => bytes
    Err(_) => b""
  }
}
