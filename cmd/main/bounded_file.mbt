///|
#external
priv type InputFileHandle

///|
#cfg(platform="windows")
priv struct InputPath(String)

///|
#cfg(not(platform="windows"))
priv struct InputPath(Bytes)

///|
#cfg(platform="windows")
fn InputPath::from_string(path : String) -> InputPath {
  InputPath(path)
}

///|
#cfg(not(platform="windows"))
fn InputPath::from_string(path : String) -> InputPath {
  InputPath(@unicode.to_utf8_bytes(path) + Bytes::make(1, 0))
}

///|
#borrow(path)
extern "C" fn input_file_open(path : InputPath) -> InputFileHandle = "binschema_input_file_open"

///|
extern "C" fn input_file_is_null(file : InputFileHandle) -> Int = "binschema_input_file_is_null"

///|
#borrow(file, buffer)
extern "C" fn input_file_read(
  file : InputFileHandle,
  buffer : Bytes,
  count : Int,
) -> Int = "binschema_input_file_read"

///|
extern "C" fn input_file_close(file : InputFileHandle) -> Int = "binschema_input_file_close"

///|
extern "C" fn input_file_error_message() -> Bytes = "binschema_input_file_error_message"

///|
fn input_file_error() -> String {
  @unicode.to_utf8_string(input_file_error_message())
}

///|
/// 分块读取文件，并且在分配超过上限前停止。
fn read_input_bounded(path : String, limit : Int) -> Result[Bytes, CliError] {
  if limit < 0 {
    return Err(Data("输入文件上限不能为负数"))
  }
  let file = input_file_open(InputPath::from_string(path))
  if input_file_is_null(file) != 0 {
    return Err(
      Io("无法读取文件 “" + path + "”：" + input_file_error()),
    )
  }
  let chunk_size = 64 * 1024
  let chunk = Bytes::make(chunk_size, 0)
  let output : Array[Byte] = []
  while output.length() <= limit {
    let remaining = limit - output.length() + 1
    let request = if remaining < chunk_size { remaining } else { chunk_size }
    let count = input_file_read(file, chunk, request)
    if count < 0 {
      let message = input_file_error()
      ignore(input_file_close(file))
      return Err(Io("无法读取文件 “" + path + "”：" + message))
    }
    if count == 0 {
      if input_file_close(file) != 0 {
        return Err(
          Io("无法关闭文件 “" + path + "”：" + input_file_error()),
        )
      }
      return Ok(Bytes::from_array(output))
    }
    for index in 0..<count {
      output.push(chunk[index])
    }
  }
  ignore(input_file_close(file))
  Err(Data("输入文件超过安全上限（\{limit} 字节）"))
}
