const MAX_FILE_BYTES = 16 * 1024 * 1024;
const LANGUAGE_KEY = "binschema-language";
const $ = (selector) => document.querySelector(selector);

const messages = {
  zh: {
    navLabel: "主导航", languageLabel: "语言", eyebrow: "LOCAL-FIRST · WASM-GC · OPEN SOURCE",
    heroTitle: "让二进制协议<br>清晰、可信、可解释。",
    heroDescription: "在浏览器本地检查 ELF、PNG、WAVE、PCAP、ISO BMFF / MP4 与 DNS。查看字段边界、协议结构与往返校验结果，文件始终留在你的设备上。",
    capabilitiesLabel: "核心能力", capabilityPrivate: "本地处理", capabilityFormats: "6 种格式", capabilityLimit: "16 MiB 上限",
    workspaceTitle: "二进制协议检查器", inputTitle: "选择输入", engineLoading: "正在加载引擎", engineReady: "引擎已就绪", engineBusy: "正在解析", engineFailed: "引擎不可用",
    formatLabel: "解析格式", formatAuto: "自动识别", samplesLabel: "内置样例", dropAria: "选择或拖入二进制文件，最大 16 MiB",
    dropTitle: "拖放文件或点击浏览", dropHint: "支持单个文件，最大 16 MiB", privacyNote: "文件仅在此浏览器中处理，不会上传。",
    analysisTitle: "分析结果", noFile: "等待输入", overviewLabel: "检查摘要", metricFormat: "格式", metricSize: "大小", metricFields: "字段", metricRoundtrip: "往返校验",
    emptyTitle: "正在准备检查器", emptyDescription: "引擎就绪后将自动载入一个 PNG 示例。", hexTitle: "字节视图", hexHint: "点击字节定位字段", hexAria: "十六进制内容",
    structureTitle: "协议结构", viewsLabel: "结构视图", schemaTab: "Schema", traceTab: "Trace", traceOffset: "偏移", traceField: "字段", traceValue: "值", traceListLabel: "解码字段",
    footerText: "MoonBit 构建 · Apache-2.0", emptyFile: "文件为空，无法识别二进制格式。", oversizedFile: "文件超过浏览器安全上限（16 MiB）。请使用 CLI 处理更大的文件。",
    wasmFailure: "Wasm 加载失败", parseFailure: "解析失败", parsedStatus: "已解析 {format}，共 {fields} 个字段", roundtripPass: "通过", roundtripDiff: "不一致",
  },
  en: {
    navLabel: "Primary navigation", languageLabel: "Language", eyebrow: "LOCAL-FIRST · WASM-GC · OPEN SOURCE",
    heroTitle: "Binary protocols,<br>clear and explainable.",
    heroDescription: "Inspect ELF, PNG, WAVE, PCAP, ISO BMFF / MP4, and DNS locally in your browser. See field boundaries, protocol structure, and round-trip validation without sending files anywhere.",
    capabilitiesLabel: "Core capabilities", capabilityPrivate: "Local processing", capabilityFormats: "6 formats", capabilityLimit: "16 MiB limit",
    workspaceTitle: "Binary protocol inspector", inputTitle: "Choose input", engineLoading: "Loading engine", engineReady: "Engine ready", engineBusy: "Inspecting", engineFailed: "Engine unavailable",
    formatLabel: "Parse as", formatAuto: "Auto detect", samplesLabel: "Built-in samples", dropAria: "Choose or drop a binary file, up to 16 MiB",
    dropTitle: "Drop a file or browse", dropHint: "One file, up to 16 MiB", privacyNote: "Files are processed only in this browser and are never uploaded.",
    analysisTitle: "Analysis", noFile: "Waiting for input", overviewLabel: "Inspection summary", metricFormat: "Format", metricSize: "Size", metricFields: "Fields", metricRoundtrip: "Round trip",
    emptyTitle: "Preparing the inspector", emptyDescription: "A PNG sample will load automatically when the engine is ready.", hexTitle: "Byte view", hexHint: "Select a byte to locate its field", hexAria: "Hexadecimal content",
    structureTitle: "Protocol structure", viewsLabel: "Structure views", schemaTab: "Schema", traceTab: "Trace", traceOffset: "Offset", traceField: "Field", traceValue: "Value", traceListLabel: "Decoded fields",
    footerText: "Built with MoonBit · Apache-2.0", emptyFile: "The file is empty and cannot be inspected.", oversizedFile: "The file exceeds the 16 MiB browser safety limit. Use the CLI for larger files.",
    wasmFailure: "Wasm failed to load", parseFailure: "Inspection failed", parsedStatus: "Parsed {format} with {fields} fields", roundtripPass: "Pass", roundtripDiff: "Diff",
  },
};

