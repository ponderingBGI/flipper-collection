# Development Workflow

This repo uses uFBT for a mainstream Flipper app workflow.

## Prerequisites
- Python 3 installed
- `pip install --upgrade ufbt` (or use the included `venv`)

## Build & Test (local)
1. Open a terminal in `apps/mouse-jiggler/fap`
2. Install toolchain files:
   - `ufbt vscode_dist`
3. Lint & format:
   - `ufbt lint`
   - `ufbt format`
4. Build:
   - `ufbt build`
5. Optional: Launch to device over USB:
   - `ufbt launch`

## Pull Requests
- CI builds for dev & release and runs `ufbt lint`.
- Fix any CI failures before requesting review.

## Packaging
- On merge to `main`, GitHub Actions builds the app and places the packaged `.fap` under `packages/Tools/`.
- Root README links to these folders for easy drag-and-drop onto the Flipper.
