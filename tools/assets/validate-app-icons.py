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
    if not (ROOT / "docs/brand/3dseen-cube.svg").is_file():
        errors.append("missing vector brand companion: docs/brand/3dseen-cube.svg")
    icon = ROOT / "Sources/Shared/DesignSystem/3DSeenIcon.icon"
    try:
        composition = json.loads((icon / "icon.json").read_text())
        if composition["fill-specializations"][0]["value"]["solid"] != "extended-srgb:0.11765,0.34510,0.86275,1.00000":
            errors.append("Icon Composer background must use blueprint blue")
        dark_fill = next((entry["value"] for entry in composition["fill-specializations"]
                          if entry.get("appearance") == "dark"), None)
        if dark_fill != composition["fill-specializations"][0]["value"]:
            errors.append("Icon Composer dark appearance must preserve blueprint blue")
        layers = [layer for group in composition["groups"] for layer in group["layers"]]
        if len(layers) != 1 or layers[0]["image-name"] != "3dseen-cube.svg":
            errors.append("Icon Composer must contain the approved cube layer")
        vector = (icon / "Assets/3dseen-cube.svg").read_text()
        if vector != (ROOT / "docs/brand/3dseen-cube.svg").read_text() or 'stroke="#FFFFFF"' not in vector:
            errors.append("Icon Composer cube must match the white vector mark")
        if (ROOT / "project.yml").read_text().count("ASSETCATALOG_COMPILER_APPICON_NAME: 3DSeenIcon") != 2:
            errors.append("Both app targets must use the Icon Composer icon")
    except (OSError, KeyError, json.JSONDecodeError) as error:
        errors.append(f"Invalid Icon Composer document: {error}")
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print("App icons valid: referenced dimensions, opaque RGB catalogs, and shared Icon Composer cube with blue default/dark backgrounds.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
