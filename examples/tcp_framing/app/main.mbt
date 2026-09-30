///|
const DEMO_CONNECTIONS : Int = 6

///|
const DEMO_IDLE_TIMEOUT_MS : Int = 120

///|
const SERVER_PORT : Int = 42042

///|
struct Logger((String) -> Unit)

///|
enum QueueItem {
  Frame(@bin.Decoded[@protocol.Message])
  DecodeFailure(@bin.BinError)
  Truncated(Int)
  IdleTimeout
  EndOfStream
}

///|
fn append_bytes(target : Array[Byte], bytes : BytesView) -> Unit {
  for byte in bytes {
    target.push(byte)
  }
}

///|
fn join_frames(frames : Array[Bytes]) -> Bytes {
  let output : Array[Byte] = []
  for frame in frames {
    append_bytes(output, frame[:])
  }
  Bytes::from_array(output)
}

///|
fn request(id : UInt, payload : String) -> Bytes {
  @protocol.encode_message(@protocol.EchoRequest((id, @utf8.encode(payload)))).unwrap()
}

///|
async fn enqueue_frame(
  queue : @aqueue.Queue[QueueItem],
  item : QueueItem,
  log : Logger,
) -> Unit {
  if !queue.try_put(item) {
    log("server: backpressure queue full, reader paused")
    queue.put(item)
  }
}

///|
async fn read_frames(
  conn : @socket.Tcp,
  queue : @aqueue.Queue[QueueItem],
  idle_timeout_ms : Int,
  log : Logger,
) -> Unit {
  let decoder = @bin.IncrementalDecoder::new(@protocol.frame_codec())
  for ;; {
    let read_result = @async.with_timeout_opt(idle_timeout_ms, async fn() {
      conn.read_some(max_len=1024)
    })
    match read_result {
      None => {
        queue.put(IdleTimeout)
        return
      }
      Some(None) => {
        if decoder.buffered_bytes() == 0 {
          queue.put(EndOfStream)
        } else {
          queue.put(Truncated(decoder.buffered_bytes()))
        }
        return
      }
      Some(Some(chunk)) =>
        match decoder.append(chunk) {
          Err(error) => {
            queue.put(DecodeFailure(error))
            return
          }
          Ok(_) =>
            for ;; {
              match decoder.poll() {
                @bin.Done(decoded) => enqueue_frame(queue, Frame(decoded), log)
                @bin.NeedMore => break
                @bin.Failed(error) => {
                  queue.put(DecodeFailure(error))
                  return
                }
              }
            }
        }
    }
  }
}

///|
async fn process_frames(
  conn : @socket.Tcp,
  queue : @aqueue.Queue[QueueItem],
  processing_delay_ms : Int,
  log : Logger,
) -> Unit {
  for ;; {
    match queue.get() {
      Frame(decoded) => {
        log(
          "server: decoded id=\{decoded.value.request_id()} trace=\{decoded.trace.length()}",
        )
        if processing_delay_ms > 0 {
          @async.sleep(processing_delay_ms)
        }
        match @protocol.response_for(decoded.value) {
          None => {
            log("server: unexpected response message")
            return
          }
          Some(response) =>
            match @protocol.encode_message(response) {
              Err(error) => {
                log("server: encode error: " + error.render())
                return
              }
              Ok(bytes) => conn.write(bytes)
            }
        }
      }
      DecodeFailure(error) => {
        log("server: decode error: " + error.render())
        return
      }
      Truncated(buffered) => {
        log("server: truncated frame at EOF, buffered=\{buffered}")
        return
      }
      IdleTimeout => {
        log("server: idle timeout")
        return
      }
      EndOfStream => return
    }
  }
}

///|
async fn handle_connection(
  conn : @socket.Tcp,
  idle_timeout_ms : Int,
  processing_delay_ms : Int,
  log : Logger,
) -> Unit {
  let queue : @aqueue.Queue[QueueItem] = @aqueue.Queue(kind=@aqueue.Blocking(2))
  @async.with_task_group(group => {
    group.spawn_bg(async fn() { read_frames(conn, queue, idle_timeout_ms, log) })
    group.spawn_bg(async fn() {
      process_frames(conn, queue, processing_delay_ms, log)
    })
  })
}

///|
async fn handle_owned_connection(
  conn : @socket.Tcp,
  idle_timeout_ms : Int,
  processing_delay_ms : Int,
  log : Logger,
) -> Unit {
  defer conn.close()
  handle_connection(conn, idle_timeout_ms, processing_delay_ms, log)
}

