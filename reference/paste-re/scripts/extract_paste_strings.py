#!/usr/bin/env python3
"""Extract Paste's localizable strings and its MCP tool descriptions from a local install.

Everything here reads files that already exist on disk; nothing is launched and no
network access happens.

What it produces, next to each other in --out:
  paste-<lang>.json   one flat key -> value map per .lproj in PasteLocalization.bundle
  mcp-strings.txt     printable strings of the paste-mcp-stdio helper binary
  paste-strings.txt   printable strings of the main Paste binary's thin arm64 slice

Paste's own UI copy is the ground truth for behaviour that the model files only hint
at (for example general.action.unpin and the pinboard wording), so keep the JSON
snapshots rather than just grepping them once.

The main binary is universal. `strings` on the fat file yields a different (and much
larger) set than the arm64 slice, so thin first: the archived paste-strings.txt was
produced from the arm64 slice, and only that reproduces its digest.

Usage:
    python3 extract_paste_strings.py --app /Applications/Paste.app --out ./artifacts
"""
import argparse
import json
import plistlib
import subprocess
import tempfile
from pathlib import Path


def load_lproj(lproj: Path) -> dict:
    strings = lproj / "Localizable.strings"
    if not strings.exists():
        return {}
    raw = strings.read_bytes()
    # Paste ships these as UTF-16 XML plists whose declaration still says UTF-8, so
    # decode explicitly and hand plistlib bytes it can parse.
    if raw.startswith(b"\xff\xfe") or raw.startswith(b"\xfe\xff"):
        raw = raw.decode("utf-16").encode("utf-8")
    elif raw[:2] in (b"<\x00", b"\x00<"):
        raw = raw.decode("utf-16-le" if raw[:2] == b"<\x00" else "utf-16-be").encode("utf-8")
    data = plistlib.loads(raw)
    return {str(key): str(value) for key, value in data.items()}


def dump_strings(binary: Path, destination: Path) -> None:
    result = subprocess.run(
        ["strings", "-a", str(binary)],
        check=True,
        capture_output=True,
        text=True,
        errors="replace",
    )
    destination.write_text(result.stdout, encoding="utf-8")


def thin_arm64(binary: Path, directory: Path) -> Path:
    """Return an arm64-only copy so strings matches the archived snapshot."""
    thinned = directory / (binary.name + "-arm64")
    subprocess.run(
        ["lipo", "-thin", "arm64", str(binary), "-output", str(thinned)],
        check=True,
        capture_output=True,
    )
    return thinned


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", default="/Applications/Paste.app")
    parser.add_argument("--out", default="./artifacts")
    parser.add_argument("--languages", nargs="*", default=["en", "zh-Hans"])
    args = parser.parse_args()

    app = Path(args.app)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    localization = (
        app
        / "Contents/Resources/PastePackages_PasteLocalization.bundle/Contents/Resources"
    )
    for language in args.languages:
        table = load_lproj(localization / f"{language}.lproj")
        target = out / f"paste-{language}.json"
        target.write_text(
            json.dumps(table, ensure_ascii=False, indent=1, sort_keys=True),
            encoding="utf-8",
        )
        print(f"{language}: {len(table)} keys -> {target}")

    with tempfile.TemporaryDirectory(prefix="paste-strings-") as scratch:
        dump_strings(
            thin_arm64(app / "Contents/MacOS/Paste", Path(scratch)),
            out / "paste-strings.txt",
        )
    dump_strings(app / "Contents/MacOS/paste-mcp-stdio", out / "mcp-strings.txt")
    print("strings extracted")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
