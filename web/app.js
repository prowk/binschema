const state = { wasm: null, bytes: null, name: "sample.bin", report: null };
const MAX_FILE_BYTES = 16 * 1024 * 1024;
const $ = (selector) => document.querySelector(selector);

async function loadWasm() {
  const response = await fetch("binschema.wasm");
  const bytes = await response.arrayBuffer();
  const { instance } = await WebAssembly.instantiate(bytes, {}, {
    builtins: ["js-string"],
    importedStringConstants: "_",
  });
  state.wasm = instance.exports;
}

function toHex(bytes) {
  return Array.from(bytes, (value) => value.toString(16).padStart(2, "0")).join("");
}

function fromHex(hex) {
  const compact = hex.replace(/\s+/g, "");
  const result = new Uint8Array(compact.length / 2);
  for (let index = 0; index < result.length; index += 1) {
    result[index] = Number.parseInt(compact.slice(index * 2, index * 2 + 2), 16);
  }
  return result;
}

function escapeText(value) {
  const element = document.createElement("span");
  element.textContent = value;
  return element.innerHTML;
}

function highlight(start, end) {
  document.querySelectorAll(".hex span").forEach((node, index) => {
    node.classList.toggle("active", index >= start && index < end);
  });
}

function render(report) {
  state.report = report;
  $("#result-format").textContent = report.format;
  $("#result-size").textContent = `${report.size} B`;
  $("#result-roundtrip").textContent = report.roundtrip_equal ? "PASS" : "DIFF";
  $("#result-roundtrip").style.color = report.roundtrip_equal ? "var(--acid)" : "var(--orange)";
  $("#result-fields").textContent = report.trace.length;
  $("#file-name").textContent = state.name;
  $("#summary").innerHTML = report.summary.map(({ key, value }) =>
    `<span>${escapeText(key)} · <b>${escapeText(value)}</b></span>`).join("");
  $("#hex").innerHTML = Array.from(state.bytes, (byte, index) =>
    `<span data-index="${index}">${byte.toString(16).padStart(2, "0")}</span>`).join(" ");
  $("#trace").innerHTML = report.trace.map((entry) => `
    <div class="trace-row" tabindex="0" data-start="${entry.start}" data-end="${entry.end}">
      <span class="offset">${entry.start.toString(16).padStart(4, "0")}</span>
      <span class="path" title="${escapeText(entry.path)}">${escapeText(entry.path || "root")}</span>
      <span class="value" title="${escapeText(entry.value)}">${escapeText(entry.value)}</span>
    </div>`).join("");
  document.querySelectorAll(".trace-row").forEach((row) => {
    row.addEventListener("mouseenter", () => highlight(Number(row.dataset.start), Number(row.dataset.end)));
    row.addEventListener("mouseleave", () => highlight(-1, -1));
    row.addEventListener("focus", () => highlight(Number(row.dataset.start), Number(row.dataset.end)));
    row.addEventListener("blur", () => highlight(-1, -1));
  });
  $("#error").hidden = true;
  $("#result").hidden = false;
  $("#status").textContent = `已解析 ${report.format}，${report.trace.length} 个字段`;
}

function inspectBytes(bytes, name = "sample.bin") {
  if (bytes.length === 0) {
    $("#result").hidden = true;
    $("#error").textContent = "文件为空，无法识别二进制格式。";
    $("#error").hidden = false;
    return;
  }
  if (bytes.length > MAX_FILE_BYTES) {
    $("#result").hidden = true;
    $("#error").textContent = "文件超过浏览器安全上限（16 MiB）。请使用 CLI 处理更大的文件。";
    $("#error").hidden = false;
    return;
  }
  state.bytes = bytes;
  state.name = name;
  const raw = state.wasm.inspect_hex($("#format").value, toHex(bytes));
  const result = JSON.parse(raw);
  if (result.error) {
    $("#result").hidden = true;
    $("#error").textContent = result.error;
    $("#error").hidden = false;
    return;
  }
  render(result);
}

async function openFile(file) {
  if (file.size > MAX_FILE_BYTES) {
    $("#result").hidden = true;
    $("#error").textContent = "文件超过浏览器安全上限（16 MiB）。请使用 CLI 处理更大的文件。";
    $("#error").hidden = false;
    return;
  }
  inspectBytes(new Uint8Array(await file.arrayBuffer()), file.name);
}

async function init() {
  try {
    await loadWasm();
  } catch (error) {
    $("#error").textContent = `Wasm 加载失败：${error.message}`;
    $("#error").hidden = false;
    return;
  }
  $("#file").addEventListener("change", (event) => event.target.files[0] && openFile(event.target.files[0]));
  const zone = $("#dropzone");
  for (const eventName of ["dragenter", "dragover"]) {
    zone.addEventListener(eventName, (event) => { event.preventDefault(); zone.classList.add("drag"); });
  }
  for (const eventName of ["dragleave", "drop"]) {
    zone.addEventListener(eventName, (event) => { event.preventDefault(); zone.classList.remove("drag"); });
  }
  zone.addEventListener("drop", (event) => event.dataTransfer.files[0] && openFile(event.dataTransfer.files[0]));
  zone.addEventListener("keydown", (event) => {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      $("#file").click();
    }
  });
  document.querySelectorAll(".sample").forEach((button) => button.addEventListener("click", () => {
    const format = button.dataset.format;
    $("#format").value = format;
    inspectBytes(fromHex(state.wasm.sample_hex(format)), `sample.${format === "wav" ? "wav" : format}`);
  }));
  $("#format").addEventListener("change", () => state.bytes && inspectBytes(state.bytes, state.name));
  inspectBytes(fromHex(state.wasm.sample_hex("png")), "sample.png");
}

init();
