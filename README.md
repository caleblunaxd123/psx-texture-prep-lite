# PSX Texture Prep Lite

Version 1.0.0 · Author: Luna Tile Works · License: MIT · Godot 4.7+ (tested on 4.7.2)

PSX Texture Prep Lite prepares **textures** for a PlayStation-style look by changing the pixels of the image files themselves. It works in batches, from a source folder to a destination folder, and offers three steps:

1. **Fit to a power of two** (nearest, crop, or pad), with nearest-neighbor resampling.
2. **Reduce color**, either to 15-bit RGB555 or to a palette of 2–256 colors (median cut).
3. **Bake a 4×4 Bayer dither** into the pixels.

The results are deterministic: the same input and options always produce the same bytes.

## Install

Copy the `addons/psx_texture_prep` folder into your project's `addons/` folder, then enable **PSX Texture Prep Lite** in *Project > Project Settings > Plugins*. The API classes work even if the plugin is not enabled.

## Use from the editor

Right-click a folder in the FileSystem dock and choose one of:

- **PSX Texture Prep: Process Folder (RGB555)**
- **PSX Texture Prep: Process Folder (16-color palette)**

The converted PNG files are written to a sibling folder named `<folder>_psx`, keeping the sub-folder layout. Your originals are never modified. Existing files in the destination are skipped (the menu does not overwrite). To process again after you change a source, delete that file from `<folder>_psx` or call `PsxBatch.process_folder` with `"overwrite": true`.

## Use from code

```gdscript
var img := Image.load_from_file("res://textures/wall.png")

# 100x60 -> 128x64 (MODE_CROP gives 64x32, MODE_PAD gives 128x64 with transparent padding)
var fitted := PsxTexturePrep.fit_pow2(img, PsxTexturePrep.MODE_NEAREST_POW2, 256)

var rgb555 := PsxTexturePrep.to_rgb555(fitted, true)           # dither on

var result := PsxTexturePrep.to_palette(fitted, 16, true)      # 16 colors, dither on
var paletted: Image = result["image"]
var palette: PackedColorArray = result["palette"]

# Whole folders (outside src, never overwrites originals):
var report := PsxBatch.process_folder("res://textures", "res://textures_psx", {
	"mode": PsxTexturePrep.MODE_NEAREST_POW2,
	"max_side": 256,
	"color_mode": "palette",     # or "rgb555"
	"palette_colors": 16,
	"dither": true,
	"alpha_threshold": 0.5,
	"overwrite": false,
})
# report = { ok, error, processed: [...], omitted: [...], errors: [...] }
```

Details:

- `fit_pow2` handles each side separately. No side exceeds `max_side` (rounded down to a power of two). `MODE_PAD` centers the original pixels without scaling and fills the rest with transparent pixels.
- `to_rgb555` keeps 5 bits per channel and expands them by bit replication. With dither, a Bayer offset of `(bayer / 16 - 0.5) * 8` is added before quantizing.
- `to_palette` builds the palette from opaque pixels only. Transparent pixels keep alpha 0.
- Alpha is binary: values at or above `alpha_threshold * 255` become opaque.
- Inputs are never modified; every function returns a copy.

## Limits

- This is **not** a PSX shader. It does not snap vertices, add affine texture mapping, or add fog.
- It does **not** assign materials or convert meshes and scenes.
- It does **not** hook into Godot's native importer. The workflow is source folder → destination folder, so you re-run it when your sources change.
- Free converters for PSX-style textures exist outside Godot. The point of this addon is to run inside the editor and in batches.
- The editor menu code has not been exercised in a running editor session; the API and batch function are covered by `tests/verify.gd`.
- Processing runs synchronously in GDScript on the editor's main thread. A folder of large (for example 1024×1024) textures can freeze the editor for a few seconds, with no progress bar.
- The addon does not use the network and sends no telemetry.

## Tests

```
godot --headless --path . --script tests/verify.gd
```

The script prints `PASS` or `FAIL` per case and exits with code 0 only if everything passes. It also writes `tests/verify_report.txt`.

## Español (breve)

Addon gratuito que prepara texturas por lotes con estética PS1: ajuste a potencia de 2, reducción a RGB555 o a una paleta de N colores y dither Bayer 4×4 horneado en los píxeles. Clic derecho en una carpeta del panel FileSystem; el resultado va a `<carpeta>_psx` y nunca toca los originales. No es un shader ni asigna materiales.

## AI disclosure

The code and text in this project were generated with the help of an AI assistant (Claude, by Anthropic) and reviewed by the author.

## License

MIT. See `LICENSE`. Copyright (c) 2026 Luna Tile Works.
