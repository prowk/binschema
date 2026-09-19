///|
pub(all) struct WavChunk {
  id : String
  data : Bytes
  padding : Byte?
} derive(Eq, Debug, ToJson)

///|
pub(all) struct WavFormat {
  audio_format : UInt
  channels : UInt
  sample_rate : UInt
  byte_rate : UInt
  block_align : UInt
  bits_per_sample : UInt
} derive(Eq, Debug, ToJson)

///|
pub(all) struct WavFile {
  riff_size : UInt
  chunks : Array[WavChunk]
  format : WavFormat?
} derive(Eq, Debug, ToJson)

///|
fn ascii_id(
  bytes : Bytes,
  field : String,
  offset : Int,
) -> Result[String, @bin.BinError] {
  if bytes.length() != 4 {
    return Err(
      @bin.BinError::new(
        @bin.InvalidValue,
        offset,
        field,
        "identifier must contain four bytes",
      ),
    )
  }
  for byte in bytes {
    let value = byte.to_int()
    if value < 32 || value > 126 {
      return Err(
        @bin.BinError::new(
          @bin.InvalidValue,
          offset,
          field,
          "identifier must contain printable ASCII bytes",
        ),
      )
    }
  }
  Ok(@utf8.decode_lossy(bytes[:]))
}

///|
fn parse_wav_format(data : Bytes) -> Result[WavFormat, @bin.BinError] {
  if data.length() < 16 {
    return Err(
      @bin.BinError::new(
        @bin.UnexpectedEof,
        0,
        "fmt",
        "WAVE fmt chunk must contain at least 16 bytes",
      ),
    )
  }
  let options = @bin.DecodeOptions::{
    limits: @bin.Limits::default(),
    require_eof: false,
  }
  let codec = @bin.Codec::make(
    fn(decoder) {
      let audio_format = match
        @bin.u16_le().named("audio_format").decode_from(decoder) {
        Err(error) => return Err(error)
        Ok(value) => value
      }
      let channels = match
        @bin.u16_le().named("channels").decode_from(decoder) {
        Err(error) => return Err(error)
        Ok(value) => value
      }
      let sample_rate = match
        @bin.u32_le().named("sample_rate").decode_from(decoder) {
        Err(error) => return Err(error)
        Ok(value) => value
      }
      let byte_rate = match
        @bin.u32_le().named("byte_rate").decode_from(decoder) {
        Err(error) => return Err(error)
        Ok(value) => value
      }
      let block_align = match
        @bin.u16_le().named("block_align").decode_from(decoder) {
        Err(error) => return Err(error)
        Ok(value) => value
      }
      let bits_per_sample = match
        @bin.u16_le().named("bits_per_sample").decode_from(decoder) {
        Err(error) => return Err(error)
        Ok(value) => value
      }
      Ok({
        audio_format,
        channels,
        sample_rate,
        byte_rate,
        block_align,
        bits_per_sample,
      })
    },
    fn(_, _) { Ok(()) },
    kind="wav-format",
    render=fn(_) { "WAVE format" },
  )
  match @bin.decode_with_options(codec, data, options) {
    Err(error) => Err(error)
    Ok(decoded) => Ok(decoded.value)
  }
}

