///|
/// 二进制整数的字节序。
pub(all) enum Endian {
  Big
  Little
} derive(Eq, Debug, ToJson)

///|
pub extend Endian with Eq::{not_equal, equal}

///|
pub extend Endian with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Endian with ToJson::{to_json}

///|
/// 统一的编解码错误分类。
pub(all) enum ErrorKind {
  UnexpectedEof
  Misaligned
  InvalidValue
  LimitExceeded
  ChecksumMismatch
  TrailingBytes
  Unsupported
} derive(Eq, Debug, ToJson)

///|
pub extend ErrorKind with Eq::{not_equal, equal}

///|
pub extend ErrorKind with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ErrorKind with ToJson::{to_json}

///|
/// 带绝对偏移和字段路径的错误。
pub struct BinError {
  kind : ErrorKind
  offset : Int
  path : String
  message : String
} derive(Eq, Debug, ToJson)

///|
pub extend BinError with Eq::{not_equal, equal}

///|
pub extend BinError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend BinError with ToJson::{to_json}

///|
pub fn BinError::new(
  kind : ErrorKind,
  offset : Int,
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
pub struct TraceEntry {
  path : String
  kind : String
  start : Int
  end : Int
  value : String
} derive(Eq, Debug, ToJson)

///|
pub extend TraceEntry with Eq::{not_equal, equal}

///|
pub extend TraceEntry with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend TraceEntry with ToJson::{to_json}

///|
/// 防止恶意长度字段造成过量内存或递归消耗。
pub struct Limits {
  max_input_bytes : Int
  max_collection_length : Int
  max_depth : Int
  max_output_bytes : Int
  max_trace_entries : Int
} derive(Eq, Debug)

///|
pub extend Limits with Eq::{not_equal, equal}

///|
pub extend Limits with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub fn Limits::new(
  max_input_bytes? : Int = 64 * 1024 * 1024,
  max_collection_length? : Int = 1_000_000,
  max_depth? : Int = 64,
  max_output_bytes? : Int = 64 * 1024 * 1024,
  max_trace_entries? : Int = 100_000,
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
pub(all) struct DecodeOptions {
  limits : Limits
  require_eof : Bool
} derive(Eq, Debug)

///|
pub extend DecodeOptions with Eq::{not_equal, equal}

///|
pub extend DecodeOptions with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub fn DecodeOptions::default() -> DecodeOptions {
  { limits: Limits::default(), require_eof: true, }
}

///|
pub(all) struct EncodeOptions {
  limits : Limits
} derive(Eq, Debug)

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
pub struct Decoded[T] {
  value : T
  consumed : Int
  trace : Array[TraceEntry]
} derive(Debug)

///|
pub extend Decoded with @moonbitlang/core/debug.Debug::{to_repr}
