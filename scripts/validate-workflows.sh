#!/usr/bin/env bash
# shellcheck disable=SC2016 # Required workflow snippets are literal strings.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
ci="$root/.github/workflows/ci.yml"
release="$root/.github/workflows/release.yml"
recovery="$root/.github/workflows/recover-v0.1.0.yml"
finalizer="$root/.github/workflows/finalize-v0.1.0.yml"
recovery_helper="$root/scripts/recover-v0.1.0-artifacts.sh"
verifier="$root/scripts/verify-oci-manifest.py"
attestation_verifier="$root/scripts/verify-attestation-anonymously.sh"
[[ -f "$ci" && -f "$release" && -f "$recovery" && -f "$finalizer" && \
   -f "$recovery_helper" && -f "$verifier" && -f "$attestation_verifier" ]] || {
  echo "error: CI, release/recovery workflows, recovery helper, and verifiers are required" >&2
  exit 1
}

python3 - "$ci" "$release" "$recovery" "$finalizer" <<'PY'
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
  '    tags:' \
  '      - "v*"' \
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
if grep -Eq '(^|[^0-9.])v?0[.]1[.]0([^0-9.]|$)' "$release" "$ci"; then
  echo "error: release or CI workflow pins a literal crate version" >&2
  grep -En '(^|[^0-9.])v?0[.]1[.]0([^0-9.]|$)' "$release" "$ci" >&2
  exit 1
fi
if grep -Eq 'CARGO_TARGET_DIR|SCCACHE_DIR|cargo clean|pull_request_target' \
  "$ci" "$release" "$recovery" "$finalizer"; then
  echo "error: workflow violates target/cache/event policy" >&2
  exit 1
fi
draft_job=$(sed -n '/^  draft:/,/^  ghcr:/p' "$release")
if grep -Fq 'id-token: write' <<<"$draft_job"; then
  echo "error: draft job has unnecessary OIDC authority" >&2
  exit 1
fi
finalize_job=$(sed -n '/^  finalize:/,/^  verify_final:/p' "$release")
if ! grep -Fq 'packages: read' <<<"$finalize_job"; then
  echo "error: finalize job cannot revalidate package cardinality" >&2
  exit 1
fi

for required in \
  'workflow_dispatch:' \
  'recover-v0.1.0-from-tag-ci-32816234695' \
  'SOURCE_CI_RUN_ID: "32816234695"' \
  'SOURCE_SHA: 64293b0d2b37a864b7129286064a23fee24b163c' \
  'SOURCE_TAG_OBJECT: 2914235ba1629663b4b88aa20a75f47f851e001c' \
  'EXPECTED_SHA: c15e88cf50726e8a80d1f73f8167563242d59ea80c1af026014e30054ac786b1' \
  './scripts/recover-v0.1.0-artifacts.sh "$RUNNER_TEMP/tagged"' \
  '$GITHUB_REPOSITORY/.github/workflows/recover-v0.1.0.yml' \
  'org.opencontainers.image.revision=$SOURCE_SHA' \
  'cargo +"$PROVIDER_RUST_TOOLCHAIN" install wasm-tools' \
  'Attest both exact recovered release files' \
  'Attest exact tag-source CycloneDX SBOM predicate for the component' \
  '/orgs/dekopon-agents/packages/container/provider-echo'; do
  grep -Fq "$required" "$recovery" || {
    echo "error: recovery workflow omits pinned interlock: $required" >&2
    exit 1
  }
done
for required in \
  'component_artifact_id=9551915476' \
  'component_archive_sha=30678952f3abc4a778e301f978c8130100004caff5ff38d0bc46495c12d72e61' \
  'component_sha=c15e88cf50726e8a80d1f73f8167563242d59ea80c1af026014e30054ac786b1' \
  'failed_release_run_id=32816234729'; do
  grep -Fq "$required" "$recovery_helper" || {
    echo "error: recovery helper omits pinned source fact: $required" >&2
    exit 1
  }
done
if grep -Eq 'cargo (build|test|check)|build-component[.]sh|reproducible-build[.]sh' "$recovery"; then
  echo "error: recovery workflow must not rebuild the component" >&2
  exit 1
fi
for required in \
  'workflow_dispatch:' \
  'finalize-v0.1.0-residual-from-run-32822577381' \
  'ATTEST_RUN_ID: "32822577381"' \
  'PRIOR_RELEASE_ID: "376223263"' \
  'PRIOR_WASM_ASSET_ID: "528836226"' \
  'PRIOR_MANIFEST_DIGEST: sha256:a59cd8871e39213a5333bc1141dda7a8941cae1771e4aab04c7a9612267d3833'; do
  if ! grep -Fq "$required" "$finalizer"; then
    echo "error: finalizer omits pinned residual interlock: $required" >&2
    exit 1
  fi
done
if grep -Eq 'packages: write|id-token: write|attestations: write' "$finalizer"; then
  echo "error: finalizer must not mutate package state or create replacement attestations" >&2
  exit 1
fi

python3 - "$release" "$recovery" "$finalizer" <<'PY'
import pathlib
import sys
text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
recovery = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8")
finalizer = pathlib.Path(sys.argv[3]).read_text(encoding="utf-8")
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
if text.count('gh release create "$GITHUB_REF_NAME"') != 1:
    raise SystemExit("error: draft creation cardinality drifted")
if text.count('"$RUNNER_TEMP/oras-bin" push "$ref"') != 1:
    raise SystemExit("error: OCI push cardinality drifted")
if text.count("echo-provider.wasm:application/wasm") != 1:
    raise SystemExit("error: OCI layer cardinality drifted")
if text.count("actions/attest-build-provenance@") != 1 or text.count("actions/attest@") != 1:
    raise SystemExit("error: provenance/SBOM attestation cardinality drifted")
if text.count("# This PATCH is the release transaction") != 1:
    raise SystemExit("error: final release transaction cardinality drifted")
if recovery.count("actions/attest-build-provenance@") != 1 or recovery.count("actions/attest@") != 1:
    raise SystemExit("error: recovery attestation cardinality drifted")
if recovery.count('"$RUNNER_TEMP/oras-bin" push "$ref"') != 1:
    raise SystemExit("error: recovery OCI push cardinality drifted")
if recovery.count("gh release create v0.1.0") != 1:
    raise SystemExit("error: recovery draft creation cardinality drifted")
if recovery.count("# This PATCH is the release transaction") != 1:
    raise SystemExit("error: recovery final transaction cardinality drifted")
if finalizer.count("# This PATCH is the finalizer's sole mutation") != 1:
    raise SystemExit("error: residual finalizer PATCH cardinality drifted")
if finalizer.count('gh api --method PATCH "repos/$GITHUB_REPOSITORY/releases/$PRIOR_RELEASE_ID"') != 1:
    raise SystemExit("error: residual release finalization cardinality drifted")
if "oras-bin\" push" in finalizer or "gh release create" in finalizer:
    raise SystemExit("error: residual finalizer must not create replacement OCI/release state")
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
  1:1 "$(printf 'a%.0s' {1..40})" 0.1.0
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
  1:1 "$(printf 'a%.0s' {1..40})" 0.1.0 >/dev/null 2>&1; then
  echo 'error: OCI verifier accepted a path-bearing layer title' >&2
  exit 1
fi

printf 'workflow pins, least-privilege transaction interlocks, attestations, and OCI verifier passed\n'
