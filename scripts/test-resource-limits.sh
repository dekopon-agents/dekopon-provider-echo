#!/usr/bin/env bash
# shellcheck disable=SC2154 # root/component/release_fuel are assigned by sourced library.
set -euo pipefail

# shellcheck source=lib-component.sh
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib-component.sh" "$@"
[[ -f "$component" ]] || { echo "error: missing $component" >&2; exit 1; }
[[ "$release_fuel" -eq 50000000 ]]

near_limit="$root/target/echo-near-limit.json"
oversize="$root/target/echo-oversize.json"
python3 - "$near_limit" "$oversize" <<'PY'
import json
import pathlib
import sys
pathlib.Path(sys.argv[1]).write_text(json.dumps({"data": "x" * 900_000}), encoding="utf-8")
# NUL escaping makes this semantic value exceed the host's 1 MiB serialized input limit.
pathlib.Path(sys.argv[2]).write_text(json.dumps({"data": "\0" * 180_000}), encoding="utf-8")
PY
[[ $(wc -c <"$near_limit" | tr -d ' ') -lt 1048576 ]]
[[ $(wc -c <"$oversize" | tr -d ' ') -gt 1048576 ]]

output="$root/target/echo-near-limit-output.json"
invoke --input-file "$near_limit" >"$output"
jq -e '.output.data | length == 900000' "$output" >/dev/null
[[ $(wc -c <"$output" | tr -d ' ') -lt 1048576 ]]

if invoke --input-file "$oversize" \
  >"$root/target/echo-oversize.out" 2>"$root/target/echo-oversize.err"; then
  echo "error: over-1-MiB wire input unexpectedly succeeded" >&2
  exit 1
fi
grep -Eqi 'input.*(large|maximum|1048576)|exceeds.*input' "$root/target/echo-oversize.err"

# The exact release host settings must execute Unicode case expansion with ample fuel headroom.
message=$(python3 - <<'PY'
print("Straße " * 10000, end="")
PY
)
printf '%s' "$message" | jq -Rs '{message:.}' |
  invoke_capability_with_fuel echo.upcase "$release_fuel" --input-file - |
  jq -e '.output.message | startswith("STRASSE STRASSE")' >/dev/null

printf '50M fuel, 64 MiB memory, 30s deadline, and 1 MiB wire/output resource gates passed\n'
