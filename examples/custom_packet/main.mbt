///|
fn packet_codec() -> @bin.Codec[(Unit, (UInt, (UInt64, UInt)))] {
  @bin.pair(
    @bin.magic(b"BS").named("magic"),
    @bin.pair(
      @bin.u8().named("version"),
      @bin.pair(
        @bin.uleb128().named("stream_id"),
        @bin.u16_le().named("sequence"),
      ),
    ),
  )
}

///|
fn main {
  let packet = ((), (1U, (624485UL, 7U)))
  let codec = packet_codec()
  match @bin.encode(codec, packet) {
    Err(error) => println(error.render())
    Ok(bytes) => {
      println("encoded: " + @bin.bytes_to_hex(bytes))
      match @bin.decode(codec, bytes) {
        Err(error) => println(error.render())
        Ok(decoded) => {
          println("stream_id: \{decoded.value.1.1.0}")
          println("trace fields: \{decoded.trace.length()}")
        }
      }
    }
  }
}
