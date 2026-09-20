///|
/// 一份 Codec 同时定义解码和编码行为。
pub(all) struct Codec[T] {
  decode_impl : (Decoder) -> Result[T, BinError]
  encode_impl : (Encoder, T) -> Result[Unit, BinError]
  kind : String
  render : (T) -> String
}

///|
pub fn[T] Codec::make(
  decode_impl : (Decoder) -> Result[T, BinError],
  encode_impl : (Encoder, T) -> Result[Unit, BinError],
  kind~ : String,
  render~ : (T) -> String,
) -> Codec[T] {
  { decode_impl, encode_impl, kind, render, }
}

///|
pub fn[T] Codec::decode_from(
  self : Codec[T],
  decoder : Decoder,
) -> Result[T, BinError] {
  (self.decode_impl)(decoder)
}

///|
pub fn[T] Codec::encode_into(
  self : Codec[T],
  encoder : Encoder,
  value : T,
) -> Result[Unit, BinError] {
  (self.encode_impl)(encoder, value)
}

///|
/// 为字段增加稳定路径和字节范围追踪。
pub fn[T] Codec::named(self : Codec[T], name : String) -> Codec[T] {
  let inner = self
  Codec::make(
    fn(decoder) {
      let start = decoder.absolute_offset()
      let full_path = if decoder.path() == "" {
        name
      } else {
        decoder.path() + "." + name
      }
      decoder.with_path(name, fn() {
        match inner.decode_from(decoder) {
          Err(error) => Err(error)
          Ok(value) => {
            decoder.record(
              full_path,
              inner.kind,
              start,
              decoder.absolute_offset(),
              (inner.render)(value),
            )
            Ok(value)
          }
        }
      })
    },
    fn(encoder, value) {
      encoder.with_path(name, fn() { inner.encode_into(encoder, value) })
    },
    kind=inner.kind,
    render=inner.render,
  )
}

///|
/// 在不改变底层字节布局的前提下映射类型。
pub fn[A, B] Codec::xmap(
  self : Codec[A],
  decode_map : (A) -> Result[B, String],
  encode_map : (B) -> Result[A, String],
  render~ : (B) -> String,
) -> Codec[B] {
  let inner = self
  Codec::make(
    fn(decoder) {
      match inner.decode_from(decoder) {
        Err(error) => Err(error)
        Ok(value) =>
          match decode_map(value) {
            Ok(mapped) => Ok(mapped)
            Err(message) =>
              Err(
                BinError::new(
                  InvalidValue,
                  decoder.absolute_offset(),
                  decoder.path(),
                  message,
                ),
              )
          }
      }
    },
    fn(encoder, value) {
      match encode_map(value) {
        Ok(mapped) => inner.encode_into(encoder, mapped)
        Err(message) =>
          Err(BinError::new(InvalidValue, encoder.length(), encoder.path(), message))
      }
    },
    kind=inner.kind,
    render~,
  )
}

///|
/// 顺序组合两个 Codec。
pub fn[A, B] pair(first : Codec[A], second : Codec[B]) -> Codec[(A, B)] {
  Codec::make(
    fn(decoder) {
      match first.decode_from(decoder) {
        Err(error) => Err(error)
        Ok(left) =>
          match second.decode_from(decoder) {
            Err(error) => Err(error)
            Ok(right) => Ok((left, right))
          }
      }
    },
    fn(encoder, value) {
      match first.encode_into(encoder, value.0) {
        Err(error) => Err(error)
        Ok(_) => second.encode_into(encoder, value.1)
      }
    },
    kind="pair",
    render=fn(_) { "<pair>" },
  )
}

