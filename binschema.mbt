///|
/// BinSchema 的版本号。
pub const VERSION : String = "0.3.0"

///|
/// 使用安全默认限制解码完整输入。
pub fn[T] decode(
  codec : Codec[T],
  input : Bytes,
) -> Result[Decoded[T], BinError] {
  decode_view_with_options(codec, input[:], DecodeOptions::default())
}

///|
/// 从借用字节视图解码，允许返回引用原始输入的 `BytesView`。
pub fn[T] decode_view(
  codec : Codec[T],
  input : BytesView,
) -> Result[Decoded[T], BinError] {
  decode_view_with_options(codec, input, DecodeOptions::default())
}

///|
/// 使用自定义限制解码完整输入。
pub fn[T] decode_with_options(
  codec : Codec[T],
  input : Bytes,
  options : DecodeOptions,
) -> Result[Decoded[T], BinError] {
  decode_view_with_options(codec, input[:], options)
}

///|
/// `decode_with_options` 的零拷贝视图版本。
pub fn[T] decode_view_with_options(
  codec : Codec[T],
  input : BytesView,
  options : DecodeOptions,
) -> Result[Decoded[T], BinError] {
  guard input.length() <= options.limits.max_input_bytes else {
    return Err(
      BinError::new(LimitExceeded, 0, "", "input exceeds max_input_bytes"),
    )
  }
  let decoder = Decoder::new_view(input, options.limits)
  match codec.decode_from(decoder) {
    Err(error) => Err(error)
    Ok(value) =>
      if options.require_eof && decoder.remaining() != 0 {
        Err(
          BinError::new(
            TrailingBytes,
            decoder.absolute_offset(),
            decoder.path(),
            "trailing bytes after decoded value",
          ),
        )
      } else {
        Ok({ value, consumed: decoder.offset(), trace: decoder.trace(), })
      }
  }
}

///|
/// 将值编码成不可变字节串。
pub fn[T] encode(codec : Codec[T], value : T) -> Result[Bytes, BinError] {
  encode_with_options(codec, value, EncodeOptions::default())
}

///|
/// 使用自定义限制编码值。
pub fn[T] encode_with_options(
  codec : Codec[T],
  value : T,
  options : EncodeOptions,
) -> Result[Bytes, BinError] {
  let encoder = Encoder::new(options.limits)
  match codec.encode_into(encoder, value) {
    Err(error) => Err(error)
    Ok(_) => encoder.finish()
  }
}
