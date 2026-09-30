///|
/// TCP 示例的最大包体长度。长度字段超过此值时会在等待包体前立即失败。
pub const MAX_FRAME_BYTES : Int = 64 * 1024

///|
/// 单条业务消息允许携带的最大 payload。
pub const MAX_PAYLOAD_BYTES : Int = 4 * 1024

///|
/// 示例协议的请求与响应共用同一份线格式。
pub(all) enum Message {
  EchoRequest((UInt, Bytes))
  EchoResponse((UInt, Bytes))
} derive(Eq, @debug.Debug)

///|
pub extend Message with Eq::{not_equal, equal}

///|
pub extend Message with @debug.Debug::{to_repr}

///|
pub fn Message::request_id(self : Message) -> UInt {
  match self {
    EchoRequest((request_id, _)) | EchoResponse((request_id, _)) => request_id
  }
}

///|
pub fn Message::payload(self : Message) -> Bytes {
  match self {
    EchoRequest((_, payload)) | EchoResponse((_, payload)) => payload
  }
}

///|
pub fn Message::render(self : Message) -> String {
  match self {
    EchoRequest((request_id, payload)) =>
      "EchoRequest(id=\{request_id}, bytes=\{payload.length()})"
    EchoResponse((request_id, payload)) =>
      "EchoResponse(id=\{request_id}, bytes=\{payload.length()})"
  }
}

///|
fn payload_codec() -> @bin.Codec[Bytes] {
  @bin.length_prefixed(
    @bin.u16_be(),
    @bin.remaining_bytes().named("payload"),
    max_length=MAX_PAYLOAD_BYTES,
  )
}

///|
fn request_codec() -> @bin.Codec[Message] {
  @bin.pair(@bin.u32_be().named("request_id"), payload_codec()).xmap(
    fn(value) { Ok(EchoRequest(value)) },
    fn(message) {
      match message {
        EchoRequest(value) => Ok(value)
        _ => Err("expected echo request")
      }
    },
    render=fn(message) { message.render() },
  )
}

///|
fn response_codec() -> @bin.Codec[Message] {
  @bin.pair(@bin.u32_be().named("request_id"), payload_codec()).xmap(
    fn(value) { Ok(EchoResponse(value)) },
    fn(message) {
      match message {
        EchoResponse(value) => Ok(value)
        _ => Err("expected echo response")
      }
    },
    render=fn(message) { message.render() },
  )
}

///|
fn message_codec() -> @bin.Codec[Message] {
  @bin.tagged(
    @bin.u8().named("message_type"),
    fn(tag) {
      match tag {
        1U => Ok(request_codec())
        2U => Ok(response_codec())
        _ => Err("unknown TCP example message type")
      }
    },
    fn(message) {
      match message {
        EchoRequest(_) => Ok(1U)
        EchoResponse(_) => Ok(2U)
      }
    },
    render=fn(message) { message.render() },
  )
}

///|
fn checksum8(bytes : BytesView) -> UInt {
  let mut sum = 0U
  for byte in bytes {
    sum = (sum + byte.to_uint()) & 0xffU
  }
  sum
}

///|
/// 完整线格式：u32_be 包体长度 + magic/version/message/checksum。
pub fn frame_codec() -> @bin.Codec[Message] {
  let body = @bin.pair(
    @bin.magic(b"BS").named("magic"),
    @bin.pair(
      @bin.u8()
      .validate(fn(value) { value == 1U }, "unsupported version")
      .named("version"),
      message_codec().named("message"),
    ),
  ).xmap(fn(value) { Ok(value.1.1) }, fn(message) { Ok(((), (1U, message))) }, render=fn(
    message,
  ) {
    message.render()
  })
  @bin.length_prefixed(
    @bin.u32_be(),
    @bin.checksum_suffix_view(body, @bin.u8().named("checksum"), checksum8),
    max_length=MAX_FRAME_BYTES,
  )
}

///|
pub fn encode_message(message : Message) -> Result[Bytes, @bin.BinError] {
  @bin.encode(frame_codec(), message)
}

///|
pub fn response_for(message : Message) -> Message? {
  match message {
    EchoRequest(value) => Some(EchoResponse(value))
    EchoResponse(_) => None
  }
}
