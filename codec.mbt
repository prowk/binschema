///|
/// 一份 Codec 同时定义解码和编码行为。
pub struct Codec[T] {
  decode_impl : (Decoder) -> Result[T, BinError]
  encode_impl : (Encoder, T) -> Result[Unit, BinError]
  kind : String
  render : (T) -> String
  schema : SchemaNode
}

///|
pub fn[T] Codec::make(
  decode_impl : (Decoder) -> Result[T, BinError],
  encode_impl : (Encoder, T) -> Result[Unit, BinError],
  kind~ : String,
  render~ : (T) -> String,
  schema? : SchemaNode = SchemaNode::leaf(kind),
) -> Codec[T] {
  { decode_impl, encode_impl, kind, render, schema, }
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
/// 返回当前 Codec 的独立 Schema 快照。
pub fn[T] Codec::schema_node(self : Codec[T]) -> SchemaNode {
  self.schema.copy()
}

///|
/// 渲染当前 Codec 的 Schema 树。
pub fn[T] Codec::describe(self : Codec[T]) -> String {
  self.schema.render()
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
          Ok(value) =>
            match
              decoder.record(
                full_path,
                inner.kind,
                start,
                decoder.absolute_offset(),
                fn() { (inner.render)(value) },
              ) {
              Err(error) => Err(error)
              Ok(_) => Ok(value)
            }
        }
      })
    },
    fn(encoder, value) {
      encoder.with_path(name, fn() { inner.encode_into(encoder, value) })
    },
    kind=inner.kind,
    render=inner.render,
    schema=inner.schema.with_name(name),
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
          Err(
            BinError::new(
              InvalidValue,
              encoder.length(),
              encoder.path(),
              message,
            ),
          )
      }
    },
    kind=inner.kind,
    render~,
    schema=inner.schema,
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
    schema=SchemaNode::node("pair", [first.schema, second.schema]),
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
      if count > encoder.max_collection_length() {
        return Err(
          BinError::new(
            LimitExceeded,
            encoder.length(),
            encoder.path(),
            "repeat count exceeds collection limit",
          ),
        )
      }
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
    schema=SchemaNode::node("array", [item.schema], constraints=[
      "count=" + count.to_string(),
    ]),
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
        Err(
          BinError::new(InvalidValue, encoder.length(), encoder.path(), message),
        )
      }
    },
    kind=inner.kind,
    render=inner.render,
    schema=inner.schema.with_constraint("validate: " + message),
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
      match decoder.take_view(length) {
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
                match decoder.append_trace(child.trace()) {
                  Err(error) => Err(error)
                  Ok(_) => Ok(value)
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
    schema=SchemaNode::node("bounded", [body.schema], constraints=[
      "length=" + length.to_string(),
      "require_eof=" + (if require_eof { "true" } else { "false" }),
    ]),
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
          if length > max_length {
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
    schema=SchemaNode::node(
      "length-prefixed",
      [length_codec.schema.with_name("length"), body.schema],
      constraints=["max_length=" + max_length.to_string()],
    ),
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
    schema=SchemaNode::node("optional", [
      flag.schema.with_name("present"),
      item.schema.with_name("value"),
    ]),
  )
}

///|
/// 为任意字节对齐的主体增加尾随校验值。
pub fn[T] checksum_suffix_view(
  body : Codec[T],
  checksum_codec : Codec[UInt],
  calculate : (BytesView) -> UInt,
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
          let body_bytes = decoder.input[start:decoder.offset()]
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
                Ok(_) =>
                  checksum_codec.encode_into(encoder, calculate(bytes[:]))
              }
          }
      }
    },
    kind="checksummed",
    render=body.render,
    schema=SchemaNode::node("checksummed", [
      body.schema,
      checksum_codec.schema.with_name("checksum"),
    ]),
  )
}

///|
/// 兼容原有拥有型校验和回调。新代码优先使用 `checksum_suffix_view` 避免解码时复制。
pub fn[T] checksum_suffix(
  body : Codec[T],
  checksum_codec : Codec[UInt],
  calculate : (Bytes) -> UInt,
) -> Codec[T] {
  checksum_suffix_view(body, checksum_codec, fn(view) {
    calculate(view.to_owned())
  })
}

