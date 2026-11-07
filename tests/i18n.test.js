// Every string key the QML asks for must exist in i18n/en.json, so no label
// ever falls back to a raw key. Run: node tests/i18n.test.js
const fs = require("fs")
const path = require("path")
const assert = require("assert")

const root = path.join(__dirname, "..")
const en = JSON.parse(fs.readFileSync(path.join(root, "i18n", "en.json"), "utf8"))

for (const [key, value] of Object.entries(en)) {
  assert.strictEqual(typeof value, "string", `en.json "${key}" should be a string`)
  assert.ok(value.trim() !== "", `en.json "${key}" is empty`)
}

const used = new Set()
for (const file of ["Panel.qml", "Service.qml"]) {
  const src = fs.readFileSync(path.join(root, file), "utf8")
  for (const m of src.matchAll(/strings\.tn?\(\s*"([^"]+)"/g)) used.add(m[1])
  // Error keys reach strings.t() through service.errorKey.
  for (const m of src.matchAll(/errorKey\s*=\s*"([^"]+)"/g)) used.add(m[1])
}
const model = fs.readFileSync(path.join(root, "Model.js"), "utf8")
for (const m of model.matchAll(/return\s+"(error\.[^"]+)"/g)) used.add(m[1])

assert.ok(used.size > 10, "expected to find the widget's string keys")
const missing = [...used].filter(k => !(k in en))
assert.deepStrictEqual(missing, [], "keys used but missing from en.json")

const unused = Object.keys(en).filter(k => !used.has(k))
assert.deepStrictEqual(unused, [], "keys in en.json that nothing uses")

// Placeholders: every %N in a string should be filled by the code; at least
// check they're numbered from 1 without gaps.
for (const [key, value] of Object.entries(en)) {
  const nums = [...value.matchAll(/%(\d)/g)].map(m => Number(m[1])).sort()
  nums.forEach((n, i) => assert.strictEqual(n, i + 1, `"${key}" placeholders should be %1..%N`))
}

console.log("ok")
