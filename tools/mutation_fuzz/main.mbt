///|
fn parse_number(raw : String, name : String) -> Result[Int, String] {
  if raw.length() == 0 {
    return Err(name + " 不能为空")
  }
  let mut value = 0
  for index in 0..<raw.length() {
    let digit = raw.code_unit_at(index).to_int() - 48
    if digit < 0 || digit > 9 {
      return Err(name + " 必须是非负十进制整数")
    }
    if value > 1_000_000 {
      return Err(name + " 超出运行上限")
    }
    value = value * 10 + digit
  }
  Ok(value)
}

///|
fn parse_options(args : Array[String]) -> Result[(Int, Int), String] {
  let mut seed = 1
  let mut iterations = 256
  let mut index = 1
  while index < args.length() {
    if index + 1 >= args.length() {
      return Err("参数后缺少数值: " + args[index])
    }
    let value = match parse_number(args[index + 1], args[index]) {
      Ok(value) => value
      Err(message) => return Err(message)
    }
    match args[index] {
      "--seed" => seed = value
      "--iterations" => iterations = value
      option => return Err("未知参数: " + option)
    }
    index += 2
  }
  if iterations <= 0 || iterations > 100_000 {
    return Err("--iterations 必须在 1 到 100000 之间")
  }
  Ok((seed, iterations))
}

///|
fn next_state(value : UInt) -> UInt {
  let mut state = if value == 0U { 0x9e3779b9U } else { value }
  state = state ^ (state << 13)
  state = state ^ (state >> 17)
  state ^ (state << 5)
}

///|
fn sample_for(index : Int) -> (Bytes, @formats.Format) {
  match index % 6 {
    0 => (@formats.sample_png(), @formats.Png)
    1 => (@formats.sample_wav(), @formats.Wav)
    2 => (@formats.sample_pcap(), @formats.Pcap)
    3 => (@formats.sample_bmff(), @formats.Bmff)
    4 => (@formats.sample_dns(), @formats.Dns)
    _ => (@formats.sample_elf(), @formats.Elf)
  }
}

///|
fn mutate(input : Bytes, state : UInt) -> Bytes {
  let position = (state % input.length().reinterpret_as_uint()).reinterpret_as_int()
  if (state >> 8) % 4U == 3U {
    let truncated : Array[Byte] = []
    for index in 0..<position {
      truncated.push(input[index])
    }
    return Bytes::from_array(truncated)
  }
  let output = input.to_array()
  let original = output[position].to_uint()
  output[position] = match (state >> 8) % 4U {
    0U =>
      (original ^ (1U << ((state >> 16) % 8U).reinterpret_as_int())).to_byte()
    1U => 0U.to_byte()
    _ => 0xffU.to_byte()
  }
  Bytes::from_array(output)
}

///|
fn validate_outcome(
  input : Bytes,
  format : @formats.Format,
) -> Result[Unit, String] {
  match @formats.inspect(input, format~) {
    Ok(report) =>
      if report.roundtrip_equal {
        Ok(())
      } else {
        Err("成功解析的变异样本未保持字节级往返")
      }
    Err(error) =>
      if error.offset < 0 || error.offset > input.length() {
        Err("结构化错误偏移超出输入范围: " + error.render())
      } else if error.render().length() == 0 {
        Err("结构化错误内容为空")
      } else {
        Ok(())
      }
  }
}

///|
fn run(seed : Int, iterations : Int) -> Result[Unit, String] {
  let mut state = seed.reinterpret_as_uint()
  for iteration in 0..<iterations {
    let (sample, format) = sample_for(iteration)
    state = next_state(state)
    let input = mutate(sample, state)
    match validate_outcome(input, format) {
      Ok(_) => ()
      Err(message) =>
        return Err(
          "seed=" +
          seed.to_string() +
          " iteration=" +
          iteration.to_string() +
          ": " +
          message,
        )
    }
  }
  Ok(())
}

///|
fn main {
  match parse_options(@env.args()) {
    Err(message) => {
      println("错误: " + message)
      @sys.exit(2)
    }
    Ok((seed, iterations)) =>
      match run(seed, iterations) {
        Ok(_) =>
          println(
            "mutation fuzz completed: seed=" +
            seed.to_string() +
            ", iterations=" +
            iterations.to_string() +
            ", formats=6",
          )
        Err(message) => {
          println("错误: " + message)
          @sys.exit(1)
        }
      }
  }
}
