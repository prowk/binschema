///|
pub(all) struct PngChunk {
  kind : String
  data : Bytes
  crc : UInt
} derive(Eq, Debug, ToJson)

///|
pub extend PngChunk with Eq::{not_equal, equal}

///|
pub extend PngChunk with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend PngChunk with ToJson::{to_json}

///|
pub(all) struct PngFile {
  chunks : Array[PngChunk]
} derive(Eq, Debug, ToJson)

///|
pub extend PngFile with Eq::{not_equal, equal}

///|
pub extend PngFile with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend PngFile with ToJson::{to_json}

///|
fn ascii_chunk_type(bytes : Bytes) -> Result[String, String] {
  if bytes.length() != 4 {
    return Err("PNG chunk type must contain four bytes")
  }
  for byte in bytes {
    let value = byte.to_int()
    if !((value >= 65 && value <= 90) || (value >= 97 && value <= 122)) {
      return Err("PNG chunk type must contain ASCII letters")
    }
  }
  Ok(@utf8.decode_lossy(bytes[:]))
}

///|
fn png_uint32_at(bytes : Bytes, offset : Int) -> UInt {
  (bytes[offset].to_uint() << 24) |
  (bytes[offset + 1].to_uint() << 16) |
  (bytes[offset + 2].to_uint() << 8) |
  bytes[offset + 3].to_uint()
}

///|
fn validate_png_chunk(
  index : Int,
  kind : String,
  data : Bytes,
) -> Result[Unit, String] {
  let kind_bytes = @utf8.encode(kind[:])
  match ascii_chunk_type(kind_bytes) {
    Err(message) => return Err(message)
    Ok(_) => ()
  }
  if index == 0 && kind != "IHDR" {
    return Err("IHDR must be the first PNG chunk")
  }
  if index > 0 && kind == "IHDR" {
    return Err("IHDR must appear exactly once")
  }
  let reserved = kind.code_unit_at(2).to_int()
  if reserved < 65 || reserved > 90 {
    return Err("PNG chunk reserved bit must be zero (uppercase third letter)")
  }
  if kind == "IHDR" {
    if data.length() != 13 {
      return Err("IHDR data must contain exactly 13 bytes")
    }
    if png_uint32_at(data, 0) == 0U || png_uint32_at(data, 4) == 0U {
      return Err("PNG width and height must be non-zero")
    }
    let bit_depth = data[8].to_uint()
    let color_type = data[9].to_uint()
    let valid_depth = match color_type {
      0U => bit_depth == 1U || bit_depth == 2U || bit_depth == 4U ||
        bit_depth == 8U || bit_depth == 16U
      2U | 4U | 6U => bit_depth == 8U || bit_depth == 16U
      3U => bit_depth == 1U || bit_depth == 2U || bit_depth == 4U ||
        bit_depth == 8U
      _ => false
    }
    if !valid_depth {
      return Err("IHDR color type and bit depth combination is invalid")
    }
    if data[10].to_uint() != 0U || data[11].to_uint() != 0U {
      return Err("IHDR compression and filter methods must be zero")
    }
    if data[12].to_uint() > 1U {
      return Err("IHDR interlace method must be 0 or 1")
    }
  }
  if kind == "IEND" && data.length() != 0 {
    return Err("IEND data must be empty")
  }
  Ok(())
}

///|
fn validate_png_file(value : PngFile) -> Result[Unit, String] {
  if value.chunks.length() < 2 {
    return Err("PNG must contain IHDR and IEND chunks")
  }
  for index, chunk in value.chunks {
    match validate_png_chunk(index, chunk.kind, chunk.data) {
      Err(message) => return Err(message)
      Ok(_) => ()
    }
    if chunk.kind == "IEND" && index != value.chunks.length() - 1 {
      return Err("IEND must be the final PNG chunk")
    }
  }
  if value.chunks[value.chunks.length() - 1].kind != "IEND" {
    return Err("PNG must end with IEND")
  }
  Ok(())
}

///|
fn png_schema() -> @bin.SchemaNode {
  @bin.SchemaNode::node(
    "png",
    [
      @bin.SchemaNode::leaf("bytes[8]").with_name("signature"),
      @bin.SchemaNode::node(
        "chunks",
        [
          @bin.SchemaNode::node(
            "chunk",
            [
              @bin.SchemaNode::leaf("u32be").with_name("length"),
              @bin.SchemaNode::leaf("bytes[4]").with_name("type"),
              @bin.SchemaNode::leaf("bytes[length]").with_name("data"),
              @bin.SchemaNode::leaf("u32be").with_name("crc"),
            ],
            constraints=["crc32(type+data)"],
          ),
        ],
        constraints=["repeat=until-IEND", "max_count=runtime-limit"],
      ),
    ],
    constraints=["signature=PNG", "IHDR-first", "IEND-last"],
  )
}

