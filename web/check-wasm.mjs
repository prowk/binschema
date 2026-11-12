import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

// 直接加载 release 产物，验证与浏览器一致的导入选项和导出契约。
const wasmPath = process.argv[2] ?? "_build/wasm-gc/release/build/prowk/binschema/web/bridge/bridge.wasm";
const { instance } = await WebAssembly.instantiate(readFileSync(wasmPath), {}, {
  builtins: ["js-string"],
  importedStringConstants: "_",
});
const { sample_hex, inspect_hex } = instance.exports;
for (const format of ["png", "wav", "pcap", "bmff", "dns", "elf"]) {
  const hex = sample_hex(format);
  assert.match(hex, /^(?:[0-9a-f]{2})+$/i);
  const report = JSON.parse(inspect_hex(format, hex));
  assert.equal(report.roundtrip_equal, true, format);
  assert.equal(report.size, hex.length / 2, format);
  assert(report.trace.length > 0, format);
  if (format !== "dns") {
    assert.equal(JSON.parse(inspect_hex("auto", hex)).roundtrip_equal, true, format);
  }
}
for (const [format, hex] of [["zip", "00"], ["png", "0g"], ["auto", ""]]) {
  assert.equal(typeof JSON.parse(inspect_hex(format, hex)).error, "string");
}
console.log("Wasm-GC exports passed: six formats, auto detection, structured errors.");
