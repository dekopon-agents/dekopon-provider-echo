#!/usr/bin/env bash
# shellcheck disable=SC2016 # Required workflow snippets are literal strings.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
ci="$root/.github/workflows/ci.yml"
release="$root/.github/workflows/release.yml"
verifier="$root/scripts/verify-oci-manifest.py"
[[ -f "$ci" && -f "$release" && -f "$verifier" ]] || {
  echo "error: CI, release workflow, and OCI verifier are required" >&2
  exit 1
}

python3 - "$ci" "$release" <<'PY'
import pathlib
import re
import sys
for path_string in sys.argv[1:]:
    path = pathlib.Path(path_string)
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        match = re.match(r"\s*uses:\s*([^\s#]+)", line)
        if match and not re.fullmatch(r"[^@]+@[0-9a-f]{40}", match.group(1)):
            raise SystemExit(f"error: {path}:{number}: Action is not full-SHA pinned")
PY

for required in \
  'tags:' \
  '"v0.1.0"' \
  'test "$(git cat-file -t "refs/tags/$GITHUB_REF_NAME")" = tag' \
  'git merge-base --is-ancestor "$GITHUB_SHA" refs/remotes/origin/main' \
  'application/vnd.dekopon.provider.v1+wasm' \
  'echo-provider.wasm:application/wasm' \
  'org.dekopon.release.run' \
  'org.opencontainers.image.licenses=MIT OR Apache-2.0' \
  'embedded:dekopon.third-party-notices' \
  'provider-echo/versions' \
  'echo-provider.wasm.sha256' \
  'name: release-sbom' \
  'predicate-type: https://cyclonedx.org/bom' \
  'subject-path: dist/echo-provider.wasm' \
  'needs.verify_final.result != '\''success'\''' \
  'manifest is missing, shared, or has another tag/version' \
  'This PATCH is the release transaction' \
  'make_latest: "false"' \
  'permissions: {}' \
  'verify-attestation-anonymously.sh' \
  'draft: false'; do
  grep -Fq "$required" "$release" || {
    echo "error: release workflow omits required interlock: $required" >&2
    exit 1
  }
done

if grep -Eq 'ghcr[.]io/dekopon-agents/provider-echo:(latest|staging|tmp|temp)' "$release"; then
  echo "error: release names a mutable or secondary package tag" >&2
  exit 1
fi
if grep -Eq 'CARGO_TARGET_DIR|SCCACHE_DIR|cargo clean|pull_request_target' "$ci" "$release"; then
  echo "error: workflow violates target/cache/event policy" >&2
  exit 1
fi

python3 - "$release" <<'PY'
import pathlib
import sys
text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
ghcr = text.index("  ghcr:")
finalize = text.index("  finalize:", ghcr)
anonymous = text.index("Recheck draft assets and every anonymous OCI byte, then finalize")
patch = text.index("# This PATCH is the release transaction")
verify_final = text.index("  verify_final:", patch)
cleanup = text.index("  cleanup_failed_release:", verify_final)
if not ghcr < finalize <= anonymous < patch < verify_final < cleanup:
    raise SystemExit("error: GHCR/finalization/anonymous-verification/cleanup ordering drifted")
if text.count("gh release create v0.1.0") != 1:
    raise SystemExit("error: draft creation cardinality drifted")
if text.count('"$RUNNER_TEMP/oras-bin" push "$ref"') != 1:
    raise SystemExit("error: OCI push cardinality drifted")
if text.count("echo-provider.wasm:application/wasm") != 1:
    raise SystemExit("error: OCI layer cardinality drifted")
if text.count("actions/attest-build-provenance@") != 1 or text.count("actions/attest@") != 1:
    raise SystemExit("error: provenance/SBOM attestation cardinality drifted")
if text.count("# This PATCH is the release transaction") != 1:
    raise SystemExit("error: final release transaction cardinality drifted")
PY

temporary=$(mktemp -d "${TMPDIR:-/tmp}/echo-oci-verifier.XXXXXX")
trap 'rm -rf "$temporary"' EXIT
printf 'component fixture\n' >"$temporary/echo-provider.wasm"
python3 - "$temporary/manifest.json" "$temporary/echo-provider.wasm" <<'PY'
import hashlib
import json
import pathlib
import sys
component = pathlib.Path(sys.argv[2]).read_bytes()
manifest = {
    "schemaVersion": 2,
    "artifactType": "application/vnd.dekopon.provider.v1+wasm",
    "config": {"size": 2},
    "annotations": {
        "org.opencontainers.image.source": "https://github.com/dekopon-agents/dekopon-provider-echo",
        "org.opencontainers.image.version": "0.1.0",
        "org.opencontainers.image.revision": "a" * 40,
        "org.opencontainers.image.licenses": "MIT OR Apache-2.0",
        "org.dekopon.distribution.notices": "embedded:dekopon.third-party-notices",
        "org.dekopon.release.run": "1:1",
        "org.dekopon.release.url": "https://github.com/dekopon-agents/dekopon-provider-echo/releases/tag/v0.1.0",
        "org.dekopon.provider.capability": "echo.echo",
    },
    "layers": [{
        "mediaType": "application/wasm",
        "digest": "sha256:" + hashlib.sha256(component).hexdigest(),
        "size": len(component),
        "annotations": {"org.opencontainers.image.title": "echo-provider.wasm"},
    }],
}
pathlib.Path(sys.argv[1]).write_text(json.dumps(manifest), encoding="utf-8")
PY
"$verifier" "$temporary/manifest.json" "$temporary/echo-provider.wasm" \
  1:1 "$(printf 'a%.0s' {1..40})"
python3 - "$temporary/manifest.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
manifest = json.loads(path.read_text(encoding="utf-8"))
manifest["layers"][0]["annotations"]["org.opencontainers.image.title"] = "dist/echo-provider.wasm"
path.write_text(json.dumps(manifest), encoding="utf-8")
PY
if "$verifier" "$temporary/manifest.json" "$temporary/echo-provider.wasm" \
  1:1 "$(printf 'a%.0s' {1..40})" >/dev/null 2>&1; then
  echo 'error: OCI verifier accepted a path-bearing layer title' >&2
  exit 1
fi

printf 'workflow pins, least-privilege transaction interlocks, attestations, and OCI verifier passed\n'
