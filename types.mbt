///|
/// 二进制整数的字节序。
pub(all) enum Endian {
  Big
  Little
} derive(Eq, Debug, ToJson)

pub extend Endian with Eq::{not_equal, equal}
pub extend Endian with @moonbitlang/core/debug.Debug::{to_repr}
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

pub extend ErrorKind with Eq::{not_equal, equal}
pub extend ErrorKind with @moonbitlang/core/debug.Debug::{to_repr}
pub extend ErrorKind with ToJson::{to_json}

///|
/// 带绝对偏移和字段路径的错误。
pub(all) struct BinError {
  kind : ErrorKind
  offset : Int
  path : String
  message : String
} derive(Eq, Debug, ToJson)

pub extend BinError with Eq::{not_equal, equal}
pub extend BinError with @moonbitlang/core/debug.Debug::{to_repr}
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
pub(all) struct TraceEntry {
  path : String
  kind : String
  start : Int
  end : Int
  value : String
} derive(Eq, Debug, ToJson)

pub extend TraceEntry with Eq::{not_equal, equal}
pub extend TraceEntry with @moonbitlang/core/debug.Debug::{to_repr}
pub extend TraceEntry with ToJson::{to_json}

///|
/// 防止恶意长度字段造成过量内存或递归消耗。
pub(all) struct Limits {
  max_input_bytes : Int
  max_collection_length : Int
  max_depth : Int
  max_output_bytes : Int
} derive(Eq, Debug)

pub extend Limits with Eq::{not_equal, equal}
pub extend Limits with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub fn Limits::default() -> Limits {
  {
    max_input_bytes: 64 * 1024 * 1024,
    max_collection_length: 1_000_000,
    max_depth: 64,
    max_output_bytes: 64 * 1024 * 1024,
  }
}

///|
pub(all) struct DecodeOptions {
  limits : Limits
  require_eof : Bool
} derive(Eq, Debug)

pub extend DecodeOptions with Eq::{not_equal, equal}
pub extend DecodeOptions with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub fn DecodeOptions::default() -> DecodeOptions {
  { limits: Limits::default(), require_eof: true, }
}

///|
pub(all) struct EncodeOptions {
  limits : Limits
} derive(Eq, Debug)

pub extend EncodeOptions with Eq::{not_equal, equal}
pub extend EncodeOptions with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub fn EncodeOptions::default() -> EncodeOptions {
  { limits: Limits::default(), }
}

///|
/// 解码成功后的值、消费字节数和字段轨迹。
pub(all) struct Decoded[T] {
  value : T
  consumed : Int
  trace : Array[TraceEntry]
} derive(Debug)

pub extend Decoded with @moonbitlang/core/debug.Debug::{to_repr}
