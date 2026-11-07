// Run: node tests/model.test.js
const fs = require("fs")
const path = require("path")
const vm = require("vm")
const assert = require("assert")

const ctx = {}
vm.createContext(ctx)
vm.runInContext(fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8"), ctx)
const M = ctx

const sample = JSON.stringify({
  credits: 50,
  balance: 1.8000000000000025,
  usage: {
    plan: { key: "starter", name: "Starter", status: "active", interval: "month", usage_left_pct: 96, price_usd: 10.0,
            period_end: "2026-12-06T22:46:13+00:00", cancel_at_period_end: false },
    balance: 1.8,
    slots: { web: { in_use: 0, limit: 5 }, api: { in_use: 1, limit: 2 } },
    last_30_days_balance_spend: 4.92
  }
})

let info = M.parse(sample)
assert.strictEqual(info.balance, 1.8000000000000025)
assert.strictEqual(info.plan.name, "Starter")
assert.strictEqual(info.plan.usageLeftPct, 96)
assert.strictEqual(info.plan.periodEndMs, Date.parse("2026-12-06T22:46:13Z"))
assert.strictEqual(M.barText(info, "plan"), "96%")
assert.strictEqual(M.barText(info, "balance"), "$1.80")
assert.strictEqual(M.slotText(info.apiSlots), "1 / 2")
assert.strictEqual(M.money(info.spend30), "$4.92")
assert.strictEqual(M.money(info.plan.priceUsd), "$10.00")
assert.strictEqual(M.isLow(info, 10), false)

// /usage style unix-seconds period_end.
info = M.parse(JSON.stringify({ balance: 3, usage: { plan: { name: "X", status: "active", usage_left_pct: 5, period_end: 1796597173 } } }))
assert.strictEqual(info.plan.periodEndMs, 1796597173000)
assert.strictEqual(M.isLow(info, 10), true)

// No plan: falls back to balance, low under a dollar.
info = M.parse(JSON.stringify({ balance: 0.4 }))
assert.strictEqual(info.plan, null)
assert.strictEqual(M.barText(info, "plan"), "$0.40")
assert.strictEqual(M.isLow(info, 10), true)

// Inactive plan is not shown as plan usage.
info = M.parse(JSON.stringify({ balance: 5, usage: { plan: { name: "Starter", status: "canceled", usage_left_pct: 80 } } }))
assert.strictEqual(M.planActive(info), false)
assert.strictEqual(M.barText(info, "plan"), "$5.00")

// Markup-shaped and oversized strings are neutralised to plain, bounded text.
info = M.parse(JSON.stringify({ balance: 1, usage: { plan: { status: "active", usage_left_pct: 50,
  name: "<img src=\"https://example.invalid/tracker\">\u0007" + "A".repeat(500) } } }))
assert.ok(info.plan.name.length <= 40)
assert.ok(!/[\u0000-\u001f]/.test(info.plan.name))

// Out-of-range and wrong-typed values are clamped or dropped.
info = M.parse(JSON.stringify({ balance: "12.5", usage: { plan: { status: "active", usage_left_pct: 900, period_end: "garbage" },
  slots: { api: { in_use: "x", limit: 2 } } } }))
assert.strictEqual(info.balance, 12.5)
assert.strictEqual(info.plan.usageLeftPct, 100)
assert.strictEqual(info.plan.periodEndMs, 0)
assert.strictEqual(info.apiSlots, null)

// Garbage in, null out.
for (const bad of ["", "not json", "[]", "null", JSON.stringify({ balance: null }), "x".repeat(70000)]) {
  assert.strictEqual(M.parse(bad), null, "should reject: " + bad.slice(0, 20))
}

assert.strictEqual(M.errorKey(3), "error.noKey")
assert.strictEqual(M.errorKey(22), "error.rejected")
assert.strictEqual(M.errorKey(6), "error.unreachable")

console.log("ok")