///|
/// 使用前置计数字段编解码数组。
pub fn[T] count_prefixed(
  count_codec : Codec[UInt],
  item : Codec[T],
  max_count? : Int = 1_000_000,
) -> Codec[Array[T]] {
  Codec::make(
    fn(decoder) {
      let raw_count = match count_codec.named("count").decode_from(decoder) {
        Err(error) => return Err(error)
        Ok(value) => value
      }
      if raw_count > 0x7fffffffU {
        return Err(
          BinError::new(
            LimitExceeded,
            decoder.absolute_offset(),
            decoder.path(),
            "collection count cannot be represented by this runtime",
          ),
        )
      }
      let count = raw_count.reinterpret_as_int()
      let effective_limit = if max_count < decoder.max_collection_length() {
        max_count
      } else {
        decoder.max_collection_length()
      }
      if count > effective_limit {
        return Err(
          BinError::new(
            LimitExceeded,
            decoder.absolute_offset(),
            decoder.path(),
            "collection count exceeds configured limit",
          ),
        )
      }
      repeat(count, item).decode_from(decoder)
    },
    fn(encoder, values) {
      let effective_limit = if max_count < encoder.max_collection_length() {
        max_count
      } else {
        encoder.max_collection_length()
      }
      if values.length() > effective_limit {
        return Err(
          BinError::new(
            LimitExceeded,
            encoder.length(),
            encoder.path(),
            "collection count exceeds configured limit",
          ),
        )
      }
      match
        count_codec.encode_into(encoder, values.length().reinterpret_as_uint()) {
        Err(error) => Err(error)
        Ok(_) => repeat(values.length(), item).encode_into(encoder, values)
      }
    },
    kind="count-prefixed-array",
    render=fn(values) { "[\{values.length()} items]" },
    schema=SchemaNode::node(
      "count-prefixed-array",
      [count_codec.schema.with_name("count"), item.schema],
      constraints=["max_count=" + max_count.to_string()],
    ),
  )
}

///|
/// 重复解码元素直到当前输入区域耗尽。每个元素必须至少消费一个字节。
pub fn[T] until_eof(item : Codec[T]) -> Codec[Array[T]] {
  Codec::make(
    fn(decoder) {
      let values : Array[T] = []
      while decoder.remaining() > 0 {
        if values.length() >= decoder.max_collection_length() {
          return Err(
            BinError::new(
              LimitExceeded,
              decoder.absolute_offset(),
              decoder.path(),
              "collection count exceeds configured limit",
            ),
          )
        }
        let before = decoder.offset()
        match item.named(values.length().to_string()).decode_from(decoder) {
          Err(error) => return Err(error)
          Ok(value) => values.push(value)
        }
        if decoder.offset() == before {
          return Err(
            BinError::new(
              InvalidValue,
              decoder.absolute_offset(),
              decoder.path(),
              "until_eof item codec must consume input",
            ),
          )
        }
      }
      Ok(values)
    },
    fn(encoder, values) {
      if values.length() > encoder.max_collection_length() {
        return Err(
          BinError::new(
            LimitExceeded,
            encoder.length(),
            encoder.path(),
            "collection count exceeds configured limit",
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
    kind="until-eof-array",
    render=fn(values) { "[\{values.length()} items]" },
    schema=SchemaNode::node("until-eof-array", [item.schema], constraints=[
      "terminates=current-region-eof",
    ]),
  )
}

///|
/// 由标签值动态选择后续 Codec，适合 tagged union / switch 协议。
pub fn[T] tagged(
  tag_codec : Codec[UInt],
  select : (UInt) -> Result[Codec[T], String],
  tag_of : (T) -> Result[UInt, String],
  render~ : (T) -> String,
) -> Codec[T] {
  Codec::make(
    fn(decoder) {
      let tag = match tag_codec.named("tag").decode_from(decoder) {
        Err(error) => return Err(error)
        Ok(value) => value
      }
      match select(tag) {
        Err(message) =>
          Err(
            BinError::new(
              InvalidValue,
              decoder.absolute_offset(),
              decoder.path(),
              message,
            ),
          )
        Ok(body) => body.named("value").decode_from(decoder)
      }
    },
    fn(encoder, value) {
      let tag = match tag_of(value) {
        Err(message) =>
          return Err(
            BinError::new(
              InvalidValue,
              encoder.length(),
              encoder.path(),
              message,
            ),
          )
        Ok(value) => value
      }
      let body = match select(tag) {
        Err(message) =>
          return Err(
            BinError::new(
              InvalidValue,
              encoder.length(),
              encoder.path(),
              message,
            ),
          )
        Ok(codec) => codec
      }
      match tag_codec.encode_into(encoder, tag) {
        Err(error) => Err(error)
        Ok(_) => body.encode_into(encoder, value)
      }
    },
    kind="tagged",
    render~,
    schema=SchemaNode::node("tagged", [tag_codec.schema.with_name("tag")], constraints=[
      "variants=dynamic",
    ]),
  )
}
