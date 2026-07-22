#!/usr/bin/env python3
"""Generate and validate 3DSeen's powder-blue tesseract app icons."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
IOS_SET = ROOT / "Sources/iOS/Assets.xcassets/AppIcon.appiconset"
MAC_SET = ROOT / "Sources/macOS/Assets.xcassets/AppIcon.appiconset"
MAC_SIZES = (16, 32, 64, 128, 256, 512, 1024)
SCALE = 4


def mix(first: tuple[int, int, int], second: tuple[int, int, int], amount: float) -> tuple[int, int, int]:
    return tuple(round(a + (b - a) * amount) for a, b in zip(first, second))


def render(size: int) -> Image.Image:
    canvas = size * SCALE
    image = Image.new("RGB", (canvas, canvas))
    draw = ImageDraw.Draw(image)
    top = (104, 173, 220)
    bottom = (49, 117, 175)
    for y in range(canvas):
        progress = y / max(canvas - 1, 1)
        eased = progress * progress * (3 - 2 * progress)
        draw.line([(0, y), (canvas, y)], fill=mix(top, bottom, eased))
    # A minimal offset-box projection: two equal boxes connected corner-to-corner. The
    # asymmetry reads as dimensional motion instead of a flat tunnel at Home Screen size.
    outer = [(0.235, 0.335), (0.655, 0.335), (0.655, 0.755), (0.235, 0.755)]
    inner = [(0.375, 0.205), (0.795, 0.205), (0.795, 0.625), (0.375, 0.625)]
    outer_points = [(round(x * canvas), round(y * canvas)) for x, y in outer]
    inner_points = [(round(x * canvas), round(y * canvas)) for x, y in inner]
    cube_edges = [(0, 1), (1, 2), (2, 3), (3, 0)]
    connector_edges = [(index, index) for index in range(4)]

    def line(points: list[tuple[int, int]], edge: tuple[int, int], fill: tuple[int, int, int], width: int,
             offset: tuple[int, int] = (0, 0)) -> None:
        first = points[edge[0]]
        second = points[edge[1]]
        draw.line(
            [(first[0] + offset[0], first[1] + offset[1]),
             (second[0] + offset[0], second[1] + offset[1])],
            fill=fill,
            width=width,
        )

    shadow_width = max(8, round(canvas * 0.036))
    mark_width = max(6, round(canvas * 0.027))
    shadow_offset = (0, round(canvas * 0.012))
    shadow = (35, 87, 130)
    for edge in cube_edges:
        line(outer_points, edge, shadow, shadow_width, shadow_offset)
        line(inner_points, edge, shadow, shadow_width, shadow_offset)
    for outer_index, inner_index in connector_edges:
        draw.line(
            [
                (outer_points[outer_index][0] + shadow_offset[0], outer_points[outer_index][1] + shadow_offset[1]),
                (inner_points[inner_index][0] + shadow_offset[0], inner_points[inner_index][1] + shadow_offset[1]),
            ],
            fill=shadow,
            width=shadow_width,
        )

    connector = (236, 247, 255)
    for outer_index, inner_index in connector_edges:
        draw.line(
            [outer_points[outer_index], inner_points[inner_index]],
            fill=connector,
            width=mark_width,
        )
    for edge in cube_edges:
        line(outer_points, edge, (255, 255, 255), mark_width)
        line(inner_points, edge, (255, 255, 255), mark_width)

    return image.resize((size, size), Image.Resampling.LANCZOS)


def expected_assets() -> dict[Path, Image.Image]:
    assets = {IOS_SET / "icon-1024.png": render(1024)}
    assets.update({MAC_SET / f"icon-{size}.png": render(size) for size in MAC_SIZES})
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
    print("App icons valid: deterministic blue RGB assets with no alpha channel.")
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
