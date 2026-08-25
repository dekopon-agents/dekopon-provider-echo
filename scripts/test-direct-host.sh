#!/usr/bin/env bash
# shellcheck disable=SC2154 # root/component are assigned by sourced lib-component.sh.
set -euo pipefail

# shellcheck source=lib-component.sh
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib-component.sh" "$@"
[[ -f "$component" ]] || { echo "error: missing $component" >&2; exit 1; }
[[ "$(dekopon-run --version)" == "dekopon-run 0.11.1" ]] || {
  echo "error: dekopon-run 0.11.1 is required" >&2
  exit 1
}

invoke --input '{"nested":{"answer":42},"unicode":"🦀"}' | jq -e '
  .provider == "echo" and .capability == "echo.echo" and
  .output == {"nested":{"answer":42},"unicode":"🦀"}
' >/dev/null

for fixture in \
  'echo.reverse|a🦀é|é🦀a' \
  'echo.upcase|Straße|STRASSE' \
  'echo.downcase|Δ WORLD|δ world' \
  'echo.ransom-case|Hello, World!|hElLo, WoRlD!'; do
  IFS='|' read -r capability input expected <<<"$fixture"
  output=$(jq -cn --arg message "$input" '{message:$message}' |
    invoke_capability "$capability" --input-file -)
  jq -e --arg capability "$capability" --arg expected "$expected" '
    .provider == "echo" and .capability == $capability and
    .output == {message:$expected}
  ' <<<"$output" >/dev/null
done

if invoke_capability echo.upcase --input '{"message":"x","extra":true}' \
  >"$root/target/direct-invalid.out" 2>"$root/target/direct-invalid.err"; then
  echo "error: closed transformation schema unexpectedly succeeded" >&2
  exit 1
fi
grep -Fq 'input must contain exactly one string field named "message"' \
  "$root/target/direct-invalid.err"

printf 'direct host manifest, identity, all transformations, and rejection tests passed\n'
