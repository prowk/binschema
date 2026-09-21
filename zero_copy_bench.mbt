///|
/// Compare the owned byte codec against the BytesView zero-copy path on a
/// payload large enough that benchmark harness overhead is negligible.
test "decode 64 KiB payload" (b : @bench.T) {
  let input = Bytes::makei(64 * 1024, fn(index) { (index % 251).to_byte() })
  let owned = bytes_fixed(input.length())
  let borrowed = bytes_view_fixed(input.length())

  b.bench(name="owned Bytes", fn() { b.keep(decode(owned, input)) })
  b.bench(name="borrowed BytesView", fn() {
    b.keep(decode_view(borrowed, input[:]))
  })
}
