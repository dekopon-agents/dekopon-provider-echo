# Third-party notices

`dekopon-echo-provider` project source is licensed under **MIT OR Apache-2.0**. The release
component statically links permissively licensed Rust dependencies. `Cargo.lock is the authority`
for every exact transitive version and crates.io checksum; `cargo deny check licenses` is the
machine-enforced license inventory.

The release component embeds this file together with `LICENSE-MIT` and `LICENSE-APACHE` in its
`dekopon.third-party-notices` WebAssembly custom section. Release documentation reproduces that
complete byte-exact distribution license bundle without adding a third release asset.

## Dekopon component interface

The component uses `dekopon-provider-sdk 0.11.1`, `dekopon-core 0.11.1`, and
`dekopon-capability 0.11.1`, all licensed MIT OR Apache-2.0. Generated bindings use
`wit-bindgen 0.44.0` and the WebAssembly/WIT `0.236.1` toolchain crates, licensed under
Apache-2.0 WITH LLVM-exception, Apache-2.0, and/or MIT. The checked component has zero imports.

`dekopon-provider-sdk-testkit 0.11.1`, Tokio, Wasmtime, HTTP-host, and storage-host packages occur
only in native development/test resolution. They are not linked into `echo-provider.wasm`; the
component-target dependency-tree and decoded-WIT gates enforce that distinction.

## Serialization and supporting crates

The component directly pins `serde_json 1.0.151`. Its component graph also includes
`serde 1.0.229`, `foldhash 0.1.5`, `unicode-ident 1.0.24`, and other exact transitive packages.
These are permissively licensed under the allowlist in `deny.toml`, including MIT, Apache-2.0,
Unicode-3.0, Unlicense, and Zlib. Complete project MIT and Apache-2.0 texts are adjacent source
files and are embedded verbatim in every release component.

## Reproducing the inventory

Package-specific source and license files are available from the exact crates.io packages and
checksums identified by `Cargo.lock`:

```console
cargo deny list
cargo deny check licenses advisories bans sources
cargo tree --locked --target wasm32-unknown-unknown --edges normal,build
./scripts/check-third-party-notices.sh Cargo.lock THIRD_PARTY_NOTICES.md
./scripts/embed-license-bundle.py verify echo-provider.wasm .
```
