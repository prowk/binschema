///|
let help_text =
  #|BinSchema — 安全的二进制协议检查器
  #|
  #|用法:
  #|  binschema inspect <file> [--format auto|png|wav|pcap] [--json]
  #|  binschema verify  <file> [--format auto|png|wav|pcap]
  #|  binschema sample  <png|wav|pcap> <output>
  #|  binschema formats
  #|  binschema --version

///|
fn parse_format(
  args : Array[String],
  start : Int,
) -> Result[@formats.Format, String] {
  let mut index = start
  let mut format = @formats.Auto
  while index < args.length() {
    if args[index] == "--format" {
      if index + 1 >= args.length() {
        return Err("--format 后缺少格式名称")
      }
      format = match @formats.Format::parse(args[index + 1]) {
        Ok(value) => value
        Err(message) => return Err(message)
      }
      index += 2
    } else if args[index] == "--json" {
      index += 1
    } else {
      return Err("未知参数: " + args[index])
    }
  }
  Ok(format)
}

///|
fn has_flag(args : Array[String], start : Int, flag : String) -> Bool {
  for index in start..<args.length() {
    if args[index] == flag {
      return true
    }
  }
  false
}

///|
fn read_input(path : String) -> Result[Bytes, String] {
  Ok(@fs.read_file_to_bytes(path)) catch {
    @fs.IOError(message) =>
      Err("无法读取文件 “" + path + "”：" + message)
  }
}

///|
fn render_report(report : @formats.Inspection) -> String {
  let buffer = StringBuilder()
  buffer.write_string("格式: \{report.format}\n")
  buffer.write_string("大小: \{report.size} 字节\n")
  buffer.write_string("往返一致: \{report.roundtrip_equal}\n")
  buffer.write_string("摘要:\n")
  for entry in report.summary {
    buffer.write_string("  \{entry.key}: \{entry.value}\n")
  }
  buffer.write_string("字段轨迹:\n")
  for entry in report.trace {
    buffer.write_string(
      "  [\{entry.start}, \{entry.end}) \{entry.path} <\{entry.kind}> = \{entry.value}\n",
    )
  }
  buffer.to_string()
}

///|
fn inspect_command(
  args : Array[String],
  verify_only : Bool,
) -> Result[String, String] {
  if args.length() < 3 {
    return Err("缺少待检查文件路径")
  }
  let format = match parse_format(args, 3) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let input = match read_input(args[2]) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let report = match @formats.inspect(input, format~) {
    Ok(value) => value
    Err(error) => return Err(error.render())
  }
  if verify_only {
    Ok(
      "验证通过：\{report.format}，\{report.size} 字节，往返一致=\{report.roundtrip_equal}",
    )
  } else if has_flag(args, 3, "--json") {
    Ok(report.to_json_string(pretty=true))
  } else {
    Ok(render_report(report))
  }
}

///|
fn sample_bytes(name : String) -> Result[Bytes, String] {
  match @formats.Format::parse(name) {
    Ok(@formats.Png) => Ok(@formats.sample_png())
    Ok(@formats.Wav) => Ok(@formats.sample_wav())
    Ok(@formats.Pcap) => Ok(@formats.sample_pcap())
    Ok(@formats.Auto) => Err("sample 不支持 auto 格式")
    Err(message) => Err(message)
  }
}

///|
fn sample_command(args : Array[String]) -> Result[String, String] {
  if args.length() != 4 {
    return Err("用法: binschema sample <png|wav|pcap> <output>")
  }
  let bytes = match sample_bytes(args[2]) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  try {
    @fs.write_bytes_to_file(args[3], bytes)
    Ok("已写入 \{args[3]}（\{bytes.length()} 字节）")
  } catch {
    @fs.IOError(message) =>
      Err("无法写入文件 “" + args[3] + "”：" + message)
  }
}

///|
fn run(args : Array[String]) -> Result[String, String] {
  if args.length() < 2 {
    return Ok(help_text)
  }
  match args[1] {
    "inspect" => inspect_command(args, false)
    "verify" => inspect_command(args, true)
    "sample" => sample_command(args)
    "formats" => Ok("支持格式: PNG, WAVE, PCAP")
    "--version" | "-V" => Ok("binschema " + @bin.VERSION)
    "--help" | "-h" | "help" => Ok(help_text)
    command => Err("未知命令: " + command + "\n\n" + help_text)
  }
}

///|
fn main {
  match run(@env.args()) {
    Ok(output) => println(output)
    Err(message) => {
      println("错误: " + message)
      @sys.exit(2)
    }
  }
}
