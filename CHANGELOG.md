# Changelog

## 0.2.0 - Unreleased

- Move to the Dekopon 0.13.0 provider SDK and testkit, and to the `dekopon:provider@0.3.0` WIT
  package copied verbatim from that release. The component still exports only `describe` and
  `invoke`; the new `provider-cli` world is declared by the package and unused here.
- Drop the `idempotency` capability classification, deleted end to end in Dekopon 0.13.0. The
  manifest `describe` emits no longer carries the field, so this rebuild is what keeps the
  component loading once the host's compatibility decoder is removed.
- Move the pinned toolchain to Rust 1.98.1 (MSRV and build), wasm-tools 1.259.0, and
  Wasmtime 48.0.2.
- Replace the `dekopon-run` gates with the `FakeBroker` harness. `dekopon-run` is retired and stops
  at 0.11.1, which would have pinned every host check to a release that requires the deleted
  `idempotency` field. `tests/broker.rs` now covers the direct-host, 1 MiB wire-input, 1 MiB
  provider-output, and 50M-fuel-headroom gates that `scripts/test-direct-host.sh` and
  `scripts/test-resource-limits.sh` used to cover; both scripts and `scripts/lib-component.sh` are
  deleted.
- Generalize the release workflow from the one-shot v0.1.0 transaction to any `v*` tag: the version
  comes from `cargo metadata`, the GHCR and release cardinality checks are scoped to the version
  being published rather than to the whole package, and `scripts/crate-version.sh` is the single
  place the version is read from.

## 0.1.0 - Unreleased

- Extract the five import-free echo capabilities from Dekopon core while preserving manifest,
  Unicode, validation, and error behavior.
- Pin the Dekopon 0.11.1 SDK/testkit to crates.io and own the exact provider WIT.
- Add native, raw component, direct-host, broker-testkit, resource, reproducibility, provenance,
  license, source-policy, release-layout, OCI-layout, and workflow validation gates.
- Add an immutable Actions-owned two-asset GitHub/GHCR release transaction for v0.1.0.
