///|
let help_text =
  #|BinSchema — 安全的二进制协议检查器
  #|
  #|用法:
  #|  binschema inspect <file> [--format auto|png|wav|pcap|bmff|dns] [--json]
  #|  binschema verify  <file> [--format auto|png|wav|pcap|bmff|dns]
  #|  binschema sample  <png|wav|pcap|bmff|dns> <output>
  #|  binschema lint    <png|wav|pcap|bmff|dns> [--json]
  #|  binschema formats
  #|  binschema --version

///|
enum CliError {
  Usage(String)
  Data(String)
  Io(String)
}

///|
fn CliError::message(self : CliError) -> String {
  match self {
    Usage(message) | Data(message) | Io(message) => message
  }
}

///|
fn CliError::exit_code(self : CliError) -> Int {
  match self {
    Usage(_) => 2
    Data(_) => 3
    Io(_) => 4
  }
}

///|
fn parse_format(
  args : Array[String],
  start : Int,
) -> Result[@formats.Format, CliError] {
  let mut index = start
  let mut format = @formats.Auto
  while index < args.length() {
    if args[index] == "--format" {
      if index + 1 >= args.length() {
        return Err(Usage("--format 后缺少格式名称"))
      }
      format = match @formats.Format::parse(args[index + 1]) {
        Ok(value) => value
        Err(message) => return Err(Usage(message))
      }
      index += 2
    } else if args[index] == "--json" {
      index += 1
    } else {
      return Err(Usage("未知参数: " + args[index]))
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
fn enforce_input_limit(input : Bytes, limit : Int) -> Result[Bytes, CliError] {
  if input.length() > limit {
    Err(Data("输入文件超过安全上限（\{limit} 字节）"))
  } else {
    Ok(input)
  }
}

///|
fn read_input(path : String) -> Result[Bytes, CliError] {
  let input = @fs.read_file_to_bytes(path) catch {
    @fs.IOError(message) =>
      return Err(Io("无法读取文件 “" + path + "”：" + message))
  }
  enforce_input_limit(input, @bin.Limits::default().max_input_bytes)
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
fn verify_report(report : @formats.Inspection) -> Result[String, CliError] {
  if report.roundtrip_equal {
    Ok(
      "验证通过：\{report.format}，\{report.size} 字节，往返一致=true",
    )
  } else {
    Err(
      Data(
        "验证失败：\{report.format} 解码后重新编码的字节与原始输入不一致",
      ),
    )
  }
}

///|
fn inspect_input(
  input : Bytes,
  format : @formats.Format,
  json : Bool,
  verify_only : Bool,
) -> Result[String, CliError] {
  let report = match @formats.inspect(input, format~) {
    Ok(value) => value
    Err(error) => return Err(Data(error.render()))
  }
  if verify_only {
    verify_report(report)
  } else if json {
    Ok(report.to_json_string(pretty=true))
  } else {
    Ok(render_report(report))
  }
}

///|
fn inspect_command(
  args : Array[String],
  verify_only : Bool,
) -> Result[String, CliError] {
  if args.length() < 3 {
    return Err(Usage("缺少待检查文件路径"))
  }
  let format = match parse_format(args, 3) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let input = match read_input(args[2]) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  inspect_input(input, format, has_flag(args, 3, "--json"), verify_only)
}

///|
fn schema_for_format(
  format : @formats.Format,
) -> Result[@bin.SchemaNode, CliError] {
  match format {
    @formats.Png => Ok(@formats.png_codec().schema_node())
    @formats.Wav => Ok(@formats.wav_codec().schema_node())
    @formats.Pcap => Ok(@formats.pcap_codec().schema_node())
    @formats.Bmff => Ok(@formats.bmff_codec().schema_node())
    @formats.Dns => Ok(@formats.dns_codec().schema_node())
    @formats.Auto => Err(Usage("lint 不支持 auto 格式"))
  }
}

///|
fn lint_format(name : String, json : Bool) -> Result[String, CliError] {
  let format = match @formats.Format::parse(name) {
    Ok(value) => value
    Err(message) => return Err(Usage(message))
  }
  let schema = match schema_for_format(format) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let issues = @bin.lint_schema(schema)
  if json {
    return Ok(@json.to_json(issues).stringify(indent=2))
  }
  let buffer = StringBuilder()
  buffer.write_string("Schema lint: \{format.name()}\n")
  let mut error_count = 0
  let mut warning_count = 0
  for issue in issues {
    match issue.severity {
      @bin.LintError => error_count += 1
      @bin.LintWarning => warning_count += 1
    }
    buffer.write_string("  " + issue.render() + "\n")
  }
  buffer.write_string(
    "结果: \{error_count} errors, \{warning_count} warnings",
  )
  let output = buffer.to_string()
  if error_count > 0 {
    Err(Data(output))
  } else {
    Ok(output)
  }
}

///|
fn lint_command(args : Array[String]) -> Result[String, CliError] {
  if args.length() < 3 || args.length() > 4 {
    return Err(Usage("用法: binschema lint <png|wav|pcap|bmff|dns> [--json]"))
  }
  if args.length() == 4 && args[3] != "--json" {
    return Err(Usage("未知参数: " + args[3]))
  }
  lint_format(args[2], args.length() == 4)
}

///|
fn sample_bytes(name : String) -> Result[Bytes, CliError] {
  match @formats.Format::parse(name) {
    Ok(@formats.Png) => Ok(@formats.sample_png())
    Ok(@formats.Wav) => Ok(@formats.sample_wav())
    Ok(@formats.Pcap) => Ok(@formats.sample_pcap())
    Ok(@formats.Bmff) => Ok(@formats.sample_bmff())
    Ok(@formats.Dns) => Ok(@formats.sample_dns())
    Ok(@formats.Auto) => Err(Usage("sample 不支持 auto 格式"))
    Err(message) => Err(Usage(message))
  }
}

///|
fn sample_command(args : Array[String]) -> Result[String, CliError] {
  if args.length() != 4 {
    return Err(Usage("用法: binschema sample <png|wav|pcap|bmff|dns> <output>"))
  }
  let bytes = match sample_bytes(args[2]) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  try {
    @fs.write_bytes_to_file(args[3], bytes)
    Ok("已写入 \{args[3]}（\{bytes.length()} 字节）")
  } catch {
    @fs.IOError(message) =>
      Err(Io("无法写入文件 “" + args[3] + "”：" + message))
  }
}

///|
fn run(args : Array[String]) -> Result[String, CliError] {
  if args.length() < 2 {
    return Ok(help_text)
  }
  match args[1] {
    "inspect" => inspect_command(args, false)
    "verify" => inspect_command(args, true)
    "sample" => sample_command(args)
    "lint" => lint_command(args)
    "formats" => Ok("支持格式: PNG, WAVE, PCAP, ISO BMFF, DNS")
    "--version" | "-V" => Ok("binschema " + @bin.VERSION)
    "--help" | "-h" | "help" => Ok(help_text)
    command => Err(Usage("未知命令: " + command + "\n\n" + help_text))
  }
}

///|
fn main {
  match run(@env.args()) {
    Ok(output) => println(output)
    Err(error) => {
      println("错误: " + error.message())
      @sys.exit(error.exit_code())
    }
  }
}
