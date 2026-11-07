// Pure helpers for the Retro Diffusion widget. No QML imports, so the Node
// test in tests/ can load this file directly.
//
// Everything that comes back from the API is untrusted: numbers are range
// checked, strings are stripped of control characters and length capped, and
// anything with the wrong type is dropped.

var MAX_RESPONSE = 65536

function num(value, min, max) {
  if (typeof value !== "number" && typeof value !== "string") return null
  if (typeof value === "string" && value.trim() === "") return null
  var n = Number(value)
  if (!isFinite(n)) return null
  return Math.min(max, Math.max(min, n))
}

function str(value, max) {
  if (typeof value !== "string") return ""
  return value.replace(/[\u0000-\u001f\u007f-\u009f]/g, "").slice(0, max)
}

function obj(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : null
}

// period_end arrives as an ISO string from /v2/inferences/credits and as unix
// seconds from /usage; accept both. Returns epoch ms, or 0 when unusable.
function timestampMs(value) {
  var ms = 0
  if (typeof value === "number" && isFinite(value)) ms = value < 1e11 ? value * 1000 : value
  else if (typeof value === "string" && value.length <= 64) ms = Date.parse(value)
  if (!isFinite(ms)) return 0
  // Somewhere between 2020 and 2100, or it isn't a real billing date.
  if (ms < 1577836800000 || ms > 4102444800000) return 0
  return ms
}

function slots(value) {
  var s = obj(value)
  if (!s) return null
  var inUse = num(s.in_use, 0, 1000)
  var limit = num(s.limit, 0, 1000)
  if (inUse === null || limit === null) return null
  return { inUse: Math.round(inUse), limit: Math.round(limit) }
}

function parse(raw) {
  var text = String(raw === undefined || raw === null ? "" : raw)
  if (text.length === 0 || text.length > MAX_RESPONSE) return null
  var data
  try { data = JSON.parse(text) } catch (e) { return null }
  data = obj(data)
  if (!data) return null

  var usage = obj(data.usage) || {}
  var plan = obj(usage.plan)
  var allSlots = obj(usage.slots) || {}

  var balance = num(data.balance, -1e6, 1e7)
  if (balance === null) balance = num(usage.balance, -1e6, 1e7)
  if (balance === null) return null

  var info = {
    balance: balance,
    credits: num(data.credits, 0, 1e9),
    // What the last 30 days of jobs cost (or would have cost, on a plan) at
    // pay-as-you-go balance rates. Not money taken out of the balance.
    spend30: num(usage.last_30_days_balance_spend, 0, 1e7),
    apiSlots: slots(allSlots.api),
    webSlots: slots(allSlots.web),
    plan: null
  }

  if (plan) {
    var left = num(plan.usage_left_pct, 0, 100)
    info.plan = {
      name: str(plan.name, 40) || str(plan.key, 40),
      status: str(plan.status, 24),
      interval: str(plan.interval, 16),
      usageLeftPct: left === null ? null : Math.round(left),
      priceUsd: num(plan.price_usd, 0, 1e5),
      periodEndMs: timestampMs(plan.period_end),
      cancelAtPeriodEnd: plan.cancel_at_period_end === true
    }
  }
  return info
}

function planActive(info) {
  return !!(info && info.plan && info.plan.status === "active" && info.plan.usageLeftPct !== null)
}

function formatter(fmt) {
  return typeof fmt === "function" ? fmt : function(v, d) { return Number(v).toFixed(d === undefined ? 0 : d) }
}

function money(value, fmt) {
  if (value === null || value === undefined) return "—"
  var f = formatter(fmt)
  return (value < 0 ? "-$" : "$") + f(Math.abs(value), 2)
}

function percent(value, fmt) {
  if (value === null || value === undefined) return "—"
  return formatter(fmt)(value, 0) + "%"
}

// What the bar shows next to the icon.
function barText(info, mode, fmt) {
  if (!info) return ""
  if (mode !== "balance" && planActive(info)) return percent(info.plan.usageLeftPct, fmt)
  return money(info.balance, fmt)
}

// Plan nearly used up, or (without a plan) under a dollar of prepaid balance.
function isLow(info, lowPlanPct) {
  if (!info) return false
  if (planActive(info)) return info.plan.usageLeftPct <= lowPlanPct
  return info.balance < 1
}

function slotText(s, fmt) {
  if (!s) return "—"
  var f = formatter(fmt)
  return f(s.inUse, 0) + " / " + f(s.limit, 0)
}

// Map fetch.sh's exit code to a translation key.
function errorKey(exitCode) {
  if (exitCode === 3) return "error.noKey"
  if (exitCode === 4) return "error.badKey"
  if (exitCode === 22) return "error.rejected"
  return "error.unreachable"
}
