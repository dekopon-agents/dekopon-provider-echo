# Source provenance

This repository extracts the Dekopon echo example from
`dekopon-agents/dekopon` commit
[`62d2185f9ec6fee61f2689197b274a9b4947659f`](https://github.com/dekopon-agents/dekopon/commit/62d2185f9ec6fee61f2689197b274a9b4947659f).

- Behavior source: `examples/providers/echo/src/lib.rs`, Git blob
  `c5dd51f580cf3e11e4a767ba48f181057d08c432` (last behavior change
  `c66a5c4923f619390f20de1341af2378a0b61c75`).
- Provider WIT: `crates/dekopon-provider-sdk/wit/provider.wit` at tag `v0.13.0`
  (`86f6fd7ee3d858d49e90162d96c930aefad59a78`), Git blob
  `c85aa512bda0716242e9b6520026f906b3e09d5d` — the `dekopon:provider@0.3.0` package, copied
  verbatim. Before v0.2.0 this was the `@0.2.0` package, blob
  `24541c0bf2236295eff22b7000fc250a676bbc6a`.
- Compatibility baseline: registry-only `dekopon-provider-sdk = "=0.13.0"`.

The five capability implementations, manifest values, errors, and Unicode scalar/case semantics are
preserved. Standalone changes are packaging and assurance changes: exact crates.io pins, expanded
independent tests, deterministic build/release scripts, embedded distribution notices, and
caller-owned WIT. The source example's unused storage-facade feature assertion was intentionally
removed because it tests a core SDK/storage property rather than echo behavior; this component
still proves zero imports directly by decoding every build.
