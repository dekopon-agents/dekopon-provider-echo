#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
component=${1:-"$root/echo-provider.wasm"}
[[ -f "$component" ]] || { echo "error: missing $component" >&2; exit 1; }
[[ "$(wasmtime --version)" == "wasmtime 48.0.0" ]] || {
  echo "error: wasmtime 48.0.0 is required" >&2
  exit 1
}

raw_invoke() {
  local capability=$1 raw=$2 quoted_capability quoted_raw
  quoted_capability=$(jq -rn --arg value "$capability" '$value | tojson')
  quoted_raw=$(jq -rn --arg value "$raw" '$value | tojson')
  wasmtime run --invoke "invoke($quoted_capability,$quoted_raw)" "$component" | jq -r .
}

description=$(wasmtime run --invoke 'describe()' "$component" | jq -r .)
jq -e '
  .apiVersion == "dekopon.dev/provider/v1alpha1" and .id == "echo" and .commandWords == [] and
  [.capabilities[].id] == ["echo.echo","echo.reverse","echo.upcase","echo.downcase","echo.ransom-case"] and
  ([.capabilities[].effect] | all(. == "read-only")) and
  ([.capabilities[].risk] | all(. == "Low")) and
  ([.capabilities[].idempotency] | all(. == "idempotent"))
' <<<"$description" >/dev/null

raw_invoke echo.echo '{"nested":[null,true,"🦀"]}' | jq -e '
  .outcome == "succeeded" and .output == {"nested":[null,true,"🦀"]}
' >/dev/null
raw_invoke echo.upcase '{"message":"Straße"}' | jq -e '
  .outcome == "succeeded" and .output == {"message":"STRASSE"}
' >/dev/null

for raw in '{"message":' '{"message":"hit"} trailing'; do
  response=$(raw_invoke echo.other "$raw")
  jq -e '.outcome == "failed" and .error.code == "invalid-input"' <<<"$response" >/dev/null
done

# serde_json retains the last duplicate key before the provider receives the semantic Value.
raw_invoke echo.upcase '{"message":"miss","message":"hit"}' | jq -e '
  .outcome == "succeeded" and .output == {"message":"HIT"}
' >/dev/null
raw_invoke echo.reverse '{"message":"x","unknown":true}' | jq -e '
  .outcome == "failed" and .error.code == "invalid-input" and
  .error.message == "input must contain exactly one string field named \"message\""
' >/dev/null

printf 'raw component manifest, SDK parsing, duplicate-name, and provider boundary tests passed\n'
