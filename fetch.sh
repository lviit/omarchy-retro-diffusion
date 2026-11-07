#!/bin/bash

# Print the Retro Diffusion account summary (GET /v2/inferences/credits) as JSON.
#
# Usage: fetch.sh [--max-age SECONDS]
#
# The API key is read from $RD_API_KEY_FILE, or ~/.config/retro-diffusion/api-key,
# and handed to curl on stdin so it never shows up in the process list.
#
# Every bar (one per monitor) runs this script, so the answer is cached in
# $XDG_RUNTIME_DIR for up to --max-age seconds (default 5) behind a lock: the
# first caller fetches, the rest read the cached copy. Only successful
# responses are cached, and the cache file is named after a hash of the key,
# so switching keys never serves another account's numbers.
#
# Exit codes: 0 ok, 2 bad arguments, 3 no key file, 4 malformed key,
# 22 HTTP error, anything else = curl failure.

set -uo pipefail

max_age=5
while (( $# > 0 )); do
  case "$1" in
  --max-age)
    [[ ${2:-} =~ ^[0-9]{1,6}$ ]] || { echo "bad --max-age" >&2; exit 2; }
    max_age=$2
    shift 2
    ;;
  *)
    echo "unknown argument: $1" >&2
    exit 2
    ;;
  esac
done

key_file="${RD_API_KEY_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/retro-diffusion/api-key}"

if [[ ! -r $key_file ]]; then
  echo "no-key" >&2
  exit 3
fi

key=$(head -c 512 "$key_file" | tr -d '[:space:]')
if [[ ! $key =~ ^rdpk-[A-Za-z0-9_-]{8,256}$ ]]; then
  echo "bad-key" >&2
  exit 4
fi

fetch() {
  printf 'X-RD-Token: %s\n' "$key" |
    curl --silent --show-error --fail \
      --proto '=https' --tlsv1.2 \
      --connect-timeout 8 --max-time 15 \
      --max-filesize 65536 \
      -H @- \
      https://api.retrodiffusion.ai/v2/inferences/credits |
    head -c 65536
}

# No private runtime dir: skip the cache rather than fall back to a shared /tmp.
runtime_dir="${XDG_RUNTIME_DIR:-}"
if [[ -z $runtime_dir || ! -d $runtime_dir || ! -O $runtime_dir ]]; then
  fetch
  exit $?
fi

cache_dir="$runtime_dir/retro-diffusion-bar"
mkdir -p -m 700 "$cache_dir" || { fetch; exit $?; }

key_hash=$(printf '%s' "$key" | sha256sum | cut -c1-16)
cache="$cache_dir/credits-$key_hash.json"

exec 9>"$cache_dir/lock"
flock -w 20 9 || true

if [[ -s $cache ]]; then
  age=$(( $(date +%s) - $(stat -c %Y "$cache") ))
  if (( age >= 0 && age < max_age )); then
    cat "$cache"
    exit 0
  fi
fi

tmp=$(mktemp "$cache_dir/.credits.XXXXXX") || { fetch; exit $?; }
fetch >"$tmp"
status=$?
if (( status == 0 )) && [[ -s $tmp ]]; then
  mv -f "$tmp" "$cache"
  cat "$cache"
else
  rm -f "$tmp"
fi
exit $status
