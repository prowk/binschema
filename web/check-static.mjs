import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = dirname(fileURLToPath(import.meta.url));
const html = readFileSync(join(root, "index.html"), "utf8");
const app = readFileSync(join(root, "app.js"), "utf8");
readFileSync(join(root, "favicon.svg"), "utf8");

const ids = [...html.matchAll(/\bid="([^"]+)"/g)].map((match) => match[1]);
assert.equal(new Set(ids).size, ids.length, "HTML id 必须唯一");

for (const id of ["format", "file", "dropzone", "engine-state", "empty-state", "result", "hex", "schema", "trace", "schema-tab", "trace-tab"]) {
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
assert(html.includes('<link rel="stylesheet" href="styles.css">'), "缺少本地样式表");
assert(html.includes('<link rel="icon" href="favicon.svg" type="image/svg+xml">'), "缺少本地图标");
assert(html.includes('<script type="module" src="app.js"></script>'), "缺少本地模块脚本");
assert(!/<script[^>]+src="https?:/i.test(html), "不得加载外部脚本");
assert(!/<link[^>]+href="https?:/i.test(html), "不得加载外部样式或字体");

console.log(`Static web checks passed: ${ids.length} ids, ${translationKeys.size} translation keys.`);
