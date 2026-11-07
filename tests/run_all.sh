#!/bin/bash
# Run every test. Needs bash, node, flock and sha256sum; never touches the network.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== model";  node tests/model.test.js
echo "== i18n";   node tests/i18n.test.js
echo "== fetch";  bash tests/fetch.test.sh
echo "== manifest"
if command -v omarchy >/dev/null; then
  omarchy plugin validate . && echo ok
else
  echo "skipped (omarchy not installed)"
fi
