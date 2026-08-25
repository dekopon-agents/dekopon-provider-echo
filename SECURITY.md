# Security policy

## Reporting

Report vulnerabilities privately through GitHub's security-advisory flow for
`dekopon-agents/dekopon-provider-echo`. Do not include sensitive invocation content in public
issues. Published v0.1.0 bytes are immutable; fixes require a new version.

## Authority and data boundary

All capabilities are deterministic computation over caller-provided JSON. Handwritten provider
code performs no filesystem, network, HTTP, storage, subprocess, environment, clock, random, or
WASI operation. Decoded component WIT must have zero imports and exactly `describe` and `invoke`.
The broker separately authenticates callers and authorizes each capability.

`echo.echo` returns its semantic JSON input unchanged. The direct trait accepts any JSON value,
while Dekopon hosts require capability input to be an object. Transformations accept exactly one
string field named `message`. Rust Unicode scalar iteration and default Unicode case mapping are
deliberate compatibility behavior, not locale-aware or grapheme-aware text processing.

The SDK parses the complete WIT `input-json` into `serde_json::Value` before provider invocation.
Malformed/trailing JSON is rejected there. Duplicate object names cannot be detected afterward;
Serde retains the last value. Producers must emit unique names.

Deployments must admit only reviewed component digests and enforce serialized input/output,
linear-memory, fuel, and deadline limits. The tested release profile uses 1 MiB input/output,
64 MiB memory, 50,000,000 fuel, and 30 seconds. Compilation caches must be owner-writable only.

## Supply chain and release

`Cargo.lock` fixes registry versions/checksums; direct SDK, Serde JSON, testkit, and Tokio versions
are exact. `cargo-deny` denies git/unknown registries, disallowed licenses, advisories, yanked
crates, and wildcard direct dependencies. CI rejects tracked Wasm, decodes exact WIT/imports, runs
native/component/host/resource tests, verifies embedded notices, and compares two clean builds.
Every third-party Action is full-commit-SHA pinned.

The v0.1.0 release workflow accepts only an annotated `v0.1.0` at current `main`, rebuilds and
attests Actions-owned bytes, creates one run-owned draft with exactly two assets, and publishes the
same Wasm as one `application/wasm` layer at only
`ghcr.io/dekopon-agents/provider-echo:0.1.0`. It anonymously verifies bytes and provenance before
finalizing the captured release as the last mutation. Failure cleanup uses captured immutable
release/package identities and refuses to delete anything it cannot prove belongs to the run.
