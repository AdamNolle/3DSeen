#!/usr/bin/env python3
"""Validate app-icon catalogs with the Python standard library only."""

from __future__ import annotations

import json
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SETS = (
    ROOT / "Sources/iOS/Assets.xcassets/AppIcon.appiconset",
    ROOT / "Sources/macOS/Assets.xcassets/AppIcon.appiconset",
)
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def png_metadata(path: Path) -> tuple[int, int, int, set[bytes]]:
    data = path.read_bytes()
    if not data.startswith(PNG_SIGNATURE):
        raise ValueError("not a PNG")
    offset = len(PNG_SIGNATURE)
    chunks: set[bytes] = set()
    width = height = color_type = -1
    while offset + 12 <= len(data):
        length = struct.unpack(">I", data[offset:offset + 4])[0]
        chunk_type = data[offset + 4:offset + 8]
        payload = data[offset + 8:offset + 8 + length]
        chunks.add(chunk_type)
        if chunk_type == b"IHDR":
            width, height, bit_depth, color_type = struct.unpack(">IIBB", payload[:10])
            if bit_depth != 8:
                raise ValueError(f"expected 8-bit pixels, got {bit_depth}")
        offset += 12 + length
        if chunk_type == b"IEND":
            break
    return width, height, color_type, chunks


def pixels_for(entry: dict[str, str]) -> int:
    logical = float(entry["size"].split("x", maxsplit=1)[0])
    scale = int(entry.get("scale", "1x").removesuffix("x"))
    return round(logical * scale)


def main() -> int:
    errors: list[str] = []
    for asset_set in SETS:
        contents = json.loads((asset_set / "Contents.json").read_text())
        checked: set[str] = set()
        for entry in contents["images"]:
            filename = entry.get("filename")
            if not filename or filename in checked:
                continue
            checked.add(filename)
            path = asset_set / filename
            if not path.is_file():
                errors.append(f"missing referenced icon: {path.relative_to(ROOT)}")
                continue
            try:
                width, height, color_type, chunks = png_metadata(path)
                expected = pixels_for(entry)
                if (width, height) != (expected, expected):
                    errors.append(f"{path.relative_to(ROOT)}: expected {expected}x{expected}, got {width}x{height}")
                if color_type != 2 or b"tRNS" in chunks:
                    errors.append(f"{path.relative_to(ROOT)}: icon must be opaque RGB without alpha")
            except (OSError, ValueError, struct.error) as error:
                errors.append(f"{path.relative_to(ROOT)}: {error}")
    if not (ROOT / "docs/brand/3dseen-tesseract.svg").is_file():
        errors.append("missing vector brand master: docs/brand/3dseen-tesseract.svg")
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print("App icon catalogs valid: referenced dimensions, opaque RGB PNGs, and vector master.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
