#!/bin/bash
# Tests for fetch.sh against a fake curl. No network access.
# Run: bash tests/fetch.test.sh

set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
fetch="$here/../fetch.sh"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/bin" "$work/run"
chmod 700 "$work/run"

# Fake curl: records its arguments, stdin and call count, then behaves
# according to $FAKE_CURL_MODE (ok | http | down).
cat >"$work/bin/curl" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" >"$FAKE_DIR/args"
cat >"$FAKE_DIR/stdin"
echo x >>"$FAKE_DIR/calls"
sleep "${FAKE_CURL_DELAY:-0}"
case "${FAKE_CURL_MODE:-ok}" in
  ok) printf '{"credits":50,"balance":%s}' "${FAKE_BALANCE:-1.8}" ;;
  http) echo "curl: (22) The requested URL returned error: 401" >&2; exit 22 ;;
  down) echo "curl: (6) Could not resolve host" >&2; exit 6 ;;
esac
EOF
chmod +x "$work/bin/curl"

export PATH="$work/bin:$PATH"
export FAKE_DIR="$work"
export XDG_RUNTIME_DIR="$work/run"

key="rdpk-TESTKEY_0123456789abcdef"
printf '%s\n' "$key" >"$work/key"
export RD_API_KEY_FILE="$work/key"

failures=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
calls() { [[ -f $work/calls ]] && wc -l <"$work/calls" | tr -d ' ' || echo 0; }
reset() { rm -f "$work/calls" "$work/args" "$work/stdin"; rm -rf "$work/run/retro-diffusion-bar"; }

# --- key handling -----------------------------------------------------------
reset
RD_API_KEY_FILE="$work/missing" bash "$fetch" >/dev/null 2>&1; code=$?
check "missing key file exits 3" '[[ $code == 3 ]]'
check "missing key file never calls curl" '[[ $(calls) == 0 ]]'

printf 'not-a-key\n' >"$work/badkey"
RD_API_KEY_FILE="$work/badkey" bash "$fetch" >/dev/null 2>&1; code=$?
check "malformed key exits 4" '[[ $code == 4 ]]'

printf 'rdpk-abc$(touch %s/pwned)\n' "$work" >"$work/evilkey"
RD_API_KEY_FILE="$work/evilkey" bash "$fetch" >/dev/null 2>&1; code=$?
check "key with shell syntax is rejected" '[[ $code == 4 && ! -e $work/pwned ]]'

bash "$fetch" --max-age nope >/dev/null 2>&1; code=$?
check "bad --max-age exits 2" '[[ $code == 2 ]]'

# --- success, and the key stays out of argv ---------------------------------
reset
out=$(bash "$fetch" --max-age 0); code=$?
check "success exits 0" '[[ $code == 0 ]]'
check "success prints the API response" '[[ $out == "{\"credits\":50,\"balance\":1.8}" ]]'
check "key is not passed on the command line" '! grep -qF "$key" "$work/args"'
check "key is sent as an X-RD-Token header on stdin" 'grep -qxF "X-RD-Token: $key" "$work/stdin"'
check "request is HTTPS-only to the credits endpoint" 'grep -qxF "=https" "$work/args" && grep -qxF "https://api.retrodiffusion.ai/v2/inferences/credits" "$work/args"'

# --- cache ------------------------------------------------------------------
before=$(calls)
bash "$fetch" --max-age 60 >/dev/null
check "fresh cache answers without calling curl" '[[ $(calls) == $before ]]'

bash "$fetch" --max-age 0 >/dev/null
check "--max-age 0 always fetches" '[[ $(calls) == $((before + 1)) ]]'

check "cache dir is private" '[[ $(stat -c %a "$work/run/retro-diffusion-bar") == 700 ]]'
check "cache file does not contain the key" '! grep -rqF "$key" "$work/run/retro-diffusion-bar"'

# Another key must not read this key's cache.
printf 'rdpk-OTHERKEY_0123456789abcdef\n' >"$work/key2"
before=$(calls)
FAKE_BALANCE=99 RD_API_KEY_FILE="$work/key2" bash "$fetch" --max-age 600 >/dev/null
check "a different key gets its own cache" '[[ $(calls) == $((before + 1)) ]]'

# --- failures ---------------------------------------------------------------
reset
bash "$fetch" --max-age 0 >/dev/null
good=$(cat "$work"/run/retro-diffusion-bar/credits-*.json)
FAKE_CURL_MODE=http bash "$fetch" --max-age 0 >/dev/null 2>&1; code=$?
check "HTTP error exits 22" '[[ $code == 22 ]]'
check "HTTP error keeps the last good cache" '[[ $(cat "$work"/run/retro-diffusion-bar/credits-*.json) == "$good" ]]'
check "HTTP error leaves no temp files" '[[ -z $(find "$work/run/retro-diffusion-bar" -name ".credits.*") ]]'

FAKE_CURL_MODE=down bash "$fetch" --max-age 0 >/dev/null 2>&1; code=$?
check "network failure exits with curl's code" '[[ $code == 6 ]]'

# --- several bars at once ---------------------------------------------------
reset
for i in 1 2 3; do
  FAKE_CURL_DELAY=0.3 bash "$fetch" --max-age 60 >"$work/par$i" &
done
wait
check "three bars refreshing together make one request" '[[ $(calls) == 1 ]]'
check "all three bars get the answer" 'grep -q balance "$work/par1" && grep -q balance "$work/par2" && grep -q balance "$work/par3"'

# --- no runtime dir ---------------------------------------------------------
reset
out=$(XDG_RUNTIME_DIR= bash "$fetch"); code=$?
check "works without XDG_RUNTIME_DIR" '[[ $code == 0 && $out == *balance* ]]'
check "no cache without XDG_RUNTIME_DIR" '[[ ! -d $work/run/retro-diffusion-bar ]]'

echo
if (( failures > 0 )); then
  echo "$failures test(s) failed"
  exit 1
fi
echo "all fetch tests passed"
