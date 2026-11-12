///|
/// 二进制整数的字节序。
#derive(Eq, Debug, ToJson)
pub(all) enum Endian {
  Big
  Little
}

///|
pub extend Endian with Eq::{not_equal, equal}

///|
pub extend Endian with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Endian with ToJson::{to_json}

///|
/// 统一的编解码错误分类。
#derive(Eq, Debug, ToJson)
pub(all) enum ErrorKind {
  UnexpectedEof
  Misaligned
  InvalidValue
  LimitExceeded
  ChecksumMismatch
  TrailingBytes
  Unsupported
}

///|
pub extend ErrorKind with Eq::{not_equal, equal}

///|
pub extend ErrorKind with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ErrorKind with ToJson::{to_json}

///|
/// 带绝对偏移和字段路径的错误。
#derive(Eq, Debug, ToJson)
pub struct BinError {
  kind : ErrorKind
  offset : Int32
  path : String
  message : String
}

///|
pub extend BinError with Eq::{not_equal, equal}

///|
pub extend BinError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend BinError with ToJson::{to_json}

///|
pub fn BinError::new(
  kind : ErrorKind,
  offset : Int32,
  path : String,
  message : String,
) -> BinError {
  { kind, offset, path, message, }
}

///|
/// 生成适合 CLI 和日志输出的稳定错误文本。
pub fn BinError::render(self : BinError) -> String {
  let location = if self.path == "" {
    "offset \{self.offset}"
  } else {
    "\{self.path} at offset \{self.offset}"
  }
  "\{self.kind.name()} (\{location}): \{self.message}"
}

///|
pub fn ErrorKind::name(self : ErrorKind) -> String {
  match self {
    UnexpectedEof => "UnexpectedEof"
    Misaligned => "Misaligned"
    InvalidValue => "InvalidValue"
    LimitExceeded => "LimitExceeded"
    ChecksumMismatch => "ChecksumMismatch"
    TrailingBytes => "TrailingBytes"
    Unsupported => "Unsupported"
  }
}

///|
/// 字段的解析轨迹，可用于 CLI 和浏览器可视化。
#derive(Eq, Debug, ToJson)
pub struct TraceEntry {
  path : String
  kind : String
  start : Int32
  end : Int32
  value : String
}

///|
pub extend TraceEntry with Eq::{not_equal, equal}

///|
pub extend TraceEntry with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend TraceEntry with ToJson::{to_json}

///|
/// 防止恶意长度字段造成过量内存或递归消耗。
#derive(Eq, Debug)
pub struct Limits {
  max_input_bytes : Int32
  max_collection_length : Int32
  max_depth : Int32
  max_output_bytes : Int32
  max_trace_entries : Int32
}

///|
pub extend Limits with Eq::{not_equal, equal}

///|
pub extend Limits with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub fn Limits::new(
  max_input_bytes~ : Int32 = 64 * 1024 * 1024,
  max_collection_length~ : Int32 = 1_000_000,
  max_depth~ : Int32 = 64,
  max_output_bytes~ : Int32 = 64 * 1024 * 1024,
  max_trace_entries~ : Int32 = 100_000,
) -> Limits {
  {
    max_input_bytes,
    max_collection_length,
    max_depth,
    max_output_bytes,
    max_trace_entries,
  }
}

///|
pub fn Limits::default() -> Limits {
  Limits::new()
}

///|
#derive(Eq, Debug)
pub(all) struct DecodeOptions {
  limits : Limits
  require_eof : Bool
}

///|
pub extend DecodeOptions with Eq::{not_equal, equal}

///|
pub extend DecodeOptions with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub fn DecodeOptions::default() -> DecodeOptions {
  { limits: Limits::default(), require_eof: true, }
}

///|
#derive(Eq, Debug)
pub(all) struct EncodeOptions {
  limits : Limits
}

///|
pub extend EncodeOptions with Eq::{not_equal, equal}

///|
pub extend EncodeOptions with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub fn EncodeOptions::default() -> EncodeOptions {
  { limits: Limits::default(), }
}

///|
/// 解码成功后的值、消费字节数和字段轨迹。
#derive(Debug)
pub struct Decoded[T] {
  value : T
  consumed : Int32
  trace : Array[TraceEntry]
}

///|
pub extend Decoded with @moonbitlang/core/debug.Debug::{to_repr}
