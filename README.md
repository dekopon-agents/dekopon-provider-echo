# Dekopon echo provider

A standalone, import-free WebAssembly component with five Low-risk, read-only capabilities:

| Capability | Result |
|---|---|
| `echo.echo` | Returns the supplied JSON value unchanged. Dekopon hosts require object input. |
| `echo.reverse` | Reverses Unicode scalar values in `message`. |
| `echo.upcase` | Applies Rust Unicode uppercase mapping. |
| `echo.downcase` | Applies Rust Unicode lowercase mapping. |
| `echo.ransom-case` | Alternates alphabetic scalars lower/upper, preserving punctuation. |

Transformation input is exactly `{"message":"..."}`. Missing, non-string, or additional fields
return `invalid-input`. Reversal is by Unicode scalar, not grapheme cluster; case operations are
Unicode mappings and may expand a scalar (`Straße` becomes `STRASSE`). Ransom case starts lowercase
and punctuation does not advance alternation.

The component has zero imports and no filesystem, network, HTTP, storage, subprocess, environment,
clock, random, or WASI authority. It exports only `describe` and `invoke`; `commandWords` is empty.
The broker—not this component—owns authentication, authorization, and host resource ceilings.

## Run it

Obtain `echo-provider.wasm` and `echo-provider.wasm.sha256` from the release for the version you
want. The byte-identical Wasm is the sole layer at `ghcr.io/dekopon-agents/provider-echo:<version>`;
no `latest` tag is published.

```console
sha256sum --check echo-provider.wasm.sha256
oras pull ghcr.io/dekopon-agents/provider-echo:0.2.0
```

Point a Dekopon broker at the component to serve it. To drive it directly — the same Wasmtime host
and the same ceilings a deployment runs, with policy replaced by an allow-all gate — use
`dekopon-provider-sdk-testkit`'s `FakeBroker`, as [`tests/broker.rs`](tests/broker.rs) does.

Host limits in the release tests are 1 MiB serialized input/output, 64 MiB linear memory,
50,000,000 fuel, and 30 seconds. `echo.echo` intentionally has no separate decoded-data limit;
production hosts must enforce the documented wire/runtime limits.

## Build and validate

Generated Wasm, checksums, `dist/`, and `target/` are ignored and must never be committed. Builds
use the checkout's ordinary `target/` and global Cargo/sccache configuration.

```console
rustup toolchain install 1.98.1 --profile minimal --component clippy --component rustfmt
rustup target add wasm32-unknown-unknown --toolchain 1.98.1
cargo +1.98.1 install wasm-tools --version 1.259.0 --locked
cargo +1.98.1 install wasmtime-cli --version 48.0.2 --locked
./scripts/validate.sh
./scripts/reproducible-build.sh
```

`validate.sh` covers formatting, warnings-denied clippy, native tests, MSRV and Wasm checks,
registry/license/advisory policy, exact copied WIT, zero imports, raw component ABI, FakeBroker
concurrency, resource ceilings, and exact two-file release layout.
See [`PROVENANCE.md`](PROVENANCE.md), [`SECURITY.md`](SECURITY.md), and
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

## License

Project-authored source is available under MIT OR Apache-2.0. The component embeds the complete
distribution-notice bundle in `dekopon.third-party-notices`.
