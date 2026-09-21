///|
enum DemoMessage {
  Counter(UInt)
  Sensor((UInt, UInt))
  Blob(Bytes)
} derive(Eq, @debug.Debug)

///|
fn DemoMessage::render(self : DemoMessage) -> String {
  match self {
    Counter(value) => "Counter(\{value})"
    Sensor((sensor_id, reading)) =>
      "Sensor(id=\{sensor_id}, reading=\{reading})"
    Blob(bytes) => "Blob(\{bytes.length()} bytes)"
  }
}

///|
fn counter_codec() -> @bin.Codec[DemoMessage] {
  @bin.u32_le().xmap(
    fn(value) { Ok(Counter(value)) },
    fn(message) {
      match message {
        Counter(value) => Ok(value)
        _ => Err("expected Counter message")
      }
    },
    render=fn(message) { message.render() },
  )
}

///|
fn sensor_codec() -> @bin.Codec[DemoMessage] {
  @bin.pair(@bin.u16_le().named("sensor_id"), @bin.u16_le().named("reading")).xmap(
    fn(value) { Ok(Sensor(value)) },
    fn(message) {
      match message {
        Sensor(value) => Ok(value)
        _ => Err("expected Sensor message")
      }
    },
    render=fn(message) { message.render() },
  )
}

///|
fn blob_codec() -> @bin.Codec[DemoMessage] {
  @bin.length_prefixed(
    @bin.u16_le(),
    @bin.remaining_bytes().named("payload"),
    max_length=4096,
  ).xmap(
    fn(bytes) { Ok(Blob(bytes)) },
    fn(message) {
      match message {
        Blob(bytes) => Ok(bytes)
        _ => Err("expected Blob message")
      }
    },
    render=fn(message) { message.render() },
  )
}

///|
fn message_codec() -> @bin.Codec[DemoMessage] {
  @bin.tagged(
    @bin.u8(),
    fn(tag) {
      match tag {
        1U => Ok(counter_codec())
        2U => Ok(sensor_codec())
        3U => Ok(blob_codec())
        _ => Err("unknown demo message tag")
      }
    },
    fn(message) {
      match message {
        Counter(_) => Ok(1U)
        Sensor(_) => Ok(2U)
        Blob(_) => Ok(3U)
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
fn demo_protocol_codec() -> @bin.Codec[
  (Unit, (UInt, (UInt, Array[DemoMessage]))),
] {
  let body = @bin.pair(
    @bin.magic(b"BS").named("magic"),
    @bin.pair(
      @bin.u8()
      .validate(fn(value) { value == 1U }, "unsupported version")
      .named("version"),
      @bin.pair(
        @bin.u8().named("flags"),
        @bin.count_prefixed(
          @bin.u8(),
          message_codec().named("message"),
          max_count=32,
        ).named("messages"),
      ),
    ),
  )
  @bin.checksum_suffix_view(body, @bin.u8().named("checksum"), checksum8)
}

///|
fn main {
  let packet = (
    (),
    (1U, (0x01U, [Counter(42U), Sensor((7U, 900U)), Blob(b"hello")])),
  )
  let codec = demo_protocol_codec()
  match @bin.encode(codec, packet) {
    Err(error) => println(error.render())
    Ok(bytes) => {
      println("encoded: " + @bin.bytes_to_hex(bytes))
      match @bin.decode(codec, bytes) {
        Err(error) => println(error.render())
        Ok(decoded) => {
          println("messages: \{decoded.value.1.1.1.length()}")
          println("roundtrip bytes: \{decoded.consumed}")
          println("trace fields: \{decoded.trace.length()}")
          for entry in decoded.trace {
            println(
              "[\{entry.start}, \{entry.end}) \{entry.path} = \{entry.value}",
            )
          }
        }
      }
    }
  }
}
