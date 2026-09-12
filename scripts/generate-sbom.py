#!/usr/bin/env python3
"""Generate deterministic CycloneDX 1.5 for the shipped wasm32 dependency graph."""

from __future__ import annotations

import json
import pathlib
import subprocess
import sys


def fail(message: str) -> None:
    raise SystemExit(f"error: {message}")


def main() -> None:
    if len(sys.argv) != 2:
        fail("usage: generate-sbom.py OUTPUT.json")
    root = pathlib.Path(__file__).resolve().parent.parent
    metadata = json.loads(subprocess.check_output([
        "cargo", "metadata", "--locked", "--format-version", "1",
        "--filter-platform", "wasm32-unknown-unknown", "--manifest-path", str(root / "Cargo.toml"),
    ]))
    packages = {package["id"]: package for package in metadata["packages"]}
    nodes = {node["id"]: node for node in metadata["resolve"]["nodes"]}
    root_id = metadata["resolve"]["root"]
    if root_id is None:
        fail("metadata has no root package")

    reachable: set[str] = set()
    pending = [root_id]
    while pending:
        package_id = pending.pop()
        if package_id in reachable:
            continue
        reachable.add(package_id)
        for dependency in nodes[package_id]["deps"]:
            # Dev-only packages are assurance inputs, not shipped component code.
            if any(kind["kind"] != "dev" for kind in dependency["dep_kinds"]):
                pending.append(dependency["pkg"])

    components = []
    for package_id in sorted(reachable - {root_id}, key=lambda item: (packages[item]["name"], packages[item]["version"])):
        package = packages[package_id]
        source = package.get("source") or ""
        if not source.startswith("registry+"):
            fail(f"non-registry shipped dependency: {package['name']} {source}")
        checksum = package.get("checksum")
        component = {
            "type": "library",
            "bom-ref": f"pkg:cargo/{package['name']}@{package['version']}",
            "name": package["name"],
            "version": package["version"],
            "purl": f"pkg:cargo/{package['name']}@{package['version']}",
        }
        if checksum:
            component["hashes"] = [{"alg": "SHA-256", "content": checksum}]
        if package.get("license"):
            component["licenses"] = [{"expression": package["license"]}]
        components.append(component)

    document = {
        "bomFormat": "CycloneDX",
        "specVersion": "1.5",
        "version": 1,
        "metadata": {
            "component": {
                "type": "application",
                "bom-ref": "pkg:cargo/dekopon-echo-provider@0.2.0",
                "name": "dekopon-echo-provider",
                "version": "0.2.0",
                "purl": "pkg:cargo/dekopon-echo-provider@0.2.0",
            },
            "properties": [
                {"name": "dekopon.target", "value": "wasm32-unknown-unknown"},
                {"name": "dekopon.sdk", "value": "0.13.0"},
            ],
        },
        "components": components,
    }
    names = {(item["name"], item["version"]) for item in components}
    if ("dekopon-provider-sdk", "0.13.0") not in names or ("serde_json", "1.0.151") not in names:
        fail("SBOM omits exact direct shipped dependencies")
    for forbidden in ("dekopon-provider-sdk-testkit", "tokio", "dekopon-provider-http", "dekopon-provider-storage"):
        if any(item["name"] == forbidden for item in components):
            fail(f"SBOM includes non-shipped dependency {forbidden}")

    output = pathlib.Path(sys.argv[1])
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", encoding="utf-8", newline="\n") as handle:
        handle.write(json.dumps(document, indent=2, sort_keys=True) + "\n")
    print(f"generated deterministic CycloneDX SBOM with {len(components)} components: {output}")


if __name__ == "__main__":
    main()