///|
/// 按固定数量重复元素 Codec。
pub fn[T] repeat(count : Int, item : Codec[T]) -> Codec[Array[T]] {
  Codec::make(
    fn(decoder) {
      if count < 0 {
        return Err(
          BinError::new(
            InvalidValue,
            decoder.absolute_offset(),
            decoder.path(),
            "repeat count cannot be negative",
          ),
        )
      }
      if count > decoder.limits.max_collection_length {
        return Err(
          BinError::new(
            LimitExceeded,
            decoder.absolute_offset(),
            decoder.path(),
            "repeat count exceeds collection limit",
          ),
        )
      }
      let values : Array[T] = []
      for index = 0; index < count; index = index + 1 {
        match item.named(index.to_string()).decode_from(decoder) {
          Err(error) => return Err(error)
          Ok(value) => values.push(value)
        }
      }
      Ok(values)
    },
    fn(encoder, values) {
      if values.length() != count {
        return Err(
          BinError::new(
            InvalidValue,
            encoder.length(),
            encoder.path(),
            "array length does not match fixed repeat count",
          ),
        )
      }
      for value in values {
        match item.encode_into(encoder, value) {
          Err(error) => return Err(error)
          Ok(_) => ()
        }
      }
      Ok(())
    },
    kind="array",
    render=fn(values) { "[\{values.length()} items]" },
  )
}

///|
/// 为 Codec 增加语义约束。
pub fn[T] Codec::validate(
  self : Codec[T],
  predicate : (T) -> Bool,
  message : String,
) -> Codec[T] {
  let inner = self
  Codec::make(
    fn(decoder) {
      match inner.decode_from(decoder) {
        Err(error) => Err(error)
        Ok(value) =>
          if predicate(value) {
            Ok(value)
          } else {
            Err(
              BinError::new(
                InvalidValue,
                decoder.absolute_offset(),
                decoder.path(),
                message,
              ),
            )
          }
      }
    },
    fn(encoder, value) {
      if predicate(value) {
        inner.encode_into(encoder, value)
      } else {
        Err(BinError::new(InvalidValue, encoder.length(), encoder.path(), message))
      }
    },
    kind=inner.kind,
    render=inner.render,
  )
}

///|
/// 将一个 Codec 限制在固定长度的子区域中。
pub fn[T] bounded(
  length : Int,
  body : Codec[T],
  require_eof? : Bool = true,
) -> Codec[T] {
  Codec::make(
    fn(decoder) {
      if decoder.depth() >= decoder.limits.max_depth {
        return Err(
          BinError::new(
            LimitExceeded,
            decoder.absolute_offset(),
            decoder.path(),
            "maximum decoder nesting depth exceeded",
          ),
        )
      }
      let start = decoder.absolute_offset()
      match decoder.take_bytes(length) {
        Err(error) => Err(error)
        Ok(bytes) => {
          let child = Decoder::new_child(
            bytes,
            start,
            decoder.path(),
            decoder.depth() + 1,
            decoder.limits,
          )
          match body.decode_from(child) {
            Err(error) => Err(error)
            Ok(value) =>
              if require_eof && child.remaining() != 0 {
                Err(
                  BinError::new(
                    TrailingBytes,
                    child.absolute_offset(),
                    child.path(),
                    "trailing bytes in bounded field",
                  ),
                )
              } else {
                decoder.append_trace(child.trace())
                Ok(value)
              }
          }
        }
      }
    },
    fn(encoder, value) {
      let child = Encoder::new(encoder.limits)
      match body.encode_into(child, value) {
        Err(error) => Err(error)
        Ok(_) =>
          match child.finish() {
            Err(error) => Err(error)
            Ok(bytes) =>
              if bytes.length() != length {
                Err(
                  BinError::new(
                    InvalidValue,
                    encoder.length(),
                    encoder.path(),
                    "encoded value does not match bounded length",
                  ),
                )
              } else {
                encoder.write_bytes(bytes[:])
              }
          }
      }
    },
    kind="bounded[\{length}]",
    render=body.render,
  )
}