function preferredLanguage() {
  try {
    const saved = localStorage.getItem(LANGUAGE_KEY);
    if (saved === "zh" || saved === "en") return saved;
  } catch (_) {
    // 本地存储不可用时仍可正常使用。
  }
  return navigator.language.toLowerCase().startsWith("zh") ? "zh" : "en";
}

const state = {
  wasm: null,
  bytes: null,
  name: "",
  report: null,
  phase: "loading",
  language: preferredLanguage(),
  pinnedTrace: -1,
  errorKey: null,
  errorDetail: "",
};

function t(key) {
  return messages[state.language][key] || key;
}

function formatMessage(key, values) {
  return Object.entries(values).reduce((text, [name, value]) => text.replace(`{${name}}`, value), t(key));
}

function setEngineState(phase) {
  state.phase = phase;
  const key = { loading: "engineLoading", ready: "engineReady", busy: "engineBusy", failed: "engineFailed" }[phase];
  const element = $("#engine-state");
  element.className = `engine-state ${phase}`;
  element.querySelector("span").textContent = t(key);
}

function setControlsEnabled(enabled) {
  $("#format").disabled = !enabled;
  $("#file").disabled = !enabled;
  document.querySelectorAll(".sample").forEach((button) => { button.disabled = !enabled; });
  const zone = $("#dropzone");
  zone.classList.toggle("disabled", !enabled);
  zone.setAttribute("aria-disabled", String(!enabled));
  zone.tabIndex = enabled ? 0 : -1;
}

function applyLanguage(language, persist = false) {
  state.language = language;
  document.documentElement.lang = language === "zh" ? "zh-CN" : "en";
  document.querySelectorAll("[data-language]").forEach((button) => button.setAttribute("aria-pressed", String(button.dataset.language === language)));
  document.querySelectorAll("[data-i18n]").forEach((element) => {
    const key = element.dataset.i18n;
    if (key === "heroTitle") element.innerHTML = t(key);
    else element.textContent = t(key);
  });
  document.querySelectorAll("[data-i18n-aria]").forEach((element) => element.setAttribute("aria-label", t(element.dataset.i18nAria)));
  $("#file-name").textContent = state.name || t("noFile");
  if (state.report) {
    $("#result-roundtrip").textContent = state.report.roundtrip_equal ? t("roundtripPass") : t("roundtripDiff");
    $("#status").textContent = formatMessage("parsedStatus", { format: state.report.format, fields: state.report.trace.length });
  }
  if (state.errorKey) showError(state.errorKey, state.errorDetail);
  setEngineState(state.phase);
  if (persist) {
    try { localStorage.setItem(LANGUAGE_KEY, language); } catch (_) { /* 无需持久化也可继续使用。 */ }
  }
}

async function loadWasm() {
  const response = await fetch("binschema.wasm");
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  const bytes = await response.arrayBuffer();
  const { instance } = await WebAssembly.instantiate(bytes, {}, { builtins: ["js-string"], importedStringConstants: "_" });
  state.wasm = instance.exports;
}

function toHex(bytes) {
  return Array.from(bytes, (value) => value.toString(16).padStart(2, "0")).join("");
}

function fromHex(hex) {
  const compact = hex.replace(/\s+/g, "");
  const result = new Uint8Array(compact.length / 2);
  for (let index = 0; index < result.length; index += 1) result[index] = Number.parseInt(compact.slice(index * 2, index * 2 + 2), 16);
  return result;
}

function escapeText(value) {
  const element = document.createElement("span");
  element.textContent = String(value);
  return element.innerHTML;
}

