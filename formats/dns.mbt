///|
/// DNS domain name with decoded labels and the exact wire representation that
/// appeared at the current field. Preserving wire keeps compression pointers
/// byte-exact across decode -> encode.
pub(all) struct DnsName {
  labels : Array[Bytes]
  wire : Bytes
} derive(Eq, Debug, ToJson)

///|
pub extend DnsName with Eq::{not_equal, equal}

///|
pub extend DnsName with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend DnsName with ToJson::{to_json}

///|
pub(all) struct DnsQuestion {
  name : DnsName
  qtype : UInt
  qclass : UInt
} derive(Eq, Debug, ToJson)

///|
pub extend DnsQuestion with Eq::{not_equal, equal}

///|
pub extend DnsQuestion with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend DnsQuestion with ToJson::{to_json}

///|
pub(all) struct DnsRecord {
  name : DnsName
  rr_type : UInt
  rr_class : UInt
  ttl : UInt
  rdata : Bytes
} derive(Eq, Debug, ToJson)

///|
pub extend DnsRecord with Eq::{not_equal, equal}

///|
pub extend DnsRecord with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend DnsRecord with ToJson::{to_json}

///|
pub(all) struct DnsMessage {
  id : UInt
  flags : UInt
  questions : Array[DnsQuestion]
  answers : Array[DnsRecord]
  authorities : Array[DnsRecord]
  additionals : Array[DnsRecord]
} derive(Eq, Debug, ToJson)

///|
pub extend DnsMessage with Eq::{not_equal, equal}

///|
pub extend DnsMessage with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend DnsMessage with ToJson::{to_json}

///|
fn dns_error(
  decoder : @bin.Decoder,
  kind : @bin.ErrorKind,
  offset : Int,
  message : String,
) -> @bin.BinError {
  @bin.BinError::new(kind, offset, decoder.path(), message)
}

///|
fn dns_append_label(
  decoder : @bin.Decoder,
  labels : Array[Bytes],
  label : Bytes,
  expanded_octets : Int,
) -> Result[Int, @bin.BinError] {
  if labels.length() >= decoder.max_collection_length() {
    return Err(
      dns_error(
        decoder,
        @bin.LimitExceeded,
        decoder.absolute_offset(),
        "DNS name label count exceeds configured collection limit",
      ),
    )
  }
  let next = expanded_octets + 1 + label.length()
  if next > 255 {
    return Err(
      dns_error(
        decoder,
        @bin.LimitExceeded,
        decoder.absolute_offset(),
        "expanded DNS name exceeds 255 octets",
      ),
    )
  }
  labels.push(label)
  Ok(next)
}

///|
fn dns_view_byte(
  decoder : @bin.Decoder,
  offset : Int,
) -> Result[Byte, @bin.BinError] {
  match decoder.view_at(offset, 1) {
    Ok(view) => Ok(view[0])
    Err(error) => Err(error)
  }
}

///|
fn dns_resolve_pointer(
  decoder : @bin.Decoder,
  start : Int,
  labels : Array[Bytes],
  initial_expanded_octets : Int,
) -> Result[Int, @bin.BinError] {
  let mut position = start
  let mut expanded_octets = initial_expanded_octets
  let mut hops = 1
  while true {
    if hops > decoder.max_depth() {
      return Err(
        dns_error(
          decoder,
          @bin.LimitExceeded,
          position,
          "DNS compression pointer chain exceeds max_depth",
        ),
      )
    }
    let first = match dns_view_byte(decoder, position) {
      Ok(value) => value.to_uint()
      Err(error) => return Err(error)
    }
    if first == 0U {
      return Ok(expanded_octets)
    }
    if first & 0xc0U == 0xc0U {
      let second = match dns_view_byte(decoder, position + 1) {
        Ok(value) => value.to_uint()
        Err(error) => return Err(error)
      }
      let target = (((first & 0x3fU) << 8) | second).reinterpret_as_int()
      if target >= position {
        return Err(
          dns_error(
            decoder,
            @bin.InvalidValue,
            position,
            "DNS compression pointer must reference an earlier message offset",
          ),
        )
      }
      position = target
      hops += 1
    } else if first & 0xc0U != 0U {
      return Err(
        dns_error(
          decoder,
          @bin.InvalidValue,
          position,
          "DNS name uses a reserved label encoding",
        ),
      )
    } else {
      let length = first.reinterpret_as_int()
      if length > 63 {
        return Err(
          dns_error(
            decoder,
            @bin.InvalidValue,
            position,
            "DNS label length exceeds 63 octets",
          ),
        )
      }
      let label = match decoder.view_at(position + 1, length) {
        Ok(value) => value.to_owned()
        Err(error) => return Err(error)
      }
      expanded_octets = match
        dns_append_label(decoder, labels, label, expanded_octets) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      position += 1 + length
    }
  }
  Ok(expanded_octets)
}

