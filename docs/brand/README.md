# 3DSeen brand assets

The approved identity is the user's wireframe cube, refreshed as a white mark on blueprint blue (`#1E58DC`) across macOS, iPhone, and iPad. `3dseen-cube-reference.png` preserves the supplied artwork; `3dseen-cube.svg` traces its geometry as a scalable white foreground layer. `3dseen-blueprint.svg` adds the blue background for flat brand assets.

`Sources/Shared/DesignSystem/3DSeenIcon.icon` is the native Apple Icon Composer document used by both app targets. It was created and imported in Icon Composer, then refined with explicit default and dark fills. Apple applies the platform mask and generates compatible icons for older supported OS versions. Native preview exports are retained here for macOS, iOS, and dark appearance. Mono/tinted variants follow the user's system appearance preferences.

Run `rsvg-convert docs/brand/3dseen-blueprint.svg -o docs/brand/3dseen-blueprint-master.png` and `python3 tools/assets/generate-app-icons.py` to refresh the opaque catalog and in-app assets. Use `--check` to verify deterministic pixels, and `python3 tools/assets/validate-app-icons.py` to validate dimensions, opacity, and the shared Icon Composer document.

Earlier aperture and tesseract artwork is retained as historical reference and is no longer the current identity.
