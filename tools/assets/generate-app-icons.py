#!/usr/bin/env python3
"""Build opaque, deterministic app-icon sizes from the blueprint cube artwork."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
IOS_SET = ROOT / "Sources/iOS/Assets.xcassets/AppIcon.appiconset"
MAC_SET = ROOT / "Sources/macOS/Assets.xcassets/AppIcon.appiconset"
MAC_SIZES = (16, 32, 64, 128, 256, 512, 1024)
BRAND_SETS = (IOS_SET.parent / "BrandIcon.imageset", MAC_SET.parent / "BrandIcon.imageset")
MASTER = ROOT / "docs/brand/3dseen-blueprint-master.png"


def render(size: int) -> Image.Image:
    with Image.open(MASTER) as source:
        return source.convert("RGB").resize((size, size), Image.Resampling.LANCZOS)


def expected_assets() -> dict[Path, Image.Image]:
    assets = {IOS_SET / "icon-1024.png": render(1024)}
    assets.update({MAC_SET / f"icon-{size}.png": render(size) for size in MAC_SIZES})
    assets.update({root / f"brand-{scale}x.png": render(48 * scale) for root in BRAND_SETS for scale in (1, 2, 3)})
    return assets


def write_assets() -> None:
    for path, image in expected_assets().items():
        path.parent.mkdir(parents=True, exist_ok=True)
        image.save(path, format="PNG", optimize=True)
        print(path.relative_to(ROOT))


def validate_contents() -> list[str]:
    errors: list[str] = []
    for asset_set in (IOS_SET, MAC_SET):
        contents = json.loads((asset_set / "Contents.json").read_text())
        for entry in contents["images"]:
            filename = entry.get("filename")
            if filename and not (asset_set / filename).is_file():
                errors.append(f"missing referenced icon: {asset_set / filename}")
    return errors


def check_assets() -> int:
    errors = validate_contents()
    for path, expected in expected_assets().items():
        if not path.is_file():
            errors.append(f"missing icon: {path}")
            continue
        actual = Image.open(path)
        if actual.mode != "RGB":
            errors.append(f"{path}: expected RGB without alpha, got {actual.mode}")
        if actual.size != expected.size:
            errors.append(f"{path}: expected {expected.size}, got {actual.size}")
        elif actual.convert("RGB").tobytes() != expected.tobytes():
            errors.append(f"{path}: pixels differ from deterministic generator")
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print("App icons valid: deterministic blueprint cube RGB assets with no alpha channel.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="validate committed assets without writing")
    arguments = parser.parse_args()
    if arguments.check:
        return check_assets()
    write_assets()
    return check_assets()


if __name__ == "__main__":
    raise SystemExit(main())