///|
fn decode_dns_name(decoder : @bin.Decoder) -> Result[DnsName, @bin.BinError] {
  let labels : Array[Bytes] = []
  let wire : Array[Byte] = []
  let mut expanded_octets = 1
  while true {
    let pointer_position = decoder.offset()
    let first_byte = match decoder.read_byte() {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    wire.push(first_byte)
    let first = first_byte.to_uint()
    if first == 0U {
      return Ok({ labels, wire: Bytes::from_array(wire), })
    }
    if first & 0xc0U == 0xc0U {
      let second_byte = match decoder.read_byte() {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      wire.push(second_byte)
      let target = (((first & 0x3fU) << 8) | second_byte.to_uint())
        .reinterpret_as_int()
      if target >= pointer_position {
        return Err(
          dns_error(
            decoder,
            @bin.InvalidValue,
            pointer_position,
            "DNS compression pointer must reference an earlier message offset",
          ),
        )
      }
      expanded_octets = match
        dns_resolve_pointer(decoder, target, labels, expanded_octets) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      return Ok({ labels, wire: Bytes::from_array(wire), })
    }
    if first & 0xc0U != 0U {
      return Err(
        dns_error(
          decoder,
          @bin.InvalidValue,
          pointer_position,
          "DNS name uses a reserved label encoding",
        ),
      )
    }
    let length = first.reinterpret_as_int()
    if length > 63 {
      return Err(
        dns_error(
          decoder,
          @bin.InvalidValue,
          pointer_position,
          "DNS label length exceeds 63 octets",
        ),
      )
    }
    let label = match decoder.take_bytes(length) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    for byte in label {
      wire.push(byte)
    }
    expanded_octets = match
      dns_append_label(decoder, labels, label, expanded_octets) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
  }
  Err(
    dns_error(
      decoder,
      @bin.InvalidValue,
      decoder.absolute_offset(),
      "unreachable DNS name state",
    ),
  )
}

///|
fn validate_dns_name_wire(
  wire : Bytes,
  absolute_start : Int,
) -> Result[Unit, String] {
  let mut position = 0
  let mut expanded_octets = 1
  while position < wire.length() {
    let first = wire[position].to_uint()
    if first == 0U {
      if position + 1 != wire.length() {
        return Err("DNS name wire contains trailing bytes after root label")
      }
      return Ok(())
    }
    if first & 0xc0U == 0xc0U {
      if position + 2 != wire.length() {
        return Err("DNS compression pointer must terminate the encoded name")
      }
      let target = (((first & 0x3fU) << 8) | wire[position + 1].to_uint())
        .reinterpret_as_int()
      if target >= absolute_start + position {
        return Err("DNS compression pointer must reference earlier message bytes")
      }
      return Ok(())
    }
    if first & 0xc0U != 0U {
      return Err("DNS name uses a reserved label encoding")
    }
    let length = first.reinterpret_as_int()
    if length > 63 {
      return Err("DNS label length exceeds 63 octets")
    }
    if position + 1 + length > wire.length() {
      return Err("DNS label exceeds encoded name bytes")
    }
    expanded_octets += 1 + length
    if expanded_octets > 255 {
      return Err("expanded DNS name exceeds 255 octets")
    }
    position += 1 + length
  }
  Err("DNS name wire is missing a root label or compression pointer")
}

///|
fn dns_name_codec() -> @bin.Codec[DnsName] {
  @bin.Codec::make(
    fn(decoder) { decode_dns_name(decoder) },
    fn(encoder, value) {
      match validate_dns_name_wire(value.wire, encoder.length()) {
        Err(message) =>
          Err(
            @bin.BinError::new(
              @bin.InvalidValue,
              encoder.length(),
              encoder.path(),
              message,
            ),
          )
        Ok(_) => encoder.write_bytes(value.wire[:])
      }
    },
    kind="dns-name",
    render=fn(value) { value.display() },
    schema=@bin.SchemaNode::node(
      "dns-name",
      [@bin.SchemaNode::leaf("labels-or-compression-pointer")],
      constraints=[
        "label_length<=63",
        "expanded_length<=255",
        "compression_pointer=backward-and-bounded",
      ],
    ),
  )
}

///|
fn dns_label_display(label : Bytes) -> String {
  let mut printable = label.length() > 0
  for byte in label {
    let value = byte.to_int()
    if value < 33 || value > 126 || value == 46 {
      printable = false
    }
  }
  if printable {
    @utf8.decode_lossy(label[:])
  } else {
    "[" + @bin.bytes_to_hex(label) + "]"
  }
}

///|
pub fn DnsName::display(self : DnsName) -> String {
  if self.labels.length() == 0 {
    "."
  } else {
    let parts : Array[String] = []
    for label in self.labels {
      parts.push(dns_label_display(label))
    }
    parts.join(".") + "."
  }
}

///|
pub fn dns_name_uncompressed(labels : Array[Bytes]) -> Result[DnsName, String] {
  let wire : Array[Byte] = []
  let copied : Array[Bytes] = []
  let mut expanded_octets = 1
  for label in labels {
    if label.length() == 0 || label.length() > 63 {
      return Err("DNS labels must contain 1..63 octets")
    }
    expanded_octets += 1 + label.length()
    if expanded_octets > 255 {
      return Err("expanded DNS name exceeds 255 octets")
    }
    wire.push(label.length().reinterpret_as_uint().to_byte())
    for byte in label {
      wire.push(byte)
    }
    copied.push(label)
  }
  wire.push(0U.to_byte())
  Ok({ labels: copied, wire: Bytes::from_array(wire), })
}

///|
fn dns_section_limit(
  count : UInt,
  decoder : @bin.Decoder,
  path : String,
) -> Result[Int, @bin.BinError] {
  let length = count.reinterpret_as_int()
  if length > decoder.max_collection_length() {
    Err(
      @bin.BinError::new(
        @bin.LimitExceeded,
        decoder.absolute_offset(),
        path,
        "DNS section count exceeds configured collection limit",
      ),
    )
  } else {
    Ok(length)
  }
}

///|
fn decode_dns_question(
  decoder : @bin.Decoder,
  prefix : String,
) -> Result[DnsQuestion, @bin.BinError] {
  let name = match dns_name_codec().named(prefix + ".name").decode_from(decoder) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let qtype = match @bin.u16_be().named(prefix + ".type").decode_from(decoder) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let qclass = match @bin.u16_be().named(prefix + ".class").decode_from(decoder) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  Ok({ name, qtype, qclass, })
}

///|
fn decode_dns_record(
  decoder : @bin.Decoder,
  prefix : String,
) -> Result[DnsRecord, @bin.BinError] {
  let name = match dns_name_codec().named(prefix + ".name").decode_from(decoder) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let rr_type = match @bin.u16_be().named(prefix + ".type").decode_from(decoder) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let rr_class = match @bin.u16_be().named(prefix + ".class").decode_from(decoder) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let ttl = match @bin.u32_be().named(prefix + ".ttl").decode_from(decoder) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let rdlength = match @bin.u16_be().named(prefix + ".rdlength").decode_from(decoder) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let rdata = match
    @bin.bytes_fixed(rdlength.reinterpret_as_int())
    .named(prefix + ".rdata")
    .decode_from(decoder) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  Ok({ name, rr_type, rr_class, ttl, rdata, })
}

///|
fn encode_dns_question(
  encoder : @bin.Encoder,
  value : DnsQuestion,
) -> Result[Unit, @bin.BinError] {
  match dns_name_codec().encode_into(encoder, value.name) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match @bin.u16_be().encode_into(encoder, value.qtype) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  @bin.u16_be().encode_into(encoder, value.qclass)
}

///|
fn encode_dns_record(
  encoder : @bin.Encoder,
  value : DnsRecord,
) -> Result[Unit, @bin.BinError] {
  if value.rdata.length() > 65535 {
    return Err(
      @bin.BinError::new(
        @bin.LimitExceeded,
        encoder.length(),
        encoder.path(),
        "DNS RDATA exceeds the 16-bit RDLENGTH field",
      ),
    )
  }
  match dns_name_codec().encode_into(encoder, value.name) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  for result in [
    @bin.u16_be().encode_into(encoder, value.rr_type),
    @bin.u16_be().encode_into(encoder, value.rr_class),
    @bin.u32_be().encode_into(encoder, value.ttl),
    @bin.u16_be().encode_into(
      encoder,
      value.rdata.length().reinterpret_as_uint(),
    ),
  ] {
    match result {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
  }
  @bin.bytes_fixed(value.rdata.length()).encode_into(encoder, value.rdata)
}

///|
fn dns_schema() -> @bin.SchemaNode {
  let question = @bin.SchemaNode::node(
    "question",
    [
      dns_name_codec().schema_node().with_name("name"),
      @bin.SchemaNode::leaf("u16be").with_name("type"),
      @bin.SchemaNode::leaf("u16be").with_name("class"),
    ],
  )
  let record = @bin.SchemaNode::node(
    "resource-record",
    [
      dns_name_codec().schema_node().with_name("name"),
      @bin.SchemaNode::leaf("u16be").with_name("type"),
      @bin.SchemaNode::leaf("u16be").with_name("class"),
      @bin.SchemaNode::leaf("u32be").with_name("ttl"),
      @bin.SchemaNode::leaf("u16be").with_name("rdlength"),
      @bin.SchemaNode::leaf("bytes[rdlength]").with_name("rdata"),
    ],
  )
  @bin.SchemaNode::node(
    "dns",
    [
      @bin.SchemaNode::node(
        "header",
        [
          @bin.SchemaNode::leaf("u16be").with_name("id"),
          @bin.SchemaNode::leaf("u16be").with_name("flags"),
          @bin.SchemaNode::leaf("u16be").with_name("qdcount"),
          @bin.SchemaNode::leaf("u16be").with_name("ancount"),
          @bin.SchemaNode::leaf("u16be").with_name("nscount"),
          @bin.SchemaNode::leaf("u16be").with_name("arcount"),
        ],
      ),
      @bin.SchemaNode::node(
        "questions",
        [question],
        constraints=["count=qdcount", "max_count=runtime-limit"],
      ),
      @bin.SchemaNode::node(
        "answers",
        [record],
        constraints=["count=ancount", "max_count=runtime-limit"],
      ),
      @bin.SchemaNode::node(
        "authorities",
        [record],
        constraints=["count=nscount", "max_count=runtime-limit"],
      ),
      @bin.SchemaNode::node(
        "additionals",
        [record],
        constraints=["count=arcount", "max_count=runtime-limit"],
      ),
    ],
    constraints=["compression-pointer=backward-bounded-depth-limited"],
  )
}

///|
fn check_dns_encode_count(
  encoder : @bin.Encoder,
  count : Int,
  path : String,
) -> Result[Unit, @bin.BinError] {
  if count > encoder.max_collection_length() || count > 65535 {
    Err(
      @bin.BinError::new(
        @bin.LimitExceeded,
        encoder.length(),
        path,
        "DNS section count exceeds configured or wire-format limit",
      ),
    )
  } else {
    Ok(())
  }
}

///|
pub fn dns_codec() -> @bin.Codec[DnsMessage] {
  @bin.Codec::make(
    fn(decoder) {
      let id = match @bin.u16_be().named("id").decode_from(decoder) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      let flags = match @bin.u16_be().named("flags").decode_from(decoder) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      let qdcount = match @bin.u16_be().named("qdcount").decode_from(decoder) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      let ancount = match @bin.u16_be().named("ancount").decode_from(decoder) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      let nscount = match @bin.u16_be().named("nscount").decode_from(decoder) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      let arcount = match @bin.u16_be().named("arcount").decode_from(decoder) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      let question_count = match dns_section_limit(qdcount, decoder, "questions") {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      let answer_count = match dns_section_limit(ancount, decoder, "answers") {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      let authority_count = match dns_section_limit(nscount, decoder, "authorities") {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      let additional_count = match dns_section_limit(arcount, decoder, "additionals") {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      let questions : Array[DnsQuestion] = []
      let answers : Array[DnsRecord] = []
      let authorities : Array[DnsRecord] = []
      let additionals : Array[DnsRecord] = []
      for index in 0..<question_count {
        match decode_dns_question(decoder, "questions.\{index}") {
          Ok(value) => questions.push(value)
          Err(error) => return Err(error)
        }
      }
      for index in 0..<answer_count {
        match decode_dns_record(decoder, "answers.\{index}") {
          Ok(value) => answers.push(value)
          Err(error) => return Err(error)
        }
      }
      for index in 0..<authority_count {
        match decode_dns_record(decoder, "authorities.\{index}") {
          Ok(value) => authorities.push(value)
          Err(error) => return Err(error)
        }
      }
      for index in 0..<additional_count {
        match decode_dns_record(decoder, "additionals.\{index}") {
          Ok(value) => additionals.push(value)
          Err(error) => return Err(error)
        }
      }
      Ok({ id, flags, questions, answers, authorities, additionals, })
    },
    fn(encoder, value) {
      for (count, path) in [
        (value.questions.length(), "questions"),
        (value.answers.length(), "answers"),
        (value.authorities.length(), "authorities"),
        (value.additionals.length(), "additionals"),
      ] {
        match check_dns_encode_count(encoder, count, path) {
          Err(error) => return Err(error)
          Ok(_) => ()
        }
      }
      for result in [
        @bin.u16_be().encode_into(encoder, value.id),
        @bin.u16_be().encode_into(encoder, value.flags),
        @bin.u16_be().encode_into(
          encoder,
          value.questions.length().reinterpret_as_uint(),
        ),
        @bin.u16_be().encode_into(
          encoder,
          value.answers.length().reinterpret_as_uint(),
        ),
        @bin.u16_be().encode_into(
          encoder,
          value.authorities.length().reinterpret_as_uint(),
        ),
        @bin.u16_be().encode_into(
          encoder,
          value.additionals.length().reinterpret_as_uint(),
        ),
      ] {
        match result {
          Err(error) => return Err(error)
          Ok(_) => ()
        }
      }
      for question in value.questions {
        match encode_dns_question(encoder, question) {
          Err(error) => return Err(error)
          Ok(_) => ()
        }
      }
      for record in value.answers {
        match encode_dns_record(encoder, record) {
          Err(error) => return Err(error)
          Ok(_) => ()
        }
      }
      for record in value.authorities {
        match encode_dns_record(encoder, record) {
          Err(error) => return Err(error)
          Ok(_) => ()
        }
      }
      for record in value.additionals {
        match encode_dns_record(encoder, record) {
          Err(error) => return Err(error)
          Ok(_) => ()
        }
      }
      Ok(())
    },
    kind="dns",
    render=fn(value) {
      "DNS id=\{value.id}, q=\{value.questions.length()}, a=\{value.answers.length()}"
    },
    schema=dns_schema(),
  )
}

///|
pub fn sample_dns() -> Bytes {
  b"\x12\x34\x81\x80\x00\x01\x00\x01\x00\x00\x00\x00\x07example\x03com\x00\x00\x01\x00\x01\xc0\x0c\x00\x01\x00\x01\x00\x00\x00\x3c\x00\x04\x01\x02\x03\x04"
}
