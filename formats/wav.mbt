///|
pub(all) struct WavChunk {
  id : String
  data : Bytes
  padding : Byte?
} derive(Eq, Debug, ToJson)

///|
pub extend WavChunk with Eq::{not_equal, equal}

///|
pub extend WavChunk with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend WavChunk with ToJson::{to_json}

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
pub extend WavFormat with Eq::{not_equal, equal}

///|
pub extend WavFormat with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend WavFormat with ToJson::{to_json}

///|
pub(all) struct WavFile {
  riff_size : UInt
  chunks : Array[WavChunk]
  format : WavFormat?
} derive(Eq, Debug, ToJson)

///|
pub extend WavFile with Eq::{not_equal, equal}

///|
pub extend WavFile with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend WavFile with ToJson::{to_json}

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
fn parse_wav_format(
  data : Bytes,
  limits : @bin.Limits,
) -> Result[WavFormat, @bin.BinError] {
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
  let options = @bin.DecodeOptions::{ limits, require_eof: false, }
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
fn validate_wav_format(format : WavFormat) -> Result[Unit, String] {
  if format.channels == 0U || format.sample_rate == 0U {
    return Err("WAVE channels and sample rate must be non-zero")
  }
  if format.block_align == 0U ||
    format.byte_rate == 0U ||
    format.bits_per_sample == 0U {
    return Err(
      "WAVE block alignment, byte rate, and bit depth must be non-zero",
    )
  }
  if format.audio_format == 1U || format.audio_format == 3U {
    if format.bits_per_sample % 8U != 0U {
      return Err("PCM/IEEE-float bit depth must be byte-aligned")
    }
    let expected_block = format.channels.to_uint64() *
      (format.bits_per_sample / 8U).to_uint64()
    if format.block_align.to_uint64() != expected_block {
      return Err(
        "WAVE block alignment is inconsistent with channels and bit depth",
      )
    }
    let expected_rate = format.sample_rate.to_uint64() * expected_block
    if format.byte_rate.to_uint64() != expected_rate {
      return Err(
        "WAVE byte rate is inconsistent with sample rate and block alignment",
      )
    }
  }
  Ok(())
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
      let mut saw_data = false
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
          if format is Some(_) {
            return Err(
              @bin.BinError::new(
                @bin.InvalidValue,
                id_offset,
                prefix,
                "WAVE must contain exactly one fmt chunk",
              ),
            )
          }
          if saw_data {
            return Err(
              @bin.BinError::new(
                @bin.InvalidValue,
                id_offset,
                prefix,
                "fmt chunk must appear before data",
              ),
            )
          }
          let parsed = match parse_wav_format(data, decoder.limits) {
            Err(error) => return Err(error)
            Ok(value) => value
          }
          match validate_wav_format(parsed) {
            Err(message) =>
              return Err(
                @bin.BinError::new(
                  @bin.InvalidValue,
                  id_offset,
                  prefix,
                  message,
                ),
              )
            Ok(_) => format = Some(parsed)
          }
        } else if id == "data" {
          if format is None {
            return Err(
              @bin.BinError::new(
                @bin.InvalidValue,
                id_offset,
                prefix,
                "data chunk must appear after fmt",
              ),
            )
          }
          saw_data = true
        }
        chunks.push({ id, data, padding, })
      }
      if format is None || !saw_data {
        return Err(
          @bin.BinError::new(
            @bin.InvalidValue,
            decoder.absolute_offset(),
            "chunks",
            "WAVE requires one fmt chunk and at least one data chunk",
          ),
        )
      }
      Ok({ riff_size, chunks, format, })
    },
    fn(encoder, value) {
      let body = @bin.Encoder::new(encoder.limits)
      match @bin.magic(b"WAVE").encode_into(body, ()) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
      let mut saw_format = false
      let mut saw_data = false
      for index, chunk in value.chunks {
        if chunk.id == "fmt " {
          if saw_format || saw_data {
            return Err(
              @bin.BinError::new(
                @bin.InvalidValue,
                encoder.length(),
                "chunks.\{index}",
                "WAVE fmt chunk must be unique and appear before data",
              ),
            )
          }
          let parsed = match parse_wav_format(chunk.data, encoder.limits) {
            Err(error) => return Err(error)
            Ok(format) => format
          }
          match validate_wav_format(parsed) {
            Err(message) =>
              return Err(
                @bin.BinError::new(
                  @bin.InvalidValue,
                  encoder.length(),
                  "chunks.\{index}",
                  message,
                ),
              )
            Ok(_) => saw_format = true
          }
        } else if chunk.id == "data" {
          if !saw_format {
            return Err(
              @bin.BinError::new(
                @bin.InvalidValue,
                encoder.length(),
                "chunks.\{index}",
                "WAVE data chunk must appear after fmt",
              ),
            )
          }
          saw_data = true
        }
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
      if !saw_format || !saw_data {
        return Err(
          @bin.BinError::new(
            @bin.InvalidValue,
            encoder.length(),
            "chunks",
            "WAVE requires one fmt chunk and at least one data chunk",
          ),
        )
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
