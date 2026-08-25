#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
[[ -z "$(git -C "$root" status --porcelain --untracked-files=no)" ]] || {
  echo "error: reproducibility check requires no tracked-file modifications" >&2
  exit 1
}
[[ -z "$(git -C "$root" ls-files '*.wasm')" ]] || {
  echo "error: generated Wasm is tracked" >&2
  exit 1
}

temporary=$(mktemp -d "${TMPDIR:-/tmp}/echo-provider-repro.XXXXXX")
cleanup() {
  rm -rf "$temporary"
}
trap cleanup EXIT INT TERM
mkdir "$temporary/source-a" "$temporary/source-b"
git -C "$root" archive --format=tar HEAD | tar -xf - -C "$temporary/source-a"
git -C "$root" archive --format=tar HEAD | tar -xf - -C "$temporary/source-b"

(
  cd "$temporary/source-a"
  ./scripts/build-component.sh
)
(
  cd "$temporary/source-b"
  ./scripts/build-component.sh
)

core=target/wasm32-unknown-unknown/release/dekopon_echo_provider.wasm
cmp "$temporary/source-a/$core" "$temporary/source-b/$core"
cmp "$temporary/source-a/echo-provider.wasm" "$temporary/source-b/echo-provider.wasm"
cmp "$temporary/source-a/echo-provider.wasm.sha256" \
  "$temporary/source-b/echo-provider.wasm.sha256"
wasm-tools validate "$temporary/source-a/echo-provider.wasm"
printf 'two clean pinned builds reproduced core and component sha256 %s\n' \
  "$(awk '{print $1}' "$temporary/source-a/echo-provider.wasm.sha256")"
