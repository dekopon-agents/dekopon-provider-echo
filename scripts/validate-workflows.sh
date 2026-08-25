#!/usr/bin/env bash
# shellcheck disable=SC2016 # Required workflow snippets are literal strings.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
ci="$root/.github/workflows/ci.yml"
release="$root/.github/workflows/release.yml"
verifier="$root/scripts/verify-oci-manifest.py"
attestation_verifier="$root/scripts/verify-attestation-anonymously.sh"
[[ -f "$ci" && -f "$release" && -f "$verifier" && -f "$attestation_verifier" ]] || {
  echo "error: CI, release workflow, attestation verifier, and OCI verifier are required" >&2
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
  'test "$(git rev-parse refs/remotes/origin/main)" = "$GITHUB_SHA"' \
  'for _attempt in {1..30}; do' \
  'multiple run-owned drafts became visible' \
  'Revalidate immutable source identity immediately before the final mutation' \
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
  'final-tags.json' \
  'final-versions.jsons' \
  'final-owned-draft.json' \
  'This PATCH is the release transaction' \
  'make_latest: "false"' \
  'permissions: {}' \
  'verify-attestation-anonymously.sh' \
  '"$GITHUB_RUN_ID" "$GITHUB_RUN_ATTEMPT"' \
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
if sed -n '/^  draft:/,/^  ghcr:/p' "$release" | grep -Fq 'id-token: write'; then
  echo "error: draft job has unnecessary OIDC authority" >&2
  exit 1
fi
if ! sed -n '/^  finalize:/,/^  verify_final:/p' "$release" | grep -Fq 'packages: read'; then
  echo "error: finalize job cannot revalidate package cardinality" >&2
  exit 1
fi

python3 - "$release" <<'PY'
import pathlib
import sys
text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
ghcr = text.index("  ghcr:")
finalize = text.index("  finalize:", ghcr)
anonymous = text.index("Recheck draft assets and every anonymous OCI byte, then finalize")
final_tags = text.index("final-tags.json", anonymous)
final_versions = text.index("final-versions.jsons", final_tags)
final_draft = text.index("final-owned-draft.json", final_versions)
patch = text.index("# This PATCH is the release transaction", final_draft)
verify_final = text.index("  verify_final:", patch)
cleanup = text.index("  cleanup_failed_release:", verify_final)
if not ghcr < finalize <= anonymous < final_tags < final_versions < final_draft < patch < verify_final < cleanup:
    raise SystemExit("error: GHCR/finalization/cardinality/anonymous-verification/cleanup ordering drifted")
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

temporary=$(mktemp -d "${TMPDIR:-/tmp}/echo-workflow-verifiers.XXXXXX")
trap 'rm -rf "$temporary"' EXIT
mkdir "$temporary/mock-bin"
printf 'component fixture\n' >"$temporary/echo-provider.wasm"
cat >"$temporary/attestations.json" <<'JSON'
{"attestations":[{"bundle":{"attempt":"old"}},{"bundle":{"attempt":"current"}}]}
JSON
cat >"$temporary/mock-bin/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
output=
while [[ $# -gt 0 ]]; do
  if [[ "$1" == --output ]]; then output=$2; shift 2; else shift; fi
done
cp "$MOCK_ATTESTATIONS" "$output"
printf '200'
SH
cat >"$temporary/mock-bin/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
bundle=
while [[ $# -gt 0 ]]; do
  if [[ "$1" == --bundle ]]; then bundle=$2; shift 2; else shift; fi
done
attempt=$(jq -er .attempt "$bundle")
if [[ "$attempt" == current ]]; then
  invocation="$MOCK_CURRENT_INVOCATION"
else
  invocation="https://github.com/dekopon-agents/dekopon-provider-echo/actions/runs/1/attempts/1"
fi
jq -cn --arg invocation "$invocation" '[{
  verificationResult:{signature:{certificate:{runInvocationURI:$invocation}}}
}]'
SH
chmod 0755 "$temporary/mock-bin/curl" "$temporary/mock-bin/gh"
PATH="$temporary/mock-bin:$PATH" \
MOCK_ATTESTATIONS="$temporary/attestations.json" \
MOCK_CURRENT_INVOCATION="https://github.com/dekopon-agents/dekopon-provider-echo/actions/runs/42/attempts/3" \
GITHUB_API_URL=https://example.invalid \
  "$attestation_verifier" "$temporary/echo-provider.wasm" \
    dekopon-agents/dekopon-provider-echo "$(printf 'a%.0s' {1..64})" \
    https://slsa.dev/provenance/v1 \
    dekopon-agents/dekopon-provider-echo/.github/workflows/release.yml \
    refs/tags/v0.1.0 "$(printf 'b%.0s' {1..40})" 42 3 >/dev/null

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
