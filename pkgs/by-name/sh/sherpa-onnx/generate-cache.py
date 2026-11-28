#!/usr/bin/env python3

"""Regenerate the FetchContent "cache" list in package.nix.

Upstream pins every CMake dependency in cmake/<dep>.cmake:

    set(<dep>_URL  "https://...")
    set(<dep>_HASH "SHA256=<hex>")

and hard-codes the archive file name it looks for under
.../Downloads/<file>. All three move with a release, so the list is
generated from the source tarball being packaged rather than maintained
by hand.

Dependencies that nixpkgs provides (passed to CMake as
FETCHCONTENT_SOURCE_DIR_* or <dep>_SOURCE_DIR) and the dependencies of
features this package disables are skipped.
"""

import argparse
import base64
import re
import sys
from pathlib import Path

BEGIN_MARKER = "# BEGIN generated cache"
END_MARKER = "# END generated cache"

URL_RE = re.compile(
    r'^\s*set\(\s*([A-Za-z0-9_.-]+)_URL\s+"(https?://[^"]+)"\s*\)',
    re.MULTILINE,
)
HASH_RE = re.compile(
    r'^\s*set\(\s*([A-Za-z0-9_.-]+)_HASH\s+"SHA256=([0-9a-f]{64})"\s*\)',
    re.MULTILINE,
)
FILENAME_RE = re.compile(r'/Downloads/(\S+?)"?\s*$', re.MULTILINE)
SOURCE_DIR_RE = re.compile(r'"([A-Za-z0-9_]*SOURCE_DIR[A-Za-z0-9_]*)"')

# sherpa-onnx is built with SHERPA_ONNX_ENABLE_PORTAUDIO=false.
DISABLED_DEPENDENCIES = {"portaudio"}


def normalize(name: str) -> str:
    """Compare dependency names the way upstream spells them inconsistently."""
    return re.sub(r"[-_]", "", name).lower()


def to_sri(hex_digest: str) -> str:
    return "sha256-" + base64.b64encode(bytes.fromhex(hex_digest)).decode("ascii")


def dependency_name(flag: str) -> str:
    """Map a CMake variable nixpkgs fills in to the dependency it names.

    The build passes them as either FETCHCONTENT_SOURCE_DIR_JSON or
    onnxruntime_SOURCE_DIR.
    """
    if "SOURCE_DIR_" in flag:
        return flag.rsplit("SOURCE_DIR_", 1)[1]
    return flag.split("_SOURCE_DIR", 1)[0]


def skipped_dependencies(package: Path) -> set[str]:
    """Names of dependencies the build takes from nixpkgs or does not use."""
    skipped = {normalize(name) for name in DISABLED_DEPENDENCIES}
    for flag in SOURCE_DIR_RE.findall(package.read_text()):
        skipped.add(normalize(dependency_name(flag)))
    return skipped


def collect(cmake_dir: Path, skipped: set[str]) -> dict[str, tuple[str, str]]:
    dependencies = {}

    for path in sorted(cmake_dir.glob("*.cmake")):
        # These download prebuilt ONNX Runtime binaries; nixpkgs' onnxruntime
        # is passed in as onnxruntime_SOURCE_DIR instead.
        if path.name.startswith("onnxruntime"):
            continue

        text = path.read_text()
        hashes = dict(HASH_RE.findall(text))
        downloads = [
            (match.start(), match.group(1)) for match in FILENAME_RE.finditer(text)
        ]

        for match in URL_RE.finditer(text):
            name, url = match.group(1), match.group(2)
            if normalize(name) in skipped:
                continue
            filename = next((f for pos, f in downloads if pos > match.end()), None)
            if name not in hashes or filename is None:
                sys.exit(
                    f"{path.name}: cannot pair {name}_URL with a SHA256 and a file name"
                )
            dependencies[filename] = (url, hashes[name])

    return dependencies


def render(dependencies: dict[str, tuple[str, str]]) -> list[str]:
    lines = ["  cache = ["]
    for filename in sorted(dependencies):
        url, digest = dependencies[filename]
        lines += [
            "    {",
            f'      name = "{filename}";',
            "      src = fetchurl {",
            f'        url = "{url}";',
            f'        hash = "{to_sri(digest)}";',
            "      };",
            "    }",
        ]
    lines.append("  ];")
    return lines


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package", required=True, type=Path)
    parser.add_argument("--cmake-dir", required=True, type=Path)
    args = parser.parse_args()

    dependencies = collect(args.cmake_dir, skipped_dependencies(args.package))
    if not dependencies:
        sys.exit("no FetchContent dependencies found; did upstream change its layout?")

    lines = args.package.read_text().splitlines()
    begin = next(
        (i for i, line in enumerate(lines) if line.strip() == BEGIN_MARKER), None
    )
    end = next(
        (
            i
            for i, line in enumerate(lines)
            if line.strip() == END_MARKER and begin is not None and i > begin
        ),
        None,
    )
    if begin is None or end is None:
        sys.exit(f"{args.package}: missing '{BEGIN_MARKER}' / '{END_MARKER}'")

    args.package.write_text(
        "\n".join(lines[: begin + 1] + render(dependencies) + lines[end:]) + "\n"
    )
    print(f"{args.package}: wrote {len(dependencies)} FetchContent dependencies")


if __name__ == "__main__":
    main()
