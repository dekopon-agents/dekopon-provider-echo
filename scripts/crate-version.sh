#!/usr/bin/env bash
# Print the one authoritative crate version: Cargo.toml, through the locked metadata.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cargo metadata --locked --no-deps --format-version 1 --manifest-path "$root/Cargo.toml" |
  jq -er '.packages[] | select(.name == "dekopon-echo-provider") | .version'
