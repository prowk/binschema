// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "prowk/binschema"

version = "0.2.0"

readme = "README.mbt.md"

repository = "https://github.com/prowk/binschema"

license = "Apache-2.0"

keywords = [ "binary", "codec", "parser", "wasm", "security" ]

preferred_target = "wasm"

supported_targets = "+wasm+wasm-gc+js+native"

description = "Safe, composable binary protocol codecs for MoonBit with CLI inspection and a Wasm visualizer"

import {
  "moonbitlang/x@0.5.5",
}