///|
pub fn wav_codec() -> @bin.Codec[WavFile] {
  @bin.Codec::make(
    fn(decoder) {
      match @bin.magic(b"RIFF").named("signature").decode_from(decoder) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
      let riff_size = match
        @bin.u32_le().named("riff_size").decode_from(decoder) {
        Err(error) => return Err(error)
        Ok(value) => value
      }
      match @bin.magic(b"WAVE").named("form_type").decode_from(decoder) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
      if riff_size > 0x7fffffffU ||
        riff_size.reinterpret_as_int() + 8 != decoder.total_length() {
        return Err(
          @bin.BinError::new(
            @bin.InvalidValue,
            4,
            "riff_size",
            "RIFF size does not match file length",
          ),
        )
      }
      let chunks : Array[WavChunk] = []
      let mut format : WavFormat? = None
      while decoder.remaining() > 0 {
        if chunks.length() >= decoder.max_collection_length() {
          return Err(
            @bin.BinError::new(
              @bin.LimitExceeded,
              decoder.absolute_offset(),
              "chunks",
              "WAVE chunk count exceeds configured limit",
            ),
          )
        }
        let index = chunks.length()
        let prefix = "chunks.\{index}"
        let id_offset = decoder.absolute_offset()
        let id_bytes = match
          @bin.bytes_fixed(4).named(prefix + ".id").decode_from(decoder) {
          Err(error) => return Err(error)
          Ok(value) => value
        }
        let id = match ascii_id(id_bytes, prefix + ".id", id_offset) {
          Err(error) => return Err(error)
          Ok(value) => value
        }
        let raw_size = match
          @bin.u32_le().named(prefix + ".size").decode_from(decoder) {
          Err(error) => return Err(error)
          Ok(value) => value
        }
        if raw_size > 0x7fffffffU {
          return Err(
            @bin.BinError::new(
              @bin.LimitExceeded,
              decoder.absolute_offset(),
              prefix,
              "WAVE chunk is too large for this runtime",
            ),
          )
        }
        let size = raw_size.reinterpret_as_int()
        if size > decoder.max_collection_length() {
          return Err(
            @bin.BinError::new(
              @bin.LimitExceeded,
              decoder.absolute_offset(),
              prefix,
              "WAVE chunk exceeds configured collection limit",
            ),
          )
        }
        let data = match
          @bin.bytes_fixed(size).named(prefix + ".data").decode_from(decoder) {
          Err(error) => return Err(error)
          Ok(value) => value
        }
        let padding = if size % 2 == 1 {
          match
            @bin.bytes_fixed(1).named(prefix + ".padding").decode_from(decoder) {
            Err(error) => return Err(error)
            Ok(value) => Some(value[0])
          }
        } else {
          None
        }
        if id == "fmt " {
          match parse_wav_format(data) {
            Err(error) => return Err(error)
            Ok(value) => format = Some(value)
          }
        }
        chunks.push({ id, data, padding, })
      }
      Ok({ riff_size, chunks, format, })
    },
    fn(encoder, value) {
      let body = @bin.Encoder::new(@bin.Limits::default())
      match @bin.magic(b"WAVE").encode_into(body, ()) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
      for chunk in value.chunks {
        let id_bytes = @utf8.encode(chunk.id[:])
        if id_bytes.length() != 4 {
          return Err(
            @bin.BinError::new(
              @bin.InvalidValue,
              encoder.length(),
              "chunk.id",
              "WAVE chunk id must contain four ASCII bytes",
            ),
          )
        }
        match @bin.bytes_fixed(4).encode_into(body, id_bytes) {
          Err(error) => return Err(error)
          Ok(_) => ()
        }
        match
          @bin.u32_le().encode_into(
            body,
            chunk.data.length().reinterpret_as_uint(),
          ) {
          Err(error) => return Err(error)
          Ok(_) => ()
        }
        match
          @bin.bytes_fixed(chunk.data.length()).encode_into(body, chunk.data) {
          Err(error) => return Err(error)
          Ok(_) => ()
        }
        if chunk.data.length() % 2 == 1 {
          let padding = match chunk.padding {
            Some(value) => value
            None => b'\x00'
          }
          match
            @bin.bytes_fixed(1).encode_into(body, Bytes::from_array([padding])) {
            Err(error) => return Err(error)
            Ok(_) => ()
          }
        }
      }
      let body_bytes = match body.finish() {
        Err(error) => return Err(error)
        Ok(bytes) => bytes
      }
      match @bin.magic(b"RIFF").encode_into(encoder, ()) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
      match
        @bin.u32_le().encode_into(
          encoder,
          body_bytes.length().reinterpret_as_uint(),
        ) {
        Err(error) => return Err(error)
        Ok(_) => encoder.write_bytes(body_bytes[:])
      }
    },
    kind="wav",
    render=fn(value) { "WAVE with \{value.chunks.length()} chunks" },
  )
}

///|
pub fn sample_wav() -> Bytes {
  let fmt = b"\x01\x00\x01\x00\x40\x1f\x00\x00\x40\x1f\x00\x00\x01\x00\x08\x00"
  let chunks = [
    WavChunk::{ id: "fmt ", data: fmt, padding: None, },
    WavChunk::{ id: "data", data: b"\x00\x40\x80\xff", padding: None, },
  ]
  let value = WavFile::{ riff_size: 0U, chunks, format: None, }
  match @bin.encode(wav_codec(), value) {
    Ok(bytes) => bytes
    Err(_) => b""
  }
}
