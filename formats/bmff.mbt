///|
/// ISO Base Media File Format box. Payload remains byte-exact so unknown box types
/// round-trip without requiring BinSchema to understand their media semantics.
pub(all) struct BmffBox {
  kind : Bytes
  extended_size : Bool
  size_to_eof : Bool
  user_type : Bytes?
  payload : Bytes
} derive(Eq, Debug, ToJson)

///|
pub extend BmffBox with Eq::{not_equal, equal}

///|
pub extend BmffBox with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend BmffBox with ToJson::{to_json}

///|
pub(all) struct BmffFile {
  boxes : Array[BmffBox]
} derive(Eq, Debug, ToJson)

///|
pub extend BmffFile with Eq::{not_equal, equal}

///|
pub extend BmffFile with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend BmffFile with ToJson::{to_json}

///|
fn bmff_kind_text(kind : Bytes) -> String {
  let mut printable = kind.length() == 4
  if printable {
    for byte in kind {
      let value = byte.to_int()
      if value < 32 || value > 126 {
        printable = false
      }
    }
  }
  if printable {
    @utf8.decode_lossy(kind[:])
  } else {
    @bin.bytes_to_hex(kind)
  }
}

///|
pub fn BmffBox::type_name(self : BmffBox) -> String {
  bmff_kind_text(self.kind)
}

///|
fn bmff_schema() -> @bin.SchemaNode {
  @bin.SchemaNode::node(
    "isobmff",
    [
      @bin.SchemaNode::node(
        "boxes",
        [
          @bin.SchemaNode::node(
            "box",
            [
              @bin.SchemaNode::leaf("u32be").with_name("size"),
              @bin.SchemaNode::leaf("bytes[4]").with_name("type"),
              @bin.SchemaNode::leaf("u64be?").with_name("largesize"),
              @bin.SchemaNode::leaf("bytes[16]?").with_name("user_type"),
              @bin.SchemaNode::leaf("bytes[payload_length]").with_name(
                "payload",
              ),
            ],
            constraints=[
              "size=0 extends to current region eof", "size=1 uses 64-bit largesize",
              "uuid adds 16-byte user type",
            ],
          ),
        ],
        constraints=["repeat=until-region-eof", "max_count=runtime-limit"],
      ),
    ],
    constraints=["unknown-box-payload=preserved"],
  )
}

///|
fn bmff_header_length(extended : Bool, uuid : Bool) -> Int {
  8 + (if extended { 8 } else { 0 }) + (if uuid { 16 } else { 0 })
}

///|
fn validate_bmff_box_for_encode(
  box : BmffBox,
  index : Int,
  count : Int,
  offset : Int,
) -> Result[Unit, @bin.BinError] {
  if box.kind.length() != 4 {
    return Err(
      @bin.BinError::new(
        @bin.InvalidValue,
        offset,
        "boxes.\{index}.type",
        "BMFF box type must contain exactly four bytes",
      ),
    )
  }
  let uuid = box.kind == b"uuid"
  match (uuid, box.user_type) {
    (true, None) =>
      return Err(
        @bin.BinError::new(
          @bin.InvalidValue,
          offset,
          "boxes.\{index}.user_type",
          "uuid boxes require a 16-byte user type",
        ),
      )
    (true, Some(value)) =>
      if value.length() != 16 {
        return Err(
          @bin.BinError::new(
            @bin.InvalidValue,
            offset,
            "boxes.\{index}.user_type",
            "uuid user type must contain exactly 16 bytes",
          ),
        )
      }
    (false, Some(_)) =>
      return Err(
        @bin.BinError::new(
          @bin.InvalidValue,
          offset,
          "boxes.\{index}.user_type",
          "only uuid boxes may carry a user type",
        ),
      )
    (false, None) => ()
  }
  if box.size_to_eof && box.extended_size {
    return Err(
      @bin.BinError::new(
        @bin.InvalidValue,
        offset,
        "boxes.\{index}.size",
        "size=0 and extended size are mutually exclusive",
      ),
    )
  }
  if box.size_to_eof && index + 1 != count {
    return Err(
      @bin.BinError::new(
        @bin.InvalidValue,
        offset,
        "boxes.\{index}.size",
        "size=0 box must be the final box in its region",
      ),
    )
  }
  Ok(())
}

