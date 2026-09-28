import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { calculateHexWindow, TraceIntervalIndex } from "./inspector-core.mjs";

const root = dirname(fileURLToPath(import.meta.url));
const html = readFileSync(join(root, "index.html"), "utf8");
const app = readFileSync(join(root, "app.js"), "utf8");
const workflow = readFileSync(join(root, "..", ".github", "workflows", "pages.yml"), "utf8");
readFileSync(join(root, "favicon.svg"), "utf8");

const ids = [...html.matchAll(/\bid="([^"]+)"/g)].map((match) => match[1]);
assert.equal(new Set(ids).size, ids.length, "HTML id 必须唯一");

for (const id of ["format", "file", "dropzone", "drop-prompt", "uploaded-file", "uploaded-file-name", "uploaded-file-meta", "clear-file", "engine-state", "empty-state", "result", "hex", "schema", "trace", "schema-tab", "trace-tab"]) {
  assert(ids.includes(id), `缺少关键节点 #${id}`);
}

for (const match of app.matchAll(/\$\("#([^"]+)"\)/g)) {
  assert(ids.includes(match[1]), `app.js 引用了不存在的 #${match[1]}`);
}

const translationKeys = new Set([
  ...html.matchAll(/data-i18n="([^"]+)"/g),
  ...html.matchAll(/data-i18n-aria="([^"]+)"/g),
].map((match) => match[1]));
for (const key of translationKeys) {
  const occurrences = [...app.matchAll(new RegExp(`\\b${key}:`, "g"))].length;
  assert.equal(occurrences, 2, `翻译键 ${key} 必须同时存在于中英文词典`);
}

assert.equal([...html.matchAll(/class="sample"/g)].length, 6, "页面必须提供六种内置样例");
assert(html.includes('<link rel="stylesheet" href="styles.css?v=0.3.3">'), "缺少带版本标识的本地样式表");
assert(html.includes('<link rel="icon" href="favicon.svg" type="image/svg+xml">'), "缺少本地图标");
assert(html.includes('<script type="module" src="app.js?v=0.3.3"></script>'), "缺少带版本标识的本地模块脚本");
assert(!/<script[^>]+src="https?:/i.test(html), "不得加载外部脚本");
assert(!/<link[^>]+href="https?:/i.test(html), "不得加载外部样式或字体");
assert(!app.includes('addEventListener("mouseenter"'), "Trace 字段不得通过鼠标悬浮触发字节高亮");
assert(!app.includes('addEventListener("mouseleave"'), "Trace 字段不得通过鼠标移出改变字节高亮");
assert(!app.includes('behavior: "smooth"'), "定位必须即时完成，不得使用平滑滚动");
assert(app.includes('$("#trace").addEventListener("click"'), "Trace 字段应使用点击事件委托");
assert(app.includes('hex.addEventListener("click"'), "字节视图应使用点击事件委托");
assert(app.includes("calculateHexWindow"), "字节视图必须使用窗口化渲染");
assert(app.includes("scrollHexToByte(entry.start)"), "点击 Trace 字段后应滚动到对应字节");
assert(app.includes('$("#clear-file").addEventListener("click"'), "上传文件必须支持取消选择");
assert(app.includes('$("#drop-prompt").addEventListener("click"'), "上传提示必须使用独立按钮打开文件选择器");
assert(app.includes('zone.classList.toggle("has-file"'), "上传区必须呈现文件已载入状态");
assert(workflow.includes("web/inspector-core.mjs"), "Pages 构建必须包含字节视图核心模块");

const traceIndex = new TraceIntervalIndex([
  { start: 0, end: 20 },
  { start: 4, end: 10 },
  { start: 4, end: 10 },
  { start: 22, end: 25 },
  { start: 30, end: 30 },
]);
assert.equal(traceIndex.find(0), 0, "范围起点应被包含");
assert.equal(traceIndex.find(4), 1, "嵌套范围应选择最小范围");
assert.equal(traceIndex.find(9), 1, "等长范围应选择更靠前的 Trace");
assert.equal(traceIndex.find(10), 0, "内层范围终点应被排除");
assert.equal(traceIndex.find(20), -1, "范围终点应被排除");
assert.equal(traceIndex.find(21), -1, "范围空隙不应命中 Trace");
assert.equal(traceIndex.find(24), 3, "非重叠范围应正确命中");
assert.equal(traceIndex.find(25), -1, "最后一个范围的终点应被排除");
assert.equal(traceIndex.find(-1), -1, "负偏移不应命中 Trace");

assert.deepEqual(calculateHexWindow({
  byteLength: 100,
  bytesPerRow: 10,
  scrollTop: 40,
  viewportHeight: 40,
  rowHeight: 20,
  overscanRows: 1,
}), {
  totalRows: 10,
  startRow: 1,
  endRow: 5,
  startByte: 10,
  endByte: 50,
  topHeight: 20,
  bottomHeight: 100,
}, "中部窗口应包含上下缓冲行");
assert.equal(calculateHexWindow({ byteLength: 100, bytesPerRow: 10, scrollTop: 180, viewportHeight: 40, rowHeight: 20, overscanRows: 1 }).endByte, 100, "底部窗口不得越过输入末尾");
assert.equal(calculateHexWindow({ byteLength: 0, bytesPerRow: 16, scrollTop: 0, viewportHeight: 560, rowHeight: 26 }).totalRows, 0, "空输入不应创建字节行");

console.log(`Static web checks passed: ${ids.length} ids, ${translationKeys.size} translation keys.`);
