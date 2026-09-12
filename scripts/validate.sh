#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$root"
version=$(./scripts/crate-version.sh)
./scripts/validate-source.sh
./scripts/build-component.sh
./scripts/inspect-component.sh
./scripts/test-raw-component.sh
./scripts/test-broker-testkit.sh
./scripts/prepare-release-assets.sh "$version" "$root/dist"
./scripts/verify-release-assets.sh "$root/dist"
printf 'all v%s source, component, raw-host, testkit, and resource gates passed\n' "$version"