///|
async fn read_responses(
  conn : @socket.Tcp,
  expected : Int,
  log : Logger,
) -> Unit {
  let decoder = @bin.IncrementalDecoder::new(@protocol.frame_codec())
  let mut received = 0
  while received < expected {
    let chunk = @async.with_timeout_opt(1000, async fn() {
      conn.read_some(max_len=1024)
    })
    match chunk {
      None => abort("client timed out waiting for response")
      Some(None) => abort("server closed before all responses arrived")
      Some(Some(bytes)) => {
        decoder.append(bytes).unwrap()
        for ;; {
          match decoder.poll() {
            @bin.Done(decoded) => {
              guard decoded.value is @protocol.EchoResponse((id, payload)) else {
                abort("client received a request instead of a response")
              }
              log("client: response id=\{id} bytes=\{payload.length()}")
              received += 1
            }
            @bin.NeedMore => break
            @bin.Failed(error) => abort(error.render())
          }
        }
      }
    }
  }
}

///|
async fn expect_server_close(
  conn : @socket.Tcp,
  label : String,
  log : Logger,
) -> Unit {
  match @async.with_timeout_opt(1000, async fn() { conn.read_some() }) {
    Some(None) => log("client: \{label} rejected and connection closed")
    Some(Some(_)) => abort("unexpected response for \{label}")
    None => abort("server did not close after \{label}")
  }
}

///|
async fn run_client_case(
  addr : @socket.Addr,
  scenario : String,
  log : Logger,
) -> Unit {
  let conn = @socket.Tcp::connect(addr)
  defer conn.close()
  match scenario {
    "normal" => {
      conn.write(request(1U, "normal"))
      read_responses(conn, 1, log)
    }
    "fragmented" => {
      let frame = request(2U, "fragmented")
      for index in 0..<frame.length() {
        conn.write(frame[index:index + 1])
        @async.sleep(1)
      }
      read_responses(conn, 1, log)
    }
    "coalesced" => {
      let frames : Array[Bytes] = []
      for index in 0..<6 {
        frames.push(request((10 + index).reinterpret_as_uint(), "batch"))
      }
      conn.write(join_frames(frames))
      read_responses(conn, frames.length(), log)
    }
    "corrupt" => {
      let frame = request(3U, "corrupt").to_array()
      frame[frame.length() - 1] = (frame[frame.length() - 1].to_uint() ^ 1U).to_byte()
      conn.write(Bytes::from_array(frame))
      expect_server_close(conn, "checksum corruption", log)
    }
    "oversized" => {
      let length = (@protocol.MAX_FRAME_BYTES + 1).reinterpret_as_uint()
      conn.write(
        Bytes::from_array([
          ((length >> 24) & 0xffU).to_byte(),
          ((length >> 16) & 0xffU).to_byte(),
          ((length >> 8) & 0xffU).to_byte(),
          (length & 0xffU).to_byte(),
        ]),
      )
      expect_server_close(conn, "oversized frame", log)
    }
    "timeout" => {
      conn.write(b"\x00\x00")
      expect_server_close(conn, "idle partial frame", log)
    }
    _ => abort("unknown client scenario: " + scenario)
  }
}

///|
async fn run_demo(log_fn : (String) -> Unit) -> Unit {
  let log = Logger(log_fn)
  @async.with_task_group(async fn(group) {
    let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    let addr = server.addr
    log("demo: listening on \{addr}")
    group.spawn_bg(async fn() {
      for _ in 0..<DEMO_CONNECTIONS {
        let (conn, _) = server.accept()
        handle_owned_connection(conn, DEMO_IDLE_TIMEOUT_MS, 10, log)
      }
    })
    for
      scenario in [
        "normal", "fragmented", "coalesced", "corrupt", "oversized", "timeout",
      ] {
      log("demo: scenario=\{scenario}")
      run_client_case(addr, scenario, log)
    }
  })
  log("demo: all scenarios passed")
}

///|
async fn run_server(log : Logger) -> Unit {
  let addr = @socket.Addr::parse("127.0.0.1:\{SERVER_PORT}")
  log("server: listening on \{addr}")
  @socket.TcpServer(addr, reuse_addr=true).run_forever(
    allow_failure=true,
    max_connections=64,
    async fn(conn, peer) {
      log("server: accepted \{peer}")
      handle_connection(conn, 5000, 10, log)
    },
  )
}

///|
fn usage() -> String {
  let text =
    #|Usage:
    #|  moon run --target native examples/tcp_framing/app -- demo
    #|  moon run --target native examples/tcp_framing/app -- server
    #|  moon run --target native examples/tcp_framing/app -- client <normal|fragmented|coalesced|corrupt|oversized|timeout>
  text
}

///|
async fn main {
  let args = @env.args()
  let mode = if args.length() < 2 { "demo" } else { args[1] }
  let log = Logger(println)
  match mode {
    "demo" => run_demo(println)
    "server" => run_server(log)
    "client" => {
      if args.length() < 3 {
        println(usage())
        return
      }
      run_client_case(
        @socket.Addr::parse("127.0.0.1:\{SERVER_PORT}"),
        args[2],
        log,
      )
    }
    _ => println(usage())
  }
}