///|
pub fn png_codec() -> @bin.Codec[PngFile] {
  @bin.Codec::make(
    fn(decoder) {
      match
        @bin.magic(b"\x89PNG\x0d\x0a\x1a\x0a")
        .named("signature")
        .decode_from(decoder) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
      let chunks : Array[PngChunk] = []
      let mut finished = false
      while !finished {
        if chunks.length() >= decoder.max_collection_length() {
          return Err(
            @bin.BinError::new(
              @bin.LimitExceeded,
              decoder.absolute_offset(),
              decoder.path(),
              "PNG chunk count exceeds configured limit",
            ),
          )
        }
        let index = chunks.length()
        let prefix = "chunks.\{index}"
        let length = match
          @bin.u32_be().named(prefix + ".length").decode_from(decoder) {
          Err(error) => return Err(error)
          Ok(value) => value
        }
        if length > 0x7fffffffU {
          return Err(
            @bin.BinError::new(
              @bin.LimitExceeded,
              decoder.absolute_offset(),
              prefix,
              "PNG chunk is too large for this runtime",
            ),
          )
        }
        let byte_length = length.reinterpret_as_int()
        let type_bytes = match
          @bin.bytes_fixed(4).named(prefix + ".type").decode_from(decoder) {
          Err(error) => return Err(error)
          Ok(value) => value
        }
        let kind = match ascii_chunk_type(type_bytes) {
          Err(message) =>
            return Err(
              @bin.BinError::new(
                @bin.InvalidValue,
                decoder.absolute_offset() - 4,
                prefix + ".type",
                message,
              ),
            )
          Ok(value) => value
        }
        let data = match
          @bin.bytes_fixed(byte_length)
          .named(prefix + ".data")
          .decode_from(decoder) {
          Err(error) => return Err(error)
          Ok(value) => value
        }
        match validate_png_chunk(index, kind, data) {
          Err(message) =>
            return Err(
              @bin.BinError::new(
                @bin.InvalidValue,
                decoder.absolute_offset() - data.length(),
                prefix,
                message,
              ),
            )
          Ok(_) => ()
        }
        let crc_offset = decoder.absolute_offset()
        let expected = match
          @bin.u32_be().named(prefix + ".crc").decode_from(decoder) {
          Err(error) => return Err(error)
          Ok(value) => value
        }
        let actual = crc32(chunk_crc_input(kind, data))
        if actual != expected {
          return Err(
            @bin.BinError::new(
              @bin.ChecksumMismatch,
              crc_offset,
              prefix + ".crc",
              "PNG CRC mismatch: expected \{expected}, calculated \{actual}",
            ),
          )
        }
        chunks.push({ kind, data, crc: expected, })
        if kind == "IEND" {
          finished = true
        }
      }
      Ok({ chunks, })
    },
    fn(encoder, value) {
      if value.chunks.length() > encoder.max_collection_length() {
        return Err(
          @bin.BinError::new(
            @bin.LimitExceeded,
            encoder.length(),
            "chunks",
            "PNG chunk count exceeds configured limit",
          ),
        )
      }
      match validate_png_file(value) {
        Err(message) =>
          return Err(
            @bin.BinError::new(
              @bin.InvalidValue,
              encoder.length(),
              "png",
              message,
            ),
          )
        Ok(_) => ()
      }
      match @bin.magic(b"\x89PNG\x0d\x0a\x1a\x0a").encode_into(encoder, ()) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
      for chunk in value.chunks {
        let kind_bytes = @utf8.encode(chunk.kind[:])
        if kind_bytes.length() != 4 {
          return Err(
            @bin.BinError::new(
              @bin.InvalidValue,
              encoder.length(),
              "chunk.type",
              "PNG chunk type must contain four ASCII bytes",
            ),
          )
        }
        match
          @bin.u32_be().encode_into(
            encoder,
            chunk.data.length().reinterpret_as_uint(),
          ) {
          Err(error) => return Err(error)
          Ok(_) => ()
        }
        match @bin.bytes_fixed(4).encode_into(encoder, kind_bytes) {
          Err(error) => return Err(error)
          Ok(_) => ()
        }
        match
          @bin.bytes_fixed(chunk.data.length()).encode_into(encoder, chunk.data) {
          Err(error) => return Err(error)
          Ok(_) => ()
        }
        let actual = crc32(chunk_crc_input(chunk.kind, chunk.data))
        if chunk.crc != actual {
          return Err(
            @bin.BinError::new(
              @bin.InvalidValue,
              encoder.length(),
              "chunk.crc",
              "PNG chunk CRC does not match type and data",
            ),
          )
        }
        match @bin.u32_be().encode_into(encoder, actual) {
          Err(error) => return Err(error)
          Ok(_) => ()
        }
      }
      Ok(())
    },
    kind="png",
    render=fn(value) { "PNG with \{value.chunks.length()} chunks" },
    schema=png_schema(),
  )
}

///|
pub fn sample_png() -> Bytes {
  let ihdr = b"\x00\x00\x00\x01\x00\x00\x00\x01\x08\x00\x00\x00\x00"
  let idat = b"\x78\x9c\x63\x60\x00\x00\x00\x02\x00\x01"
  let chunks = [
    PngChunk::{ kind: "IHDR", data: ihdr, crc: crc32(chunk_crc_input("IHDR", ihdr)), },
    PngChunk::{
      kind: "IDAT",
      data: idat,
      crc: crc32(chunk_crc_input("IDAT", idat)),
    },
    PngChunk::{ kind: "IEND", data: b"", crc: crc32(chunk_crc_input("IEND", b"")), },
  ]
  match @bin.encode(png_codec(), { chunks, }) {
    Ok(bytes) => bytes
    Err(_) => b""
  }
}