///|
pub fn bmff_codec() -> @bin.Codec[BmffFile] {
  @bin.Codec::make(
    fn(decoder) {
      let boxes : Array[BmffBox] = []
      while decoder.remaining() > 0 {
        if boxes.length() >= decoder.max_collection_length() {
          return Err(
            @bin.BinError::new(
              @bin.LimitExceeded,
              decoder.absolute_offset(),
              "boxes",
              "BMFF box count exceeds configured limit",
            ),
          )
        }
        let index = boxes.length()
        let prefix = "boxes.\{index}"
        let box_start = decoder.absolute_offset()
        let size32 = match
          @bin.u32_be().named(prefix + ".size").decode_from(decoder) {
          Err(error) => return Err(error)
          Ok(value) => value
        }
        let kind = match
          @bin.bytes_fixed(4).named(prefix + ".type").decode_from(decoder) {
          Err(error) => return Err(error)
          Ok(value) => value
        }
        let extended = size32 == 1U
        let uuid = kind == b"uuid"
        let total_size = if extended {
          let high = match
            @bin.u32_be().named(prefix + ".largesize_hi").decode_from(decoder) {
            Err(error) => return Err(error)
            Ok(value) => value
          }
          let low = match
            @bin.u32_be().named(prefix + ".largesize_lo").decode_from(decoder) {
            Err(error) => return Err(error)
            Ok(value) => value
          }
          if high != 0U || low > 0x7fffffffU {
            return Err(
              @bin.BinError::new(
                @bin.LimitExceeded,
                box_start,
                prefix + ".largesize",
                "BMFF box size exceeds this runtime's bounded input model",
              ),
            )
          }
          low.reinterpret_as_int()
        } else if size32 == 0U {
          0
        } else {
          if size32 > 0x7fffffffU {
            return Err(
              @bin.BinError::new(
                @bin.LimitExceeded,
                box_start,
                prefix + ".size",
                "BMFF box size exceeds this runtime's bounded input model",
              ),
            )
          }
          size32.reinterpret_as_int()
        }
        let user_type = if uuid {
          match
            @bin.bytes_fixed(16)
            .named(prefix + ".user_type")
            .decode_from(decoder) {
            Err(error) => return Err(error)
            Ok(value) => Some(value)
          }
        } else {
          None
        }
        let header_length = bmff_header_length(extended, uuid)
        let payload_length = if size32 == 0U {
          decoder.remaining()
        } else {
          if total_size < header_length {
            return Err(
              @bin.BinError::new(
                @bin.InvalidValue,
                box_start,
                prefix + ".size",
                "BMFF box size is smaller than its header",
              ),
            )
          }
          total_size - header_length
        }
        if payload_length > decoder.remaining() {
          return Err(
            @bin.BinError::new(
              @bin.UnexpectedEof,
              decoder.absolute_offset(),
              prefix + ".payload",
              "BMFF box payload exceeds the enclosing region",
            ),
          )
        }
        let payload = match
          @bin.bytes_fixed(payload_length)
          .named(prefix + ".payload")
          .decode_from(decoder) {
          Err(error) => return Err(error)
          Ok(value) => value
        }
        boxes.push({
          kind,
          extended_size: extended,
          size_to_eof: size32 == 0U,
          user_type,
          payload,
        })
      }
      Ok({ boxes, })
    },
    fn(encoder, value) {
      if value.boxes.length() > encoder.max_collection_length() {
        return Err(
          @bin.BinError::new(
            @bin.LimitExceeded,
            encoder.length(),
            "boxes",
            "BMFF box count exceeds configured limit",
          ),
        )
      }
      for index, box in value.boxes {
        match
          validate_bmff_box_for_encode(
            box,
            index,
            value.boxes.length(),
            encoder.length(),
          ) {
          Err(error) => return Err(error)
          Ok(_) => ()
        }
        let uuid = box.kind == b"uuid"
        let header_length = bmff_header_length(box.extended_size, uuid)
        let total_size = header_length + box.payload.length()
        if box.size_to_eof {
          match @bin.u32_be().encode_into(encoder, 0U) {
            Err(error) => return Err(error)
            Ok(_) => ()
          }
        } else if box.extended_size {
          match @bin.u32_be().encode_into(encoder, 1U) {
            Err(error) => return Err(error)
            Ok(_) => ()
          }
        } else {
          match
            @bin.u32_be().encode_into(encoder, total_size.reinterpret_as_uint()) {
            Err(error) => return Err(error)
            Ok(_) => ()
          }
        }
        match @bin.bytes_fixed(4).encode_into(encoder, box.kind) {
          Err(error) => return Err(error)
          Ok(_) => ()
        }
        if box.extended_size {
          match @bin.u32_be().encode_into(encoder, 0U) {
            Err(error) => return Err(error)
            Ok(_) => ()
          }
          match
            @bin.u32_be().encode_into(encoder, total_size.reinterpret_as_uint()) {
            Err(error) => return Err(error)
            Ok(_) => ()
          }
        }
        match box.user_type {
          Some(user_type) =>
            match @bin.bytes_fixed(16).encode_into(encoder, user_type) {
              Err(error) => return Err(error)
              Ok(_) => ()
            }
          None => ()
        }
        match
          @bin.bytes_fixed(box.payload.length()).encode_into(
            encoder,
            box.payload,
          ) {
          Err(error) => return Err(error)
          Ok(_) => ()
        }
      }
      Ok(())
    },
    kind="isobmff",
    render=fn(value) { "ISO BMFF with \{value.boxes.length()} boxes" },
    schema=bmff_schema(),
  )
}

///|
pub fn sample_bmff() -> Bytes {
  let value = BmffFile::{
    boxes: [
      {
        kind: b"ftyp",
        extended_size: false,
        size_to_eof: false,
        user_type: None,
        payload: b"isom\x00\x00\x02\x00isomiso2mp41",
      },
      {
        kind: b"free",
        extended_size: true,
        size_to_eof: false,
        user_type: None,
        payload: b"demo",
      },
      {
        kind: b"uuid",
        extended_size: false,
        size_to_eof: false,
        user_type: Some(b"0123456789abcdef"),
        payload: b"x",
      },
      {
        kind: b"mdat",
        extended_size: false,
        size_to_eof: true,
        user_type: None,
        payload: b"\x00\x01\x02\x03",
      },
    ],
  }
  match @bin.encode(bmff_codec(), value) {
    Ok(bytes) => bytes
    Err(_) => b""
  }
}
