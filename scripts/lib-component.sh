#!/usr/bin/env bash
# shellcheck shell=bash
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
component=${1:-"$root/echo-provider.wasm"}
cache="$root/target/dekopon-run-compile-cache"
release_fuel=50000000
mkdir -p "$cache"

invoke_capability_with_fuel() {
  local capability=$1 fuel=$2
  shift 2
  dekopon-run invoke \
    --provider "$component" \
    --compile-cache "$cache" \
    --max-memory-bytes 67108864 \
    --max-input-bytes 1048576 \
    --max-output-bytes 1048576 \
    --fuel "$fuel" \
    --timeout-ms 30000 \
    "$capability" "$@"
}

invoke_capability() {
  local capability=$1
  shift
  invoke_capability_with_fuel "$capability" "$release_fuel" "$@"
}

invoke() {
  invoke_capability echo.echo "$@"
}
