#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
lock=${1:-Cargo.lock}
notices=${2:-THIRD_PARTY_NOTICES.md}
[[ -f "$lock" && -f "$notices" ]] || { echo "error: lockfile and notices are required" >&2; exit 1; }

require_locked() {
  local name=$1 version=$2
  awk -v name="$name" -v version="$version" '
    $0 == "name = \"" name "\"" { found_name = 1; next }
    found_name && $0 == "version = \"" version "\"" { found = 1 }
    found_name && /^$/ { found_name = 0 }
    END { exit !found }
  ' "$lock" || { echo "error: $name $version is not locked" >&2; exit 1; }
  grep -Fq "$name" "$notices" || { echo "error: notices omit $name" >&2; exit 1; }
  grep -Fq "$version" "$notices" || { echo "error: notices omit version $version" >&2; exit 1; }
}

require_locked dekopon-provider-sdk 0.13.0
require_locked dekopon-provider-sdk-testkit 0.13.0
require_locked serde 1.0.229
require_locked serde_json 1.0.151
require_locked foldhash 0.2.0
require_locked unicode-ident 1.0.24

for phrase in \
  'Cargo.lock is the authority' \
  'dekopon.third-party-notices' \
  'zero imports' \
  'only in native development/test' \
  'LICENSE-MIT' \
  'LICENSE-APACHE'; do
  grep -Fq "$phrase" "$notices" || {
    echo "error: notices omit required statement: $phrase" >&2
    exit 1
  }
done

bundle=$(mktemp "${TMPDIR:-/tmp}/echo-license-bundle.XXXXXX")
trap 'rm -f "$bundle"' EXIT
"$root/scripts/embed-license-bundle.py" write "$bundle" "$root"
for source in "$root/THIRD_PARTY_NOTICES.md" "$root/LICENSE-MIT" "$root/LICENSE-APACHE"; do
  python3 - "$bundle" "$source" <<'PY'
import pathlib
import sys
bundle = pathlib.Path(sys.argv[1]).read_bytes()
source = pathlib.Path(sys.argv[2]).read_bytes()
if bundle.count(source) != 1:
    raise SystemExit(f"error: bundle does not contain {sys.argv[2]} exactly once")
PY
done
printf 'third-party notices and exact embedded distribution-license bundle cover the shipped graph\n'
