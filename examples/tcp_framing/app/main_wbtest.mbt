///|
async test "loopback demo covers framing failures, timeout, and backpressure" {
  let output = StringBuilder()
  run_demo(fn(line) { output..write_string(line).write_char('\n') })
  let text = output.to_string()
  assert_true(text.contains("scenario=fragmented"))
  assert_true(text.contains("scenario=coalesced"))
  assert_true(text.contains("backpressure queue full"))
  assert_true(text.contains("ChecksumMismatch"))
  assert_true(text.contains("LimitExceeded"))
  assert_true(text.contains("idle timeout"))
  assert_true(text.contains("all scenarios passed"))
}