function showError(key, detail = "") {
  state.errorKey = key;
  state.errorDetail = detail;
  const error = $("#error");
  error.textContent = detail ? `${t(key)}：${detail}` : t(key);
  error.hidden = false;
}

function clearError() {
  state.errorKey = null;
  state.errorDetail = "";
  $("#error").hidden = true;
}

function renderSchemaNode(node, depth = 0) {
  const label = node.name ? `${escapeText(node.name)} <span class="schema-kind">${escapeText(node.kind)}</span>` : `<span class="schema-kind">${escapeText(node.kind)}</span>`;
  const constraints = (node.constraints || []).map((constraint) => `<span>${escapeText(constraint)}</span>`).join("");
  const children = (node.children || []).map((child) => renderSchemaNode(child, depth + 1)).join("");
  return `<div class="schema-node" style="--depth:${depth}"><div class="schema-row">${label}<span class="schema-constraints">${constraints}</span></div>${children}</div>`;
}

function setView(view) {
  document.querySelectorAll("[data-view]").forEach((button) => button.setAttribute("aria-selected", String(button.dataset.view === view)));
  $("#schema-view").hidden = view !== "schema";
  $("#trace-view").hidden = view !== "trace";
}

function paintRange(start, end, pinned = false) {
  document.querySelectorAll("#hex span").forEach((node, index) => {
    const selected = index >= start && index < end;
    node.classList.toggle("active", selected);
    node.classList.toggle("pinned", selected && pinned);
  });
}

function activateTrace(index, scroll = false) {
  state.pinnedTrace = index;
  document.querySelectorAll(".trace-row").forEach((row) => {
    const active = Number(row.dataset.traceIndex) === index;
    row.classList.toggle("active", active);
    row.setAttribute("aria-selected", String(active));
    if (active && scroll) row.scrollIntoView({ block: "nearest", behavior: "smooth" });
  });
  if (index < 0 || !state.report) paintRange(-1, -1);
  else {
    const entry = state.report.trace[index];
    paintRange(entry.start, entry.end, true);
  }
}

function bindTraceInteractions() {
  document.querySelectorAll(".trace-row").forEach((row) => {
    const index = Number(row.dataset.traceIndex);
    row.addEventListener("mouseenter", () => {
      const entry = state.report.trace[index];
      paintRange(entry.start, entry.end, state.pinnedTrace === index);
    });
    row.addEventListener("mouseleave", () => activateTrace(state.pinnedTrace));
    row.addEventListener("click", () => activateTrace(state.pinnedTrace === index ? -1 : index));
    row.addEventListener("keydown", (event) => {
      if (event.key === "Enter" || event.key === " ") { event.preventDefault(); row.click(); }
    });
  });
}

function bindHexInteractions() {
  document.querySelectorAll("#hex span").forEach((node) => node.addEventListener("click", () => {
    const byteIndex = Number(node.dataset.index);
    const candidates = state.report.trace.map((entry, index) => ({ entry, index })).filter(({ entry }) => byteIndex >= entry.start && byteIndex < entry.end);
    candidates.sort((left, right) => (left.entry.end - left.entry.start) - (right.entry.end - right.entry.start));
    if (candidates.length > 0) {
      setView("trace");
      activateTrace(candidates[0].index, true);
      $("#trace-tab").focus();
    }
  }));
}

function render(report) {
  state.report = report;
  state.pinnedTrace = -1;
  $("#result-format").textContent = report.format;
  $("#result-size").textContent = `${report.size} B`;
  $("#result-fields").textContent = report.trace.length;
  const roundtrip = $("#result-roundtrip");
  roundtrip.textContent = report.roundtrip_equal ? t("roundtripPass") : t("roundtripDiff");
  roundtrip.className = report.roundtrip_equal ? "success" : "danger";
  $("#file-name").textContent = state.name;
  $("#summary").innerHTML = report.summary.map(({ key, value }) => `<span>${escapeText(key)} · <b>${escapeText(value)}</b></span>`).join("");
  $("#schema").innerHTML = renderSchemaNode(report.schema);
  $("#hex").innerHTML = Array.from(state.bytes, (byte, index) => `<span data-index="${index}" title="0x${index.toString(16).padStart(4, "0")}">${byte.toString(16).padStart(2, "0")}</span>`).join(" ");
  $("#trace").innerHTML = report.trace.map((entry, index) => `<button class="trace-row" type="button" role="option" aria-selected="false" data-trace-index="${index}"><span class="offset">${entry.start.toString(16).padStart(4, "0")}</span><span class="path" title="${escapeText(entry.path)}">${escapeText(entry.path || "root")}</span><span class="value" title="${escapeText(entry.value)}">${escapeText(entry.value)}</span></button>`).join("");
  bindTraceInteractions();
  bindHexInteractions();
  setView("schema");
  clearError();
  $("#empty-state").hidden = true;
  $("#result").hidden = false;
  $("#status").textContent = formatMessage("parsedStatus", { format: report.format, fields: report.trace.length });
}

