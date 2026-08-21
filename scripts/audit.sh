#!/usr/bin/env bash
set -euo pipefail

idh_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
luau_bin="${LUAU_COMPILE_BIN:-luau-compile}"

if ! command -v "$luau_bin" >/dev/null 2>&1; then
  echo "FAIL: luau-compile tidak ditemukan"
  exit 1
fi

for source_file in NazhanHub.lua autofish.lua automining.lua copyavatar.lua; do
  "$luau_bin" "$idh_root/$source_file" >/dev/null
  echo "PASS: syntax $source_file"
done

git -C "$idh_root" diff --check
echo "PASS: git diff --check"

rg -q 'MouseButton1.*Touch.*Space' "$idh_root/docs/protocol.md"
rg -q 'ButtonR2' "$idh_root/docs/protocol.md"
rg -q 'SendMouseButtonEvent' "$idh_root/NazhanHub.lua"
rg -q 'PlayerGui","Reeling' "$idh_root/NazhanHub.lua"
echo "PASS: fishing protocol markers"

if rg -n -i '(discord(app)?\.com/api/webhooks|api[_-]?key\s*=|password\s*=|bearer\s+[a-z0-9._-]+)' \
  "$idh_root" --glob '!scripts/audit.sh' --glob '!.git/**'; then
  echo "FAIL: pola credential atau webhook ditemukan"
  exit 1
fi
echo "PASS: no credential or webhook pattern"
