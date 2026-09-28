import { calculateHexWindow, TraceIntervalIndex } from "./inspector-core.mjs?v=0.3.3";

const MAX_FILE_BYTES = 16 * 1024 * 1024;
const HEX_ROW_HEIGHT = 26;
const HEX_OVERSCAN_ROWS = 10;
const HEX_CELL_WIDTH = 29;
const HEX_HORIZONTAL_PADDING = 44;
const LANGUAGE_KEY = "binschema-language";
const $ = (selector) => document.querySelector(selector);

const messages = {
  zh: {
    navLabel: "主导航", languageLabel: "语言", eyebrow: "LOCAL-FIRST · WASM-GC · OPEN SOURCE",
    heroSubtitle: "看清每一个字节", startInspecting: "开始检查", viewDocs: "查看文档",
    heroDescription: "在浏览器中解析二进制文件，查看字段边界、协议结构与往返校验。",
    capabilitiesLabel: "核心能力", capabilityPrivate: "本地处理", capabilityFormats: "6 种格式", capabilityLimit: "16 MiB 上限",
    workspaceTitle: "二进制协议检查器", inputTitle: "选择输入", engineLoading: "正在加载引擎", engineReady: "引擎已就绪", engineBusy: "正在解析", engineFailed: "引擎不可用",
    formatLabel: "解析格式", formatAuto: "自动识别", samplesLabel: "内置样例", dropAria: "选择或拖入二进制文件，最大 16 MiB",
    dropTitle: "拖放文件或点击浏览", dropHint: "支持单个文件，最大 16 MiB", fileReady: "文件已载入", removeFile: "取消选择", fileRemoved: "已取消文件选择", privacyNote: "文件仅在此浏览器中处理，不会上传。",
    analysisTitle: "分析结果", noFile: "等待输入", overviewLabel: "检查摘要", metricFormat: "格式", metricSize: "大小", metricFields: "字段", metricRoundtrip: "往返校验",
    emptyTitle: "正在准备检查器", emptyDescription: "引擎就绪后将自动载入一个 PNG 示例。", idleTitle: "等待文件", idleDescription: "选择或拖入另一个二进制文件继续检查。", hexTitle: "字节视图", hexHint: "点击字节或右侧 Trace 字段双向定位", hexAria: "十六进制内容",
    structureTitle: "协议结构", viewsLabel: "结构视图", schemaTab: "Schema", traceTab: "Trace", traceOffset: "偏移", traceField: "字段", traceValue: "值", traceListLabel: "解码字段",
    featureTitle: "一次定义，贯穿编解码与验证", featureDescription: "上面的检查器不只是十六进制查看器。它直接使用 BinSchema 的 Codec，将协议定义、边界校验、结构描述和字节级追踪连接在一起。",
    featureCodecTitle: "双向 Codec", featureCodecDescription: "同一份组合式定义同时完成安全解码与编码，并用于字节级往返校验。",
    featureSafetyTitle: "边界优先", featureSafetyDescription: "输入、输出、集合、嵌套与追踪均有资源上限，错误保留偏移和字段路径。",
    featureExplainTitle: "结构可解释", featureExplainDescription: "Schema 描述协议结构，Trace 将每个字段映射回准确的字节范围。",
    featureStreamTitle: "面向真实输入", featureStreamDescription: "支持增量帧解析、零拷贝视图和 Schema lint，适合流式及大输入场景。",
    codeTitle: "像搭积木一样描述协议", codeDescription: "基础类型、字段命名和组合子共同生成可执行协议；检查器中的 Schema、Trace 与往返结果都来自同一棵 Codec 树。",
    apiTagsLabel: "扩展能力", apiStructuredErrors: "结构化错误", apiIncremental: "增量解码", apiZeroCopy: "零拷贝视图", codeAria: "MoonBit Codec 示例",
    footerText: "MoonBit 构建 · Apache-2.0", emptyFile: "文件为空，无法识别二进制格式。", oversizedFile: "文件超过浏览器安全上限（16 MiB）。请使用 CLI 处理更大的文件。",
    wasmFailure: "Wasm 加载失败", parseFailure: "解析失败", parsedStatus: "已解析 {format}，共 {fields} 个字段", roundtripPass: "通过", roundtripDiff: "不一致",
  },
  en: {
    navLabel: "Primary navigation", languageLabel: "Language", eyebrow: "LOCAL-FIRST · WASM-GC · OPEN SOURCE",
    heroSubtitle: "Clarity in every byte", startInspecting: "Start inspecting", viewDocs: "Read the docs",
    heroDescription: "Inspect binary files in your browser. Explore field boundaries, protocol structure, and round-trip validation.",
    capabilitiesLabel: "Core capabilities", capabilityPrivate: "Local processing", capabilityFormats: "6 formats", capabilityLimit: "16 MiB limit",
    workspaceTitle: "Binary protocol inspector", inputTitle: "Choose input", engineLoading: "Loading engine", engineReady: "Engine ready", engineBusy: "Inspecting", engineFailed: "Engine unavailable",
    formatLabel: "Parse as", formatAuto: "Auto detect", samplesLabel: "Built-in samples", dropAria: "Choose or drop a binary file, up to 16 MiB",
    dropTitle: "Drop a file or browse", dropHint: "One file, up to 16 MiB", fileReady: "File ready", removeFile: "Remove file", fileRemoved: "File selection removed", privacyNote: "Files are processed only in this browser and are never uploaded.",
    analysisTitle: "Analysis", noFile: "Waiting for input", overviewLabel: "Inspection summary", metricFormat: "Format", metricSize: "Size", metricFields: "Fields", metricRoundtrip: "Round trip",
    emptyTitle: "Preparing the inspector", emptyDescription: "A PNG sample will load automatically when the engine is ready.", idleTitle: "Waiting for a file", idleDescription: "Choose or drop another binary file to continue.", hexTitle: "Byte view", hexHint: "Select a byte or Trace field to locate either side", hexAria: "Hexadecimal content",
    structureTitle: "Protocol structure", viewsLabel: "Structure views", schemaTab: "Schema", traceTab: "Trace", traceOffset: "Offset", traceField: "Field", traceValue: "Value", traceListLabel: "Decoded fields",
    featureTitle: "Define once. Decode, explain, and verify.", featureDescription: "The inspector above is more than a hex viewer. It runs BinSchema codecs directly, connecting protocol definitions, boundary checks, structural metadata, and byte-level traces.",
    featureCodecTitle: "Bidirectional codecs", featureCodecDescription: "One compositional definition safely decodes and encodes data, enabling byte-exact round-trip checks.",
    featureSafetyTitle: "Boundaries first", featureSafetyDescription: "Inputs, outputs, collections, nesting, and traces are bounded; errors retain offsets and field paths.",
    featureExplainTitle: "Explainable structure", featureExplainDescription: "Schema describes the protocol while Trace maps every named field back to its exact byte range.",
    featureStreamTitle: "Built for real input", featureStreamDescription: "Incremental framing, zero-copy views, and Schema lint support streaming and large-input workloads.",
    codeTitle: "Compose protocols from small parts", codeDescription: "Primitives, named fields, and combinators form an executable protocol. The inspector's Schema, Trace, and round-trip result all come from that same codec tree.",
    apiTagsLabel: "Extended capabilities", apiStructuredErrors: "Structured errors", apiIncremental: "Incremental decode", apiZeroCopy: "Zero-copy views", codeAria: "MoonBit codec example",
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
  uploadedFile: null,
  report: null,
  phase: "loading",
  language: preferredLanguage(),
  pinnedTrace: -1,
  paintedRange: null,
  traceIndex: null,
  activeTraceRow: null,
  hexBytesPerRow: 16,
  hexRenderKey: "",
  hexFrame: 0,
  hexResizeObserver: null,
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
  $("#drop-prompt").disabled = !enabled;
  document.querySelectorAll(".sample").forEach((button) => { button.disabled = !enabled; });
  const zone = $("#dropzone");
  zone.classList.toggle("disabled", !enabled);
  zone.setAttribute("aria-disabled", String(!enabled));
  $("#clear-file").disabled = !enabled;
}

function formatFileSize(size) {
  if (size < 1024) return `${size} B`;
  if (size < 1024 * 1024) return `${(size / 1024).toFixed(1)} KiB`;
  return `${(size / (1024 * 1024)).toFixed(1)} MiB`;
}

function updateUploadState() {
  const file = state.uploadedFile;
  const zone = $("#dropzone");
  zone.classList.toggle("has-file", Boolean(file));
  $("#drop-prompt").hidden = Boolean(file);
  $("#uploaded-file").hidden = !file;
  if (file) {
    $("#uploaded-file-name").textContent = file.name;
    $("#uploaded-file-meta").textContent = `${formatFileSize(file.size)} · ${t("fileReady")}`;
  }
  $("#drop-prompt").setAttribute("aria-label", t("dropAria"));
  const clear = $("#clear-file");
  clear.setAttribute("aria-label", t("removeFile"));
  clear.title = t("removeFile");
}

function setEmptyMessage(titleKey, descriptionKey) {
  const empty = $("#empty-state");
  const title = empty.querySelector("strong");
  const description = empty.querySelector("p");
  title.dataset.i18n = titleKey;
  description.dataset.i18n = descriptionKey;
  title.textContent = t(titleKey);
  description.textContent = t(descriptionKey);
}

function applyLanguage(language, persist = false) {
  state.language = language;
  document.documentElement.lang = language === "zh" ? "zh-CN" : "en";
  document.querySelectorAll("[data-language]").forEach((button) => button.setAttribute("aria-pressed", String(button.dataset.language === language)));
  document.querySelectorAll("[data-i18n]").forEach((element) => {
    const key = element.dataset.i18n;
    element.textContent = t(key);
  });
  document.querySelectorAll("[data-i18n-aria]").forEach((element) => element.setAttribute("aria-label", t(element.dataset.i18nAria)));
  $("#file-name").textContent = state.name || t("noFile");
  if (state.report) {
    $("#result-roundtrip").textContent = state.report.roundtrip_equal ? t("roundtripPass") : t("roundtripDiff");
    $("#status").textContent = formatMessage("parsedStatus", { format: state.report.format, fields: state.report.trace.length });
  }
  if (state.errorKey) showError(state.errorKey, state.errorDetail);
  setEngineState(state.phase);
  updateUploadState();
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

function calculateBytesPerRow(width) {
  return Math.max(16, Math.min(32, Math.floor((width - HEX_HORIZONTAL_PADDING) / HEX_CELL_WIDTH)));
}

function renderHexWindow(force = false) {
  if (!state.bytes) return;
  const hex = $("#hex");
  const window = calculateHexWindow({
    byteLength: state.bytes.length,
    bytesPerRow: state.hexBytesPerRow,
    scrollTop: hex.scrollTop,
    viewportHeight: hex.clientHeight,
    rowHeight: HEX_ROW_HEIGHT,
    overscanRows: HEX_OVERSCAN_ROWS,
  });
  const range = state.paintedRange;
  const renderKey = `${window.startRow}:${window.endRow}:${state.hexBytesPerRow}:${range?.start ?? -1}:${range?.end ?? -1}`;
  if (!force && renderKey === state.hexRenderKey) return;

  const rows = [];
  for (let row = window.startRow; row < window.endRow; row += 1) {
    const rowStart = row * state.hexBytesPerRow;
    const rowEnd = Math.min(state.bytes.length, rowStart + state.hexBytesPerRow);
    const cells = [];
    for (let index = rowStart; index < rowEnd; index += 1) {
      const selected = range && index >= range.start && index < range.end;
      const classes = selected ? ' class="active pinned"' : "";
      cells.push(`<span${classes} data-byte-index="${index}" title="0x${index.toString(16).padStart(4, "0")}">${state.bytes[index].toString(16).padStart(2, "0")}</span>`);
    }
    rows.push(`<div class="hex-row" style="--hex-columns:${state.hexBytesPerRow}">${cells.join("")}</div>`);
  }
  hex.innerHTML = `<div class="hex-spacer" style="height:${window.topHeight}px"></div>${rows.join("")}<div class="hex-spacer" style="height:${window.bottomHeight}px"></div>`;
  state.hexRenderKey = renderKey;
}

function scheduleHexRender() {
  if (state.hexFrame) return;
  state.hexFrame = requestAnimationFrame(() => {
    state.hexFrame = 0;
    renderHexWindow();
  });
}

function updateHexLayout() {
  const hex = $("#hex");
  const nextColumns = calculateBytesPerRow(hex.clientWidth);
  if (nextColumns !== state.hexBytesPerRow) {
    const anchorByte = Math.floor(hex.scrollTop / HEX_ROW_HEIGHT) * state.hexBytesPerRow;
    state.hexBytesPerRow = nextColumns;
    hex.scrollTop = Math.floor(anchorByte / nextColumns) * HEX_ROW_HEIGHT;
  }
  state.hexRenderKey = "";
  renderHexWindow(true);
}

function paintRange(start, end, render = true) {
  state.paintedRange = start >= 0 && end > start ? { start, end } : null;
  state.hexRenderKey = "";
  if (render) renderHexWindow(true);
}

function scrollHexToByte(index) {
  const hex = $("#hex");
  const row = Math.floor(index / state.hexBytesPerRow);
  hex.scrollTop = Math.max(0, row * HEX_ROW_HEIGHT - (hex.clientHeight - HEX_ROW_HEIGHT) / 2);
  renderHexWindow(true);
}

function activateTrace(index, { scrollHex = false, scrollTrace = false, row = null } = {}) {
  const trace = $("#trace");
  const previous = state.activeTraceRow;
  if (previous) {
    previous.classList.remove("active");
    previous.setAttribute("aria-selected", "false");
  }
  state.pinnedTrace = index;
  const active = index >= 0 ? row || trace.children[index] : null;
  state.activeTraceRow = active;
  if (active) {
    active.classList.add("active");
    active.setAttribute("aria-selected", "true");
    if (scrollTrace) active.scrollIntoView({ block: "nearest", behavior: "auto" });
  }
  if (index < 0 || !state.report) paintRange(-1, -1);
  else {
    const entry = state.report.trace[index];
    paintRange(entry.start, entry.end, !scrollHex);
    if (scrollHex) scrollHexToByte(entry.start);
  }
}

function bindInspectorInteractions() {
  $("#trace").addEventListener("click", (event) => {
    const row = event.target.closest(".trace-row");
    if (!row) return;
    const index = Number(row.dataset.traceIndex);
    activateTrace(state.pinnedTrace === index ? -1 : index, { scrollHex: true, row });
  });
  const hex = $("#hex");
  hex.addEventListener("scroll", scheduleHexRender, { passive: true });
  hex.addEventListener("click", (event) => {
    const byte = event.target.closest("[data-byte-index]");
    if (!byte || !state.traceIndex) return;
    const index = state.traceIndex.find(Number(byte.dataset.byteIndex));
    if (index < 0) return;
    setView("trace");
    activateTrace(index, { scrollTrace: true });
    $("#trace-tab").focus({ preventScroll: true });
  });
  state.hexResizeObserver = new ResizeObserver(updateHexLayout);
  state.hexResizeObserver.observe(hex);
}

function render(report) {
  state.report = report;
  state.pinnedTrace = -1;
  state.paintedRange = null;
  state.traceIndex = new TraceIntervalIndex(report.trace);
  state.activeTraceRow = null;
  state.hexRenderKey = "";
  $("#result-format").textContent = report.format;
  $("#result-size").textContent = `${report.size} B`;
  $("#result-fields").textContent = report.trace.length;
  const roundtrip = $("#result-roundtrip");
  roundtrip.textContent = report.roundtrip_equal ? t("roundtripPass") : t("roundtripDiff");
  roundtrip.className = report.roundtrip_equal ? "success" : "danger";
  $("#file-name").textContent = state.name;
  $("#summary").innerHTML = report.summary.map(({ key, value }) => `<span>${escapeText(key)} · <b>${escapeText(value)}</b></span>`).join("");
  $("#schema").innerHTML = renderSchemaNode(report.schema);
  $("#trace").innerHTML = report.trace.map((entry, index) => `<button class="trace-row" type="button" role="option" aria-selected="false" data-trace-index="${index}"><span class="offset">${entry.start.toString(16).padStart(4, "0")}</span><span class="path" title="${escapeText(entry.path)}">${escapeText(entry.path || "root")}</span><span class="value" title="${escapeText(entry.value)}">${escapeText(entry.value)}</span></button>`).join("");
  const hex = $("#hex");
  hex.scrollTop = 0;
  state.hexBytesPerRow = calculateBytesPerRow(hex.clientWidth);
  renderHexWindow(true);
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
  if (file.size > MAX_FILE_BYTES) { $("#file").value = ""; showError("oversizedFile"); return; }
  document.querySelectorAll(".sample").forEach((button) => button.classList.remove("active"));
  state.uploadedFile = { name: file.name, size: file.size };
  updateUploadState();
  await inspectBytes(new Uint8Array(await file.arrayBuffer()), file.name);
}

function clearUploadedFile() {
  state.uploadedFile = null;
  state.bytes = null;
  state.name = "";
  state.report = null;
  state.pinnedTrace = -1;
  state.paintedRange = null;
  state.traceIndex = null;
  state.activeTraceRow = null;
  state.hexRenderKey = "";
  $("#file").value = "";
  $("#hex").replaceChildren();
  $("#schema").replaceChildren();
  $("#trace").replaceChildren();
  $("#result").hidden = true;
  $("#empty-state").hidden = false;
  $("#file-name").textContent = t("noFile");
  setEmptyMessage("idleTitle", "idleDescription");
  clearError();
  updateUploadState();
  $("#status").textContent = t("fileRemoved");
}

function bindControls() {
  document.querySelectorAll("[data-language]").forEach((button) => button.addEventListener("click", () => applyLanguage(button.dataset.language, true)));
  document.querySelectorAll("[data-view]").forEach((button) => button.addEventListener("click", () => setView(button.dataset.view)));
  $("#file").addEventListener("change", (event) => event.target.files[0] && openFile(event.target.files[0]));
  const zone = $("#dropzone");
  $("#drop-prompt").addEventListener("click", () => $("#file").click());
  for (const eventName of ["dragenter", "dragover"]) zone.addEventListener(eventName, (event) => { event.preventDefault(); if (!zone.classList.contains("disabled")) zone.classList.add("drag"); });
  for (const eventName of ["dragleave", "drop"]) zone.addEventListener(eventName, (event) => { event.preventDefault(); zone.classList.remove("drag"); });
  zone.addEventListener("drop", (event) => {
    const file = event.dataTransfer.files[0];
    if (file && !zone.classList.contains("disabled")) openFile(file);
  });
  $("#clear-file").addEventListener("click", (event) => {
    event.stopPropagation();
    clearUploadedFile();
  });
  document.querySelectorAll(".sample").forEach((button) => button.addEventListener("click", async () => {
    const format = button.dataset.format;
    state.uploadedFile = null;
    $("#file").value = "";
    updateUploadState();
    $("#format").value = format;
    document.querySelectorAll(".sample").forEach((candidate) => candidate.classList.toggle("active", candidate === button));
    await inspectBytes(fromHex(state.wasm.sample_hex(format)), `sample.${format === "bmff" ? "mp4" : format}`);
  }));
  $("#format").addEventListener("change", () => state.bytes && inspectBytes(state.bytes, state.name));
}

async function init() {
  applyLanguage(state.language);
  bindControls();
  bindInspectorInteractions();
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