///|
/// 使用无符号长度字段限定后续值。
pub fn[T] length_prefixed(
  length_codec : Codec[UInt],
  body : Codec[T],
  max_length? : Int = 16 * 1024 * 1024,
) -> Codec[T] {
  Codec::make(
    fn(decoder) {
      match length_codec.named("length").decode_from(decoder) {
        Err(error) => Err(error)
        Ok(raw_length) => {
          if raw_length > 0x7fffffffU {
            return Err(
              BinError::new(
                LimitExceeded,
                decoder.absolute_offset(),
                decoder.path(),
                "length cannot be represented by this runtime",
              ),
            )
          }
          let length = raw_length.reinterpret_as_int()
          if length > max_length || length > decoder.max_collection_length() {
            return Err(
              BinError::new(
                LimitExceeded,
                decoder.absolute_offset(),
                decoder.path(),
                "length-prefixed field exceeds configured limit",
              ),
            )
          }
          bounded(length, body).decode_from(decoder)
        }
      }
    },
    fn(encoder, value) {
      let child = Encoder::new(encoder.limits)
      match body.encode_into(child, value) {
        Err(error) => Err(error)
        Ok(_) =>
          match child.finish() {
            Err(error) => Err(error)
            Ok(bytes) => {
              if bytes.length() > max_length {
                return Err(
                  BinError::new(
                    LimitExceeded,
                    encoder.length(),
                    encoder.path(),
                    "length-prefixed field exceeds configured limit",
                  ),
                )
              }
              match
                length_codec.encode_into(
                  encoder,
                  bytes.length().reinterpret_as_uint(),
                ) {
                Err(error) => Err(error)
                Ok(_) => encoder.write_bytes(bytes[:])
              }
            }
          }
      }
    },
    kind="length-prefixed",
    render=body.render,
  )
}

///|
/// 编解码带显式存在标记的可选字段。
pub fn[T] optional_if(flag : Codec[Bool], item : Codec[T]) -> Codec[T?] {
  Codec::make(
    fn(decoder) {
      match flag.named("present").decode_from(decoder) {
        Err(error) => Err(error)
        Ok(false) => Ok(None)
        Ok(true) =>
          match item.named("value").decode_from(decoder) {
            Err(error) => Err(error)
            Ok(value) => Ok(Some(value))
          }
      }
    },
    fn(encoder, value) {
      match value {
        None => flag.encode_into(encoder, false)
        Some(actual) =>
          match flag.encode_into(encoder, true) {
            Err(error) => Err(error)
            Ok(_) => item.encode_into(encoder, actual)
          }
      }
    },
    kind="optional",
    render=fn(value) {
      match value {
        None => "none"
        Some(actual) => (item.render)(actual)
      }
    },
  )
}

///|
/// 为任意字节对齐的主体增加尾随校验值。
pub fn[T] checksum_suffix(
  body : Codec[T],
  checksum_codec : Codec[UInt],
  calculate : (Bytes) -> UInt,
) -> Codec[T] {
  Codec::make(
    fn(decoder) {
      if decoder.bit_offset != 0 {
        return Err(
          BinError::new(
            Misaligned,
            decoder.absolute_offset(),
            decoder.path(),
            "checksum body must start on a byte boundary",
          ),
        )
      }
      let start = decoder.offset()
      match body.decode_from(decoder) {
        Err(error) => Err(error)
        Ok(value) => {
          if decoder.bit_offset != 0 {
            return Err(
              BinError::new(
                Misaligned,
                decoder.absolute_offset(),
                decoder.path(),
                "checksum body must end on a byte boundary",
              ),
            )
          }
          let body_bytes = decoder.input[start:decoder.offset()].to_owned()
          match checksum_codec.named("checksum").decode_from(decoder) {
            Err(error) => Err(error)
            Ok(expected) => {
              let actual = calculate(body_bytes)
              if actual == expected {
                Ok(value)
              } else {
                Err(
                  BinError::new(
                    ChecksumMismatch,
                    decoder.absolute_offset(),
                    decoder.path(),
                    "checksum mismatch: expected \{expected}, calculated \{actual}",
                  ),
                )
              }
            }
          }
        }
      }
    },
    fn(encoder, value) {
      let child = Encoder::new(encoder.limits)
      match body.encode_into(child, value) {
        Err(error) => Err(error)
        Ok(_) =>
          match child.finish() {
            Err(error) => Err(error)
            Ok(bytes) =>
              match encoder.write_bytes(bytes[:]) {
                Err(error) => Err(error)
                Ok(_) => checksum_codec.encode_into(encoder, calculate(bytes))
              }
          }
      }
    },
    kind="checksummed",
    render=body.render,
  )
}
