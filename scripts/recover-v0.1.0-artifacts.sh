#!/usr/bin/env bash
# Recover only the immutable component artifact produced by tag CI run 32816234695.
# The helper never rebuilds or substitutes provider bytes.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
destination=${1:?usage: recover-v0.1.0-artifacts.sh DESTINATION}

repo=dekopon-agents/dekopon-provider-echo
source_sha=64293b0d2b37a864b7129286064a23fee24b163c
tag=v0.1.0
tag_object=2914235ba1629663b4b88aa20a75f47f851e001c
ci_run_id=32816234695
ci_workflow_id=341808399
ci_source_job_id=97704989915
ci_repro_job_id=97706291816
ci_component_job_id=97706291830
failed_release_run_id=32816234729
release_workflow_id=341808400
release_build_job_id=97704990314
release_cleanup_job_id=97708884217
component_artifact_id=9551915476
component_archive_sha=30678952f3abc4a778e301f978c8130100004caff5ff38d0bc46495c12d72e61
component_archive_size=64465
component_sha=c15e88cf50726e8a80d1f73f8167563242d59ea80c1af026014e30054ac786b1
checksum_sha=a395d01420d7ef11cec85e4408dac1f5c1a7b0b1d2ebb8755b44f9e8cba7ad2a

: "${GH_TOKEN:?GH_TOKEN is required to read the captured Actions artifact}"
[[ "${GITHUB_REPOSITORY:-$repo}" == "$repo" ]]
for command in gh git jq shasum unzip; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "error: $command is required" >&2
    exit 1
  }
done

ci_run=$(gh api "repos/$repo/actions/runs/$ci_run_id")
jq -e \
  --arg repo "$repo" \
  --arg sha "$source_sha" \
  --argjson id "$ci_run_id" \
  --argjson workflow_id "$ci_workflow_id" '
    .id == $id and .workflow_id == $workflow_id and
    .name == "CI" and .path == ".github/workflows/ci.yml" and
    .event == "push" and .status == "completed" and .conclusion == "success" and
    .head_branch == "v0.1.0" and .head_sha == $sha and .run_attempt == 1 and
    .repository.full_name == $repo
  ' <<<"$ci_run" >/dev/null
ci_jobs=$(gh api "repos/$repo/actions/runs/$ci_run_id/jobs?filter=all&per_page=100")
jq -e \
  --argjson source "$ci_source_job_id" \
  --argjson repro "$ci_repro_job_id" \
  --argjson component "$ci_component_job_id" '
    .total_count == 3 and
    ([.jobs[] | {id, name, conclusion}] | sort_by(.id)) == ([
      {id: $source, name: "source, native tests, MSRV, and policy", conclusion: "success"},
      {id: $repro, name: "two clean pinned builds are byte-identical", conclusion: "success"},
      {id: $component, name: "component, direct host, testkit, and resources", conclusion: "success"}
    ] | sort_by(.id))
  ' <<<"$ci_jobs" >/dev/null

release_run=$(gh api "repos/$repo/actions/runs/$failed_release_run_id")
jq -e \
  --arg repo "$repo" \
  --arg sha "$source_sha" \
  --argjson id "$failed_release_run_id" \
  --argjson workflow_id "$release_workflow_id" '
    .id == $id and .workflow_id == $workflow_id and
    .name == "Immutable v0.1.0 release" and .path == ".github/workflows/release.yml" and
    .event == "push" and .status == "completed" and .conclusion == "failure" and
    .head_branch == "v0.1.0" and .head_sha == $sha and .run_attempt == 1 and
    .repository.full_name == $repo
  ' <<<"$release_run" >/dev/null
release_jobs=$(gh api \
  "repos/$repo/actions/runs/$failed_release_run_id/jobs?filter=all&per_page=100")
jq -e \
  --arg cleanup_name "remove only this failed run's proven release and sole final manifest" \
  --argjson build "$release_build_job_id" \
  --argjson cleanup "$release_cleanup_job_id" '
    ([.jobs[] | select(.id == $build)][0]) as $build_job |
    ([.jobs[] | select(.id == $cleanup)][0]) as $cleanup_job |
    (.total_count == 7) and
    $build_job.name == "verify immutable source and exact component" and
    $build_job.conclusion == "failure" and
    ([$build_job.steps[] | select(
      .name == "Run every source, component, host, testkit, resource, and license gate"
    ) | .conclusion] == ["failure"]) and
    $cleanup_job.name == $cleanup_name and
    $cleanup_job.conclusion == "success" and
    ([.jobs[] | select(
      .id != $build and .id != $cleanup
    ) | .conclusion] | all(. == "skipped"))
  ' <<<"$release_jobs" >/dev/null

artifacts=$(gh api "repos/$repo/actions/runs/$ci_run_id/artifacts?per_page=100")
jq -e \
  --arg digest "sha256:$component_archive_sha" \
  --arg sha "$source_sha" \
  --argjson artifact_id "$component_artifact_id" \
  --argjson artifact_size "$component_archive_size" \
  --argjson run_id "$ci_run_id" '
    .total_count == 1 and (.artifacts | length) == 1 and
    .artifacts[0].id == $artifact_id and
    .artifacts[0].name == "echo-provider-component" and
    .artifacts[0].size_in_bytes == $artifact_size and
    .artifacts[0].expired == false and
    .artifacts[0].digest == $digest and
    .artifacts[0].workflow_run.id == $run_id and
    .artifacts[0].workflow_run.head_branch == "v0.1.0" and
    .artifacts[0].workflow_run.head_sha == $sha
  ' <<<"$artifacts" >/dev/null

git -C "$root" fetch --force origin "refs/tags/$tag:refs/tags/$tag"
[[ "$(git -C "$root" cat-file -t "refs/tags/$tag")" == tag ]]
[[ "$(git -C "$root" rev-parse "refs/tags/$tag")" == "$tag_object" ]]
[[ "$(git -C "$root" rev-parse "refs/tags/$tag^{}")" == "$source_sha" ]]
git -C "$root" merge-base --is-ancestor "$source_sha" HEAD

rm -rf "$destination"
mkdir -p "$destination/dist" "$destination/archive"
gh api "repos/$repo/actions/artifacts/$component_artifact_id/zip" \
  >"$destination/archive/echo-provider-component.zip"
[[ "$(shasum -a 256 "$destination/archive/echo-provider-component.zip" |
  awk '{print $1}')" == "$component_archive_sha" ]]
unzip -q "$destination/archive/echo-provider-component.zip" -d "$destination/dist"
files=$(cd "$destination/dist" && find . -type f -print | LC_ALL=C sort)
[[ "$files" == $'./echo-provider.wasm\n./echo-provider.wasm.sha256' ]]
[[ "$(shasum -a 256 "$destination/dist/echo-provider.wasm" | awk '{print $1}')" == \
   "$component_sha" ]]
[[ "$(shasum -a 256 "$destination/dist/echo-provider.wasm.sha256" |
  awk '{print $1}')" == "$checksum_sha" ]]
[[ "$(cat "$destination/dist/echo-provider.wasm.sha256")" == \
   "$component_sha  echo-provider.wasm" ]]
(cd "$destination/dist" && shasum -a 256 -c echo-provider.wasm.sha256)
[[ "$(wc -c <"$destination/dist/echo-provider.wasm" | tr -d '[:space:]')" == 150036 ]]

printf 'verified immutable tag-CI artifact: run=%s component=sha256:%s\n' \
  "$ci_run_id" "$component_sha"
