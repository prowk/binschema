///|
/// 增量解码的单步结果。
pub(all) enum DecodeStep[T] {
  Done(Decoded[T])
  NeedMore
  Failed(BinError)
}

///|
/// 解码一个前缀值，不要求消费完整输入。适合一块缓冲区中串联多个 frame。
pub fn[T] decode_prefix(
  codec : Codec[T],
  input : Bytes,
) -> Result[Decoded[T], BinError] {
  decode_prefix_with_options(codec, input, DecodeOptions::default())
}

///|
/// decode_prefix 的自定义限制版本。
pub fn[T] decode_prefix_with_options(
  codec : Codec[T],
  input : Bytes,
  options : DecodeOptions,
) -> Result[Decoded[T], BinError] {
  decode_prefix_view_with_options(codec, input[:], options)
}

///|
/// 前缀解码的零拷贝视图版本。
pub fn[T] decode_prefix_view(
  codec : Codec[T],
  input : BytesView,
) -> Result[Decoded[T], BinError] {
  decode_prefix_view_with_options(codec, input, DecodeOptions::default())
}

///|
/// 使用自定义限制进行零拷贝前缀解码。
pub fn[T] decode_prefix_view_with_options(
  codec : Codec[T],
  input : BytesView,
  options : DecodeOptions,
) -> Result[Decoded[T], BinError] {
  decode_view_with_options(codec, input, {
    limits: options.limits,
    require_eof: false,
  })
}

///|
/// 将 UnexpectedEof 解释为“需要更多数据”，其余错误保持为 Failed。
pub fn[T] probe_decode(codec : Codec[T], input : Bytes) -> DecodeStep[T] {
  probe_decode_with_options(codec, input, DecodeOptions::default())
}

///|
/// probe_decode 的自定义限制版本。
pub fn[T] probe_decode_with_options(
  codec : Codec[T],
  input : Bytes,
  options : DecodeOptions,
) -> DecodeStep[T] {
  match decode_prefix_with_options(codec, input, options) {
    Ok(decoded) => Done(decoded)
    Err({ kind: UnexpectedEof, .. }) => NeedMore
    Err(error) => Failed(error)
  }
}

///|
/// 可持续喂入字节块的帧解码器。成功解析一个值后，仅移除已消费前缀并保留尾部数据。
pub struct IncrementalDecoder[T] {
  codec : Codec[T]
  limits : Limits
  mut buffer : Array[Byte]
}

///|
pub fn[T] IncrementalDecoder::new(
  codec : Codec[T],
  limits? : Limits = Limits::default(),
) -> IncrementalDecoder[T] {
  { codec, limits, buffer: [], }
}

///|
/// 当前仍未消费的缓冲字节数。
pub fn[T] IncrementalDecoder::buffered_bytes(
  self : IncrementalDecoder[T],
) -> Int {
  self.buffer.length()
}

///|
/// 丢弃当前尚未消费的数据。
pub fn[T] IncrementalDecoder::clear(self : IncrementalDecoder[T]) -> Unit {
  self.buffer = []
}

///|
fn[T] IncrementalDecoder::drop_prefix(
  self : IncrementalDecoder[T],
  count : Int,
) -> Unit {
  let remaining : Array[Byte] = []
  for index in count..<self.buffer.length() {
    remaining.push(self.buffer[index])
  }
  self.buffer = remaining
}

///|
/// 仅追加字节，不立即重新解析。大量小 chunk 场景可先批量 append，再 poll，
/// 避免每个 chunk 都从缓冲区起点重试通用 codec。
pub fn[T] IncrementalDecoder::append(
  self : IncrementalDecoder[T],
  chunk : Bytes,
) -> Result[Unit, BinError] {
  if chunk.length() > self.limits.max_input_bytes - self.buffer.length() {
    return Err(
      BinError::new(
        LimitExceeded,
        self.buffer.length(),
        "",
        "incremental buffer exceeds max_input_bytes",
      ),
    )
  }
  for byte in chunk {
    self.buffer.push(byte)
  }
  Ok(())
}

///|
/// 在不追加新数据的情况下尝试解析一个 frame。
/// 通用 codec 会从当前缓冲区起点重新尝试，因此这属于 buffered/retry framing，
/// 不是 continuation-based parser。
pub fn[T] IncrementalDecoder::poll(
  self : IncrementalDecoder[T],
) -> DecodeStep[T] {
  let bytes = Bytes::from_array(self.buffer.copy())
  match
    probe_decode_with_options(self.codec, bytes, {
      limits: self.limits,
      require_eof: false,
    }) {
    Done(decoded) => {
      if decoded.consumed <= 0 {
        return Failed(
          BinError::new(
            InvalidValue,
            0,
            "",
            "incremental frame codec must consume at least one byte",
          ),
        )
      }
      self.drop_prefix(decoded.consumed)
      Done(decoded)
    }
    NeedMore => NeedMore
    Failed(error) => Failed(error)
  }
}

///|
/// 追加一个 chunk，并尝试解析一个 frame。
pub fn[T] IncrementalDecoder::feed(
  self : IncrementalDecoder[T],
  chunk : Bytes,
) -> DecodeStep[T] {
  match self.append(chunk) {
    Err(error) => Failed(error)
    Ok(_) => self.poll()
  }
}