async function inspectBytes(bytes, name = "sample.bin") {
  if (bytes.length === 0) { $("#result").hidden = true; $("#empty-state").hidden = false; showError("emptyFile"); return; }
  if (bytes.length > MAX_FILE_BYTES) { $("#result").hidden = true; $("#empty-state").hidden = false; showError("oversizedFile"); return; }
  state.bytes = bytes;
  state.name = name;
  setEngineState("busy");
  setControlsEnabled(false);
  await new Promise((resolve) => requestAnimationFrame(resolve));
  try {
    const result = JSON.parse(state.wasm.inspect_hex($("#format").value, toHex(bytes)));
    if (result.error) { $("#result").hidden = true; $("#empty-state").hidden = false; showError("parseFailure", result.error); return; }
    render(result);
  } catch (error) {
    $("#result").hidden = true;
    $("#empty-state").hidden = false;
    showError("parseFailure", error.message);
  } finally {
    setEngineState("ready");
    setControlsEnabled(true);
  }
}

async function openFile(file) {
  if (file.size > MAX_FILE_BYTES) { showError("oversizedFile"); return; }
  document.querySelectorAll(".sample").forEach((button) => button.classList.remove("active"));
  await inspectBytes(new Uint8Array(await file.arrayBuffer()), file.name);
}

function bindControls() {
  document.querySelectorAll("[data-language]").forEach((button) => button.addEventListener("click", () => applyLanguage(button.dataset.language, true)));
  document.querySelectorAll("[data-view]").forEach((button) => button.addEventListener("click", () => setView(button.dataset.view)));
  $("#file").addEventListener("change", (event) => event.target.files[0] && openFile(event.target.files[0]));
  const zone = $("#dropzone");
  for (const eventName of ["dragenter", "dragover"]) zone.addEventListener(eventName, (event) => { event.preventDefault(); if (!zone.classList.contains("disabled")) zone.classList.add("drag"); });
  for (const eventName of ["dragleave", "drop"]) zone.addEventListener(eventName, (event) => { event.preventDefault(); zone.classList.remove("drag"); });
  zone.addEventListener("drop", (event) => event.dataTransfer.files[0] && openFile(event.dataTransfer.files[0]));
  zone.addEventListener("keydown", (event) => {
    if ((event.key === "Enter" || event.key === " ") && !zone.classList.contains("disabled")) { event.preventDefault(); $("#file").click(); }
  });
  document.querySelectorAll(".sample").forEach((button) => button.addEventListener("click", async () => {
    const format = button.dataset.format;
    $("#format").value = format;
    document.querySelectorAll(".sample").forEach((candidate) => candidate.classList.toggle("active", candidate === button));
    await inspectBytes(fromHex(state.wasm.sample_hex(format)), `sample.${format === "bmff" ? "mp4" : format}`);
  }));
  $("#format").addEventListener("change", () => state.bytes && inspectBytes(state.bytes, state.name));
}

async function init() {
  applyLanguage(state.language);
  bindControls();
  setControlsEnabled(false);
  try {
    await loadWasm();
    setEngineState("ready");
    setControlsEnabled(true);
    const pngButton = document.querySelector('.sample[data-format="png"]');
    pngButton.classList.add("active");
    $("#format").value = "png";
    await inspectBytes(fromHex(state.wasm.sample_hex("png")), "sample.png");
  } catch (error) {
    setEngineState("failed");
    showError("wasmFailure", error.message);
  }
}

init();
